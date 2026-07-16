import GameController
import os

private let gamepadLogger = Logger(subsystem: "ch.polonium.selene", category: "gamepad")

/// Tracks connected `GCController`s (DualSense, DualShock 4, Xbox, and any
/// other MFi/HID gamepad macOS recognizes natively) and forwards their
/// standard button/stick/trigger state to the host via moonlight-common-c's
/// `LiSendControllerArrivalEvent`/`LiSendMultiControllerEvent` (declared in
/// Limelight.h, already available here through the bridging header, same as
/// `InputForwarder`'s keyboard/mouse calls).
///
/// Split into two lifecycles on purpose:
///  - Connect/disconnect tracking (slot assignment, `mask`) runs continuously
///    from app launch, independent of whether a stream is active - `mask`
///    must already be correct by the time `GameStreamClient.launchApp` reads
///    `attachedGamepadMask`, which happens *before* any `GameStreamSession`
///    exists.
///  - Actual forwarding to the host (`LiSendControllerArrivalEvent` /
///    `valueChangedHandler` wiring) only runs between `start()` and `stop()`,
///    which `StreamConnectionController` calls alongside `inputForwarder`.
@MainActor
final class GamepadForwarder {
    static let shared = GamepadForwarder()

    /// Read by `GameStreamClient.launchApp` before the connection even
    /// starts, so the host's launch request already reflects what's plugged
    /// in - mirrors the legacy Qt client's `getAttachedGamepadMask()`.
    static var attachedGamepadMask: Int16 { Int16(shared.mask) }

    private static let maxControllers = 4

