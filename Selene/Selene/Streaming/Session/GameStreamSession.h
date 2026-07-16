#import <Foundation/Foundation.h>
#import "VideoDecodeRenderer.h"
#import "AudioDecodeRenderer.h"

NS_ASSUME_NONNULL_BEGIN

/// Reports `LiStartConnection`'s progress back to Swift. All methods are
/// invoked on the main queue. This milestone only wires up connectivity -
/// no video/audio/input callbacks do anything real yet (see
/// `GameStreamSession.mm`'s stub `DECODER_RENDERER_CALLBACKS`/
/// `AUDIO_RENDERER_CALLBACKS`).
@protocol GameStreamSessionDelegate <NSObject>
- (void)gameStreamSessionStageStarting:(NSString *)stage;
- (void)gameStreamSessionStageComplete:(NSString *)stage;
- (void)gameStreamSessionStageFailed:(NSString *)stage errorCode:(int)errorCode;
- (void)gameStreamSessionConnectionStarted;
- (void)gameStreamSessionConnectionTerminatedWithErrorCode:(int)errorCode;
@optional
- (void)gameStreamSessionLogMessage:(NSString *)message;
@end

/// Wraps `LiStartConnection` (moonlight-common-c) - the actual GameStream
/// protocol connection (RTSP handshake + ENet control stream + RTP
/// video/audio depacketization). `LiStartConnection` blocks until connected
/// or failed, so `start...` runs it on a background queue and reports back
/// via the delegate.
///
/// moonlight-common-c only supports one active connection per process (its
/// state is process-global, matching every other Moonlight client), so only
/// one `GameStreamSession` should be started at a time.
@interface GameStreamSession : NSObject

- (instancetype)initWithDelegate:(id<GameStreamSessionDelegate>)delegate
                    videoRenderer:(VideoDecodeRenderer *)videoRenderer
                    audioRenderer:(AudioDecodeRenderer *)audioRenderer;

- (void)startWithAddress:(NSString *)address
         serverAppVersion:(NSString *)serverAppVersion
           rtspSessionUrl:(nullable NSString *)rtspSessionUrl
                    width:(int)width
                   height:(int)height
                      fps:(int)fps
              bitrateKbps:(int)bitrateKbps
        remoteInputAesKey:(NSData *)remoteInputAesKey
         remoteInputAesIv:(NSData *)remoteInputAesIv
         audioChannelCount:(int)audioChannelCount
          audioChannelMask:(int)audioChannelMask
                packetSize:(int)packetSize;

- (void)stop;

@end

NS_ASSUME_NONNULL_END
