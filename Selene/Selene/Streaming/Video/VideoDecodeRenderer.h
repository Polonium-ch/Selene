#import <AVFoundation/AVFoundation.h>
#import "Limelight.h"

NS_ASSUME_NONNULL_BEGIN

/// Converts moonlight-common-c's raw Annex-B H.264 `DECODE_UNIT`s into
/// AVCC-formatted `CMSampleBuffer`s and feeds them to an
/// `AVSampleBufferDisplayLayer`, which decodes (via VideoToolbox
/// internally) and presents them.
///
/// This is deliberately the simple path: `AVSampleBufferDisplayLayer` owns
/// decode + timing + presentation once fed a well-formed sample buffer, so
/// there's no manual `VTDecompressionSession`/Metal render loop to write.
/// The tradeoff is less control over post-processing (custom scaling
/// filters, HDR tone-mapping, etc) - revisit with a manual
/// `VTDecompressionSession` + Metal pipeline only if that's ever needed.
@interface VideoDecodeRenderer : NSObject

@property (nonatomic, readonly) AVSampleBufferDisplayLayer *displayLayer;

/// Called from `DECODER_RENDERER_CALLBACKS.submitDecodeUnit`. Returns
/// `DR_OK` or `DR_NEED_IDR` (see Limelight.h).
- (int)submitDecodeUnit:(PDECODE_UNIT)decodeUnit;

/// Drops any pending format state - call when a session ends so a new one
/// starts clean.
- (void)reset;

@end

NS_ASSUME_NONNULL_END
