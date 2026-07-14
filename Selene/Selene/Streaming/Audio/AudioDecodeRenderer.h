#import <Foundation/Foundation.h>
#import "Limelight.h"

NS_ASSUME_NONNULL_BEGIN

/// Decodes moonlight-common-c's raw Opus packets to PCM using the system's
/// native Opus codec (`kAudioFormatOpus` via `AudioConverter` -
/// `AudioToolbox`) and plays them through `AVAudioEngine`. No third-party
/// audio codec library needed - Apple ships Opus decode support directly,
/// the same way VideoToolbox covers H.264 decode for video.
@interface AudioDecodeRenderer : NSObject

/// Called from `AUDIO_RENDERER_CALLBACKS.init`. Returns 0 on success.
- (int)setupWithOpusConfig:(POPUS_MULTISTREAM_CONFIGURATION)opusConfig;

- (void)start;
- (void)stop;

/// Called from `AUDIO_RENDERER_CALLBACKS.decodeAndPlaySample` - `sampleData`
/// is one raw (still Opus-encoded) audio packet, `sampleLength` bytes long.
- (void)decodeAndPlaySample:(const char *)sampleData length:(int)sampleLength;

- (void)reset;

@end

NS_ASSUME_NONNULL_END
