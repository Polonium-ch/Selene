import AppKit
import CoreGraphics
import os

private let inputLogger = Logger(subsystem: "ch.polonium.selene", category: "input")

/// Captures local keyboard/mouse events while a stream is active and forwards
/// them to the host via moonlight-common-c's LiSend*Event() calls (declared
/// in Limelight.h, already available here through the bridging header - no
/// extra Objective-C++ shim needed since these are plain C functions).
///
/// Uses `NSEvent.addLocalMonitorForEvents` (AppKit) to capture events, and
/// `CGAssociateMouseAndMouseCursorPosition` (Core Graphics) to decouple the
/// system cursor from mouse motion while streaming - the standard
/// "relative/captured mouse" trick every native mouse-look app uses - with
/// the cursor hidden the whole time. The video content already shows the
/// host's own cursor baked into the frame (Sunshine captures it as part of
/// the desktop image), so there's no reason to also show a second, unsynced
/// local cursor.
///
/// Both the event capture and the cursor hide/disassociate are scoped to
/// `targetWindow` actually being key, not just to this object being
/// "started" - the stream keeps running when backgrounded (see
/// StreamWindowView.backgroundWindow), so without this check every keypress
/// and mouse move made in some *other* Selene window (e.g. the app grid,
/// reached by switching Spaces away from the still-fullscreen stream) would
/// otherwise still get hijacked and forwarded to the host instead of
/// reaching the window the user is actually looking at.
@MainActor
final class InputForwarder {
    private var monitor: Any?
    private var windowObservers: [NSObjectProtocol] = []
    private var heldModifierKeyCodes: Set<UInt16> = []
    private var isCaptureActive = false

    /// The window whose focus state gates capture - set this before/as soon
    /// as the stream's NSWindow is known, ideally before `start()`.
    weak var targetWindow: NSWindow?

    /// Fired on Ctrl+Option+Shift+Q - matches real Moonlight/Sunshine
    /// clients' "background this stream" hotkey.
    var onBackgroundRequested: (() -> Void)?

