#import "GameStreamSession.h"
#import "Limelight.h"

#include <stdarg.h>

// moonlight-common-c's callbacks are plain C function pointers - they can't
// capture `self` - so we keep a process-wide pointer to whichever session is
// currently active. This matches moonlight-common-c's own one-connection-
// per-process model (see GameStreamSession.h).
static GameStreamSession *currentSession = nil;

// LiStartConnection/LiStopConnection share process-global state in
// moonlight-common-c, so a start() and a stop() (e.g. backgrounding a stream
// and immediately resuming) must never run concurrently with each other.
// dispatch_get_global_queue() is a CONCURRENT queue - two blocks dispatched
// to it, even back to back, can run on different threads at the same time,
// which let a fresh LiStartConnection race an in-flight LiStopConnection and
// fail with no useful error. A dedicated serial queue guarantees stop()
// fully finishes before the next start() begins.
static dispatch_queue_t gameStreamSessionQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("ch.polonium.selene.gamestream-session", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

@implementation GameStreamSession {
    __weak id<GameStreamSessionDelegate> _delegate;
    VideoDecodeRenderer *_videoRenderer;
    AudioDecodeRenderer *_audioRenderer;
}

- (instancetype)initWithDelegate:(id<GameStreamSessionDelegate>)delegate
                    videoRenderer:(VideoDecodeRenderer *)videoRenderer
                    audioRenderer:(AudioDecodeRenderer *)audioRenderer {
    self = [super init];
    if (self) {
        _delegate = delegate;
        _videoRenderer = videoRenderer;
        _audioRenderer = audioRenderer;
    }
    return self;
}

#pragma mark - CONNECTION_LISTENER_CALLBACKS (stubs that just report to the delegate)

static void connListenerStageStarting(int stage) {
    id<GameStreamSessionDelegate> delegate = currentSession ? currentSession->_delegate : nil;
    NSString *stageName = [NSString stringWithUTF8String:LiGetStageName(stage)];
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate gameStreamSessionStageStarting:stageName];
    });
}

static void connListenerStageComplete(int stage) {
    id<GameStreamSessionDelegate> delegate = currentSession ? currentSession->_delegate : nil;
    NSString *stageName = [NSString stringWithUTF8String:LiGetStageName(stage)];
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate gameStreamSessionStageComplete:stageName];
    });
}

static void connListenerStageFailed(int stage, int errorCode) {
    id<GameStreamSessionDelegate> delegate = currentSession ? currentSession->_delegate : nil;
    NSString *stageName = [NSString stringWithUTF8String:LiGetStageName(stage)];
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate gameStreamSessionStageFailed:stageName errorCode:errorCode];
    });
}

static void connListenerConnectionStarted(void) {
    id<GameStreamSessionDelegate> delegate = currentSession ? currentSession->_delegate : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate gameStreamSessionConnectionStarted];
    });
}

static void connListenerConnectionTerminated(int errorCode) {
    id<GameStreamSessionDelegate> delegate = currentSession ? currentSession->_delegate : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate gameStreamSessionConnectionTerminatedWithErrorCode:errorCode];
    });
}

static void connListenerLogMessage(const char *format, ...) {
    va_list args;
    va_start(args, format);
    char buffer[1024];
    vsnprintf(buffer, sizeof(buffer), format, args);
    va_end(args);

    id<GameStreamSessionDelegate> delegate = currentSession ? currentSession->_delegate : nil;
    if (![delegate respondsToSelector:@selector(gameStreamSessionLogMessage:)]) {
        return;
    }
    NSString *message = [NSString stringWithUTF8String:buffer];
    dispatch_async(dispatch_get_main_queue(), ^{
        [delegate gameStreamSessionLogMessage:message];
    });
}

#pragma mark - DECODER_RENDERER_CALLBACKS (routes to VideoDecodeRenderer)

static int drSetup(int videoFormat, int width, int height, int redrawRate, void *context, int drFlags) {
    NSLog(@"[GameStreamSession] drSetup format=%d %dx%d@%d", videoFormat, width, height, redrawRate);
    return 0;
}

static void drStart(void) {
    NSLog(@"[GameStreamSession] drStart");
}
static void drStop(void) {
    NSLog(@"[GameStreamSession] drStop");
}
static void drCleanup(void) {}

static int drSubmitDecodeUnit(PDECODE_UNIT decodeUnit) {
    VideoDecodeRenderer *renderer = currentSession ? currentSession->_videoRenderer : nil;
    if (renderer == nil) {
        return DR_OK;
    }
    return [renderer submitDecodeUnit:decodeUnit];
}

#pragma mark - AUDIO_RENDERER_CALLBACKS (routes to AudioDecodeRenderer)

static int arInit(int audioConfiguration, const POPUS_MULTISTREAM_CONFIGURATION opusConfig, void *context, int arFlags) {
    AudioDecodeRenderer *renderer = currentSession ? currentSession->_audioRenderer : nil;
    if (renderer == nil) {
        return 0;
    }
    return [renderer setupWithOpusConfig:opusConfig];
}

static void arStart(void) {
    AudioDecodeRenderer *renderer = currentSession ? currentSession->_audioRenderer : nil;
    [renderer start];
}