    private var slots: [ObjectIdentifier: Int] = [:]
    private var mask = 0
    private var isForwarding = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        let center = NotificationCenter.default
        observers = [
            // `queue: .main` guarantees these run on the main thread at
            // runtime, but NotificationCenter's `using:` closure type is
            // plain `@Sendable`, not `@MainActor`, and `GCController`/
            // `Notification` aren't `Sendable` - rather than fight the
            // compiler over sending the notification's object across that
            // boundary, the handlers ignore it and just re-sync against
            // `GCController.controllers()` (read fresh, inside the isolated
            // block, so nothing non-Sendable ever crosses). `assumeIsolated`
            // proves the `queue: .main` runtime guarantee to the compiler,
            // same pattern already used in StreamConnectionController's
            // delegate callbacks.
            center.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.syncControllers()
                }
            },
            center.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.syncControllers()
                }
            },
        ]
        syncControllers()
    }

    func start() {
        guard !isForwarding else { return }
        isForwarding = true
        for (id, index) in slots {
            guard let controller = GCController.controllers().first(where: { ObjectIdentifier($0) == id }) else { continue }
            sendArrival(controller: controller, index: index)
            armHandler(controller: controller, index: index)
        }
    }

    func stop() {
        guard isForwarding else { return }
        isForwarding = false
        for controller in GCController.controllers() {
            controller.extendedGamepad?.valueChangedHandler = nil
        }
    }

    // MARK: - Connect/disconnect tracking (always on)

    /// Reconciles `slots`/`mask` against the live `GCController.controllers()`
    /// list. Called on init and on every connect/disconnect notification -
    /// re-deriving full state from scratch each time is simpler and more
    /// robust than trying to thread the specific added/removed controller
    /// through a `Sendable` boundary from the notification handlers.
    private func syncControllers() {
        let current = GCController.controllers().filter { $0.extendedGamepad != nil }
        let currentIds = Set(current.map(ObjectIdentifier.init))

        for (id, index) in slots where !currentIds.contains(id) {
            slots.removeValue(forKey: id)
            mask &= ~(1 << index)
            gamepadLogger.notice("controller disconnected: slot=\(index, privacy: .public)")
            if isForwarding {
                LiSendMultiControllerEvent(Int16(index), Int16(mask), 0, 0, 0, 0, 0, 0, 0)
            }
        }

        for controller in current {
            let id = ObjectIdentifier(controller)
            guard slots[id] == nil else { continue }

            let used = Set(slots.values)
            guard let index = (0..<Self.maxControllers).first(where: { !used.contains($0) }) else {
                gamepadLogger.notice("ignoring controller, already at max of \(Self.maxControllers, privacy: .public)")
                continue
            }

            slots[id] = index
            mask |= (1 << index)
            gamepadLogger.notice("controller connected: \(controller.vendorName ?? "unknown", privacy: .public) slot=\(index, privacy: .public)")

            if isForwarding {
                sendArrival(controller: controller, index: index)
                armHandler(controller: controller, index: index)
            }
        }
    }

    // MARK: - Forwarding (only while streaming)

    private func armHandler(controller: GCController, index: Int) {
        controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, _ in
            self?.sendState(gamepad: gamepad, index: index)
        }
    }

    private func sendArrival(controller: GCController, index: Int) {
        guard let gamepad = controller.extendedGamepad else { return }

        var supportedButtonFlags: UInt32 = 0
        supportedButtonFlags |= UInt32(UP_FLAG) | UInt32(DOWN_FLAG) | UInt32(LEFT_FLAG) | UInt32(RIGHT_FLAG)
        supportedButtonFlags |= UInt32(A_FLAG) | UInt32(B_FLAG) | UInt32(X_FLAG) | UInt32(Y_FLAG)
        supportedButtonFlags |= UInt32(LB_FLAG) | UInt32(RB_FLAG) | UInt32(PLAY_FLAG)
        if gamepad.leftThumbstickButton != nil { supportedButtonFlags |= UInt32(LS_CLK_FLAG) }
        if gamepad.rightThumbstickButton != nil { supportedButtonFlags |= UInt32(RS_CLK_FLAG) }
        if gamepad.buttonOptions != nil { supportedButtonFlags |= UInt32(BACK_FLAG) }
        if gamepad.buttonHome != nil { supportedButtonFlags |= UInt32(SPECIAL_FLAG) }

        let type: UInt8
        switch controller.productCategory {
        case GCProductCategoryDualSense, GCProductCategoryDualShock4:
            type = UInt8(LI_CTYPE_PS)
        case GCProductCategoryXboxOne:
            type = UInt8(LI_CTYPE_XBOX)
        default:
            type = UInt8(LI_CTYPE_UNKNOWN)
        }

        LiSendControllerArrivalEvent(
            UInt8(index),
            UInt16(mask),
            type,
            supportedButtonFlags,
            UInt16(LI_CCAP_ANALOG_TRIGGERS)
        )
    }

    private func sendState(gamepad: GCExtendedGamepad, index: Int) {
        var buttons: Int32 = 0
        if gamepad.dpad.up.isPressed { buttons |= Int32(UP_FLAG) }
        if gamepad.dpad.down.isPressed { buttons |= Int32(DOWN_FLAG) }
        if gamepad.dpad.left.isPressed { buttons |= Int32(LEFT_FLAG) }
        if gamepad.dpad.right.isPressed { buttons |= Int32(RIGHT_FLAG) }
        if gamepad.buttonA.isPressed { buttons |= Int32(A_FLAG) }
        if gamepad.buttonB.isPressed { buttons |= Int32(B_FLAG) }
        if gamepad.buttonX.isPressed { buttons |= Int32(X_FLAG) }
        if gamepad.buttonY.isPressed { buttons |= Int32(Y_FLAG) }
        if gamepad.leftShoulder.isPressed { buttons |= Int32(LB_FLAG) }
        if gamepad.rightShoulder.isPressed { buttons |= Int32(RB_FLAG) }
        if gamepad.buttonMenu.isPressed { buttons |= Int32(PLAY_FLAG) }
        if gamepad.buttonOptions?.isPressed == true { buttons |= Int32(BACK_FLAG) }
        if gamepad.buttonHome?.isPressed == true { buttons |= Int32(SPECIAL_FLAG) }
        if gamepad.leftThumbstickButton?.isPressed == true { buttons |= Int32(LS_CLK_FLAG) }
        if gamepad.rightThumbstickButton?.isPressed == true { buttons |= Int32(RS_CLK_FLAG) }

        let leftTrigger = UInt8(clamping: Int(gamepad.leftTrigger.value * 255))
        let rightTrigger = UInt8(clamping: Int(gamepad.rightTrigger.value * 255))
        let lsX = Int16(clamping: Int(gamepad.leftThumbstick.xAxis.value * 32767))
        let lsY = Int16(clamping: Int(gamepad.leftThumbstick.yAxis.value * 32767))
        let rsX = Int16(clamping: Int(gamepad.rightThumbstick.xAxis.value * 32767))
        let rsY = Int16(clamping: Int(gamepad.rightThumbstick.yAxis.value * 32767))

        LiSendMultiControllerEvent(Int16(index), Int16(mask), buttons, leftTrigger, rightTrigger, lsX, lsY, rsX, rsY)
    }
}