    func start() {
        guard monitor == nil else { return }

        let center = NotificationCenter.default
        windowObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let window = note.object as? NSWindow, window === self.targetWindow else { return }
                self.setCaptureActive(true)
            },
            center.addObserver(forName: NSWindow.didResignKeyNotification, object: nil, queue: .main) { [weak self] note in
                guard let self, let window = note.object as? NSWindow, window === self.targetWindow else { return }
                self.setCaptureActive(false)
            },
        ]
        // Covers the common case where targetWindow is already key by the
        // time this runs (start() fires once the connection is fully up,
        // well after the window itself became key) - the notifications
        // above only fire on future transitions, not this already-past one.
        if targetWindow?.isKeyWindow == true {
            setCaptureActive(true)
        }

        monitor = NSEvent.addLocalMonitorForEvents(matching: [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp,
            .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
            .scrollWheel,
        ]) { [weak self] event in
            guard let self, self.isCaptureActive else { return event }

            if event.type == .keyDown, self.isBackgroundHotkey(event) {
                self.onBackgroundRequested?()
                return nil
            }

            self.handle(event)
            return nil // swallow everything so it doesn't also affect our own UI/system
        }

        inputLogger.notice("input capture started")
    }

    func stop() {
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
        setCaptureActive(false)

        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        heldModifierKeyCodes.removeAll()

        inputLogger.notice("input capture stopped")
    }

    private func setCaptureActive(_ active: Bool) {
        guard active != isCaptureActive else { return }
        isCaptureActive = active
        if active {
            CGAssociateMouseAndMouseCursorPosition(0)
            CGDisplayHideCursor(CGMainDisplayID())
        } else {
            CGAssociateMouseAndMouseCursorPosition(1)
            CGDisplayShowCursor(CGMainDisplayID())
        }
    }

    private func isBackgroundHotkey(_ event: NSEvent) -> Bool {
        let requiredFlags: NSEvent.ModifierFlags = [.control, .option, .shift]
        return event.keyCode == 0x0C /* Q */ && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == requiredFlags
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            guard !event.isARepeat else { return }
            forwardKey(event, down: true)
        case .keyUp:
            forwardKey(event, down: false)
        case .flagsChanged:
            forwardFlagsChanged(event)
        case .leftMouseDown:
            forwardMouseButton(BUTTON_LEFT, down: true)
        case .leftMouseUp:
            forwardMouseButton(BUTTON_LEFT, down: false)
        case .rightMouseDown:
            forwardMouseButton(BUTTON_RIGHT, down: true)
        case .rightMouseUp:
            forwardMouseButton(BUTTON_RIGHT, down: false)
        case .otherMouseDown:
            forwardOtherMouseButton(event, down: true)
        case .otherMouseUp:
            forwardOtherMouseButton(event, down: false)
        case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            forwardMouseMove(event)
        case .scrollWheel:
            forwardScroll(event)
        default:
            break
        }
    }

    // MARK: - Keyboard

    private func forwardKey(_ event: NSEvent, down: Bool) {
        guard let vk = KeyCodeMap.winVirtualKey(for: event.keyCode) else { return }
        sendKey(vk: vk, down: down, modifierFlags: event.modifierFlags)
    }

    private func forwardFlagsChanged(_ event: NSEvent) {
        guard let vk = KeyCodeMap.winVirtualKey(for: event.keyCode) else { return }

        let genericFlag: NSEvent.ModifierFlags
        switch event.keyCode {
        case 0x38, 0x3C: genericFlag = .shift
        case 0x3B, 0x3E: genericFlag = .control
        case 0x3A, 0x3D: genericFlag = .option
        case 0x37, 0x36: genericFlag = .command
        case 0x39: genericFlag = .capsLock
        default: return
        }

        let isSet = event.modifierFlags.contains(genericFlag)
        let wasHeld = heldModifierKeyCodes.contains(event.keyCode)
        guard isSet != wasHeld else { return }

        if isSet {
            heldModifierKeyCodes.insert(event.keyCode)
        } else {
            heldModifierKeyCodes.remove(event.keyCode)
        }
        sendKey(vk: vk, down: isSet, modifierFlags: event.modifierFlags)
    }

    private func sendKey(vk: Int16, down: Bool, modifierFlags: NSEvent.ModifierFlags) {
        var modifiers: Int32 = 0
        if modifierFlags.contains(.shift) { modifiers |= MODIFIER_SHIFT }
        if modifierFlags.contains(.control) { modifiers |= MODIFIER_CTRL }
        if modifierFlags.contains(.option) { modifiers |= MODIFIER_ALT }
        if modifierFlags.contains(.command) { modifiers |= MODIFIER_META }

        LiSendKeyboardEvent(vk, Int8(down ? KEY_ACTION_DOWN : KEY_ACTION_UP), Int8(modifiers))
    }

    // MARK: - Mouse buttons

    private func forwardMouseButton(_ button: Int32, down: Bool) {
        LiSendMouseButtonEvent(Int8(down ? BUTTON_ACTION_PRESS : BUTTON_ACTION_RELEASE), button)
    }

    private func forwardOtherMouseButton(_ event: NSEvent, down: Bool) {
        let button: Int32
        switch event.buttonNumber {
        case 2: button = BUTTON_MIDDLE
        case 3: button = BUTTON_X1
        case 4: button = BUTTON_X2
        default: return
        }
        forwardMouseButton(button, down: down)
    }

    // MARK: - Mouse motion & scroll

    private func forwardMouseMove(_ event: NSEvent) {
        let deltaX = Int16(clamping: Int(event.deltaX.rounded()))
        let deltaY = Int16(clamping: Int(event.deltaY.rounded()))
        guard deltaX != 0 || deltaY != 0 else { return }
        LiSendMouseMoveEvent(deltaX, deltaY)
    }

    // macOS applies its own scroll acceleration curve to trackpad scrollingDelta,
    // which can spike to huge values on a fast flick. Clamping to [-1, 1] per
    // event before scaling by WHEEL_DELTA (120) discards that acceleration and
    // relies on event frequency instead, matching the legacy Qt client's
    // macOS-specific fix for the same "wild scroll deltas" issue.
    private static let wheelDelta: Double = 120

    private func forwardScroll(_ event: NSEvent) {
        if event.scrollingDeltaY != 0 {
            let clamped = min(max(event.scrollingDeltaY, -1), 1)
            LiSendHighResScrollEvent(Int16(clamping: Int((clamped * Self.wheelDelta).rounded())))
        }
        if event.scrollingDeltaX != 0 {
            let clamped = min(max(event.scrollingDeltaX, -1), 1)
            LiSendHighResHScrollEvent(Int16(clamping: Int((clamped * Self.wheelDelta).rounded())))
        }
    }
}