static void arStop(void) {
    AudioDecodeRenderer *renderer = currentSession ? currentSession->_audioRenderer : nil;
    [renderer stop];
}

static void arCleanup(void) {}

static void arDecodeAndPlaySample(char *sampleData, int sampleLength) {
    AudioDecodeRenderer *renderer = currentSession ? currentSession->_audioRenderer : nil;
    [renderer decodeAndPlaySample:sampleData length:sampleLength];
}

#pragma mark - Public API

- (void)startWithAddress:(NSString *)address
         serverAppVersion:(NSString *)serverAppVersion
           rtspSessionUrl:(nullable NSString *)rtspSessionUrl
                    width:(int)width
                   height:(int)height
                      fps:(int)fps
              bitrateKbps:(int)bitrateKbps
        remoteInputAesKey:(NSData *)remoteInputAesKey
         remoteInputAesIv:(NSData *)remoteInputAesIv
{
    currentSession = self;

    NSString *addressCopy = [address copy];
    NSString *serverAppVersionCopy = [serverAppVersion copy];
    NSString *rtspSessionUrlCopy = [rtspSessionUrl copy];
    NSData *aesKeyCopy = [remoteInputAesKey copy];
    NSData *aesIvCopy = [remoteInputAesIv copy];

    dispatch_async(gameStreamSessionQueue(), ^{
        const char *addressCStr = strdup(addressCopy.UTF8String);
        const char *appVersionCStr = strdup(serverAppVersionCopy.UTF8String);
        const char *rtspCStr = rtspSessionUrlCopy ? strdup(rtspSessionUrlCopy.UTF8String) : NULL;

        SERVER_INFORMATION serverInfo = {0};
        serverInfo.address = addressCStr;
        serverInfo.serverInfoAppVersion = appVersionCStr;
        serverInfo.rtspSessionUrl = rtspCStr;
        // Required to be non-zero or LiStartConnection bails out before ever
        // invoking a single callback (silently, with no connectionTerminated
        // either - this bit us during hardware validation). We only request
        // VIDEO_FORMAT_H264 below, and every Sunshine host supports it, so
        // this hardcoded value is safe for now. A future revision should
        // parse the real <ServerCodecModeSupport> value from /serverinfo.
        serverInfo.serverCodecModeSupport = SCM_H264;

        STREAM_CONFIGURATION streamConfig = {0};
        streamConfig.width = width;
        streamConfig.height = height;
        streamConfig.fps = fps;
        streamConfig.bitrate = bitrateKbps;
        streamConfig.packetSize = 1024;
        streamConfig.streamingRemotely = STREAM_CFG_AUTO;
        streamConfig.audioConfiguration = AUDIO_CONFIGURATION_STEREO;
        streamConfig.supportedVideoFormats = VIDEO_FORMAT_H264;
        streamConfig.encryptionFlags = ENCFLG_NONE;
        memcpy(streamConfig.remoteInputAesKey, aesKeyCopy.bytes, MIN(aesKeyCopy.length, sizeof(streamConfig.remoteInputAesKey)));
        memcpy(streamConfig.remoteInputAesIv, aesIvCopy.bytes, MIN(aesIvCopy.length, sizeof(streamConfig.remoteInputAesIv)));

        CONNECTION_LISTENER_CALLBACKS connCallbacks = {0};
        connCallbacks.stageStarting = connListenerStageStarting;
        connCallbacks.stageComplete = connListenerStageComplete;
        connCallbacks.stageFailed = connListenerStageFailed;
        connCallbacks.connectionStarted = connListenerConnectionStarted;
        connCallbacks.connectionTerminated = connListenerConnectionTerminated;
        connCallbacks.logMessage = connListenerLogMessage;

        DECODER_RENDERER_CALLBACKS drCallbacks = {0};
        drCallbacks.setup = drSetup;
        drCallbacks.start = drStart;
        drCallbacks.stop = drStop;
        drCallbacks.cleanup = drCleanup;
        drCallbacks.submitDecodeUnit = drSubmitDecodeUnit;
        drCallbacks.capabilities = 0;

        AUDIO_RENDERER_CALLBACKS arCallbacks = {0};
        arCallbacks.init = arInit;
        arCallbacks.start = arStart;
        arCallbacks.stop = arStop;
        arCallbacks.cleanup = arCleanup;
        arCallbacks.decodeAndPlaySample = arDecodeAndPlaySample;
        arCallbacks.capabilities = 0;

        int result = LiStartConnection(&serverInfo, &streamConfig, &connCallbacks, &drCallbacks, &arCallbacks, NULL, 0, NULL, 0);
        if (result != 0) {
            id<GameStreamSessionDelegate> delegate = currentSession ? currentSession->_delegate : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [delegate gameStreamSessionStageFailed:@"LiStartConnection" errorCode:result];
            });
        }

        free((void *)addressCStr);
        free((void *)appVersionCStr);
        if (rtspCStr) {
            free((void *)rtspCStr);
        }
    });
}

- (void)stop {
    dispatch_async(gameStreamSessionQueue(), ^{
        LiStopConnection();
    });
}

@end
