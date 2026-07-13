#import "VideoDecodeRenderer.h"
#import <os/log.h>

static os_log_t videoLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("ch.useselene.selene", "video");
    });
    return log;
}

@implementation VideoDecodeRenderer {
    CMVideoFormatDescriptionRef _formatDescription;
    int _frameLogCount;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _displayLayer = [[AVSampleBufferDisplayLayer alloc] init];
        _displayLayer.videoGravity = AVLayerVideoGravityResizeAspect;

        // AVSampleBufferDisplayLayer defaults to a real-wall-clock timebase.
        // The host's RTP timestamps (a 90kHz clock counting from stream
        // start, unrelated to our wall clock) don't correlate with that at
        // all, so presentation timestamps built from them would tell the
        // layer to display frames at some arbitrary point in the future (or
        // past) relative to its own clock - it just never shows anything.
        // This is a low-latency live stream, not a file with fixed timing,
        // so we replace presentation timestamps with "now" on our own
        // host-time-synced timebase instead (see submitDecodeUnit).
        CMTimebaseRef timebase = NULL;
        CMTimebaseCreateWithSourceClock(kCFAllocatorDefault, CMClockGetHostTimeClock(), &timebase);
        CMTimebaseSetTime(timebase, CMClockGetTime(CMClockGetHostTimeClock()));
        CMTimebaseSetRate(timebase, 1.0);
        _displayLayer.controlTimebase = timebase;
        if (timebase != NULL) {
            CFRelease(timebase);
        }
    }
    return self;
}

- (void)dealloc {
    if (_formatDescription != NULL) {
        CFRelease(_formatDescription);
    }
}

- (void)reset {
    [_displayLayer flush];
    if (_formatDescription != NULL) {
        CFRelease(_formatDescription);
        _formatDescription = NULL;
    }
}

/// Strips a NAL's 3- or 4-byte Annex B start code, returning the raw NAL
/// unit (header byte + RBSP) `CMVideoFormatDescriptionCreateFromH264ParameterSets`
/// expects for SPS/PPS.
static NSData *StripAnnexBStartCode(const char *data, int length) {
    int prefixLen;
    if (length >= 4 && data[0] == 0 && data[1] == 0 && data[2] == 0 && data[3] == 1) {
        prefixLen = 4;
    } else if (length >= 3 && data[0] == 0 && data[1] == 0 && data[2] == 1) {
        prefixLen = 3;
    } else {
        prefixLen = 0;
    }
    return [NSData dataWithBytes:data + prefixLen length:(NSUInteger)(length - prefixLen)];
}

/// Re-splits a (possibly multi-NAL) Annex B buffer at its start codes and
/// appends each NAL to `avccData` with a 4-byte big-endian length prefix in
/// place of the start code - the format `CMBlockBuffer`/VideoToolbox wants.
/// Doesn't assume one buffer-list entry == one NAL; scans for real
/// boundaries instead; entries are, in practice, one NAL each.
static void AppendAnnexBAsAVCC(const uint8_t *bytes, int length, NSMutableData *avccData) {
    int i = 0;
    while (i < length) {
        int scLen;
        if (i + 3 <= length && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 1) {
            scLen = 3;
        } else if (i + 4 <= length && bytes[i] == 0 && bytes[i + 1] == 0 && bytes[i + 2] == 0 && bytes[i + 3] == 1) {
            scLen = 4;
        } else {
            // Not sitting on a start code - malformed input, bail rather
            // than emit garbage.
            break;
        }

        int nalStart = i + scLen;
        int nalEnd = length;
        int j = nalStart;
        while (j + 3 <= length) {
            if (bytes[j] == 0 && bytes[j + 1] == 0 &&
                (bytes[j + 2] == 1 || (j + 4 <= length && bytes[j + 2] == 0 && bytes[j + 3] == 1))) {
                nalEnd = j;
                break;
            }
            j++;
        }

        uint32_t nalLength = (uint32_t)(nalEnd - nalStart);
        uint32_t lengthBE = CFSwapInt32HostToBig(nalLength);
        [avccData appendBytes:&lengthBE length:4];
        [avccData appendBytes:bytes + nalStart length:nalLength];
        i = nalEnd;
    }
}

- (BOOL)updateFormatDescriptionWithSPS:(NSData *)sps pps:(NSData *)pps {
    const uint8_t *parameterSetPointers[2] = {
        (const uint8_t *)sps.bytes,
        (const uint8_t *)pps.bytes,
    };
    const size_t parameterSetSizes[2] = {
        (size_t)sps.length,
        (size_t)pps.length,
    };

    CMVideoFormatDescriptionRef newFormatDescription = NULL;
    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
        kCFAllocatorDefault, 2, parameterSetPointers, parameterSetSizes, 4, &newFormatDescription);
    if (status != noErr) {
        return NO;
    }

    if (_formatDescription != NULL) {
        CFRelease(_formatDescription);
    }
    _formatDescription = newFormatDescription;
    return YES;
}

- (int)submitDecodeUnit:(PDECODE_UNIT)decodeUnit {
    BOOL verbose = _frameLogCount < 10;
    if (verbose) {
        _frameLogCount++;
    }

    NSData *sps = nil;
    NSData *pps = nil;
    // Picture-data entries are concatenated raw first, then scanned for NAL
    // boundaries as one contiguous buffer - a single NAL's bytes can span
    // multiple buffer-list entries, so parsing each entry independently
    // (as an earlier version of this function did) silently drops any
    // entry that doesn't happen to start exactly on a start code.
    NSMutableData *annexBPicData = [NSMutableData dataWithCapacity:(NSUInteger)decodeUnit->fullLength];

    int entryCount = 0;
    for (PLENTRY entry = decodeUnit->bufferList; entry != NULL; entry = entry->next) {
        entryCount++;
        switch (entry->bufferType) {
            case BUFFER_TYPE_SPS:
                sps = StripAnnexBStartCode(entry->data, entry->length);
                break;
            case BUFFER_TYPE_PPS:
                pps = StripAnnexBStartCode(entry->data, entry->length);
                break;
            default:
                [annexBPicData appendBytes:entry->data length:(NSUInteger)entry->length];
                break;
        }
    }

    NSMutableData *avccData = [NSMutableData dataWithCapacity:annexBPicData.length];
    AppendAnnexBAsAVCC((const uint8_t *)annexBPicData.bytes, (int)annexBPicData.length, avccData);

    if (verbose) {
        os_log(videoLog(), "frame=%d type=%d entries=%d sps=%d pps=%d avcc=%lu",
               decodeUnit->frameNumber, decodeUnit->frameType, entryCount,
               (int)sps.length, (int)pps.length, (unsigned long)avccData.length);
    }

    if (sps != nil && pps != nil) {
        BOOL ok = [self updateFormatDescriptionWithSPS:sps pps:pps];
        if (verbose || !ok) {
            os_log(videoLog(), "format description update ok=%d", ok);
        }
        if (!ok) {
            return DR_NEED_IDR;
        }
    }

    if (_formatDescription == NULL) {
        // Haven't decoded a parameter-set-bearing IDR frame yet.
        os_log(videoLog(), "no format description yet, requesting IDR");
        return DR_NEED_IDR;
    }

    if (avccData.length == 0) {
        return DR_OK;
    }

    CMBlockBufferRef blockBuffer = NULL;
    OSStatus status = CMBlockBufferCreateWithMemoryBlock(
        kCFAllocatorDefault, NULL, avccData.length, kCFAllocatorDefault, NULL, 0, avccData.length, 0, &blockBuffer);
    if (status != noErr) {
        os_log(videoLog(), "CMBlockBufferCreateWithMemoryBlock failed: %d", (int)status);
        return DR_OK;
    }
    CMBlockBufferReplaceDataBytes(avccData.bytes, blockBuffer, 0, avccData.length);

    CMSampleTimingInfo timingInfo = {0};
    timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock());
    timingInfo.duration = kCMTimeInvalid;
    timingInfo.decodeTimeStamp = kCMTimeInvalid;

    size_t sampleSizeArray[1] = { avccData.length };
    CMSampleBufferRef sampleBuffer = NULL;
    status = CMSampleBufferCreate(kCFAllocatorDefault, blockBuffer, true, NULL, NULL,
                                   _formatDescription, 1, 1, &timingInfo, 1, sampleSizeArray, &sampleBuffer);
    CFRelease(blockBuffer);
    if (status != noErr || sampleBuffer == NULL) {
        os_log(videoLog(), "CMSampleBufferCreate failed: %d", (int)status);
        return DR_OK;
    }

    if (decodeUnit->frameType == FRAME_TYPE_IDR) {
        CFArrayRef attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, true);
        if (CFArrayGetCount(attachmentsArray) > 0) {
            CFMutableDictionaryRef attachments = (CFMutableDictionaryRef)CFArrayGetValueAtIndex(attachmentsArray, 0);
            CFDictionarySetValue(attachments, kCMSampleAttachmentKey_NotSync, kCFBooleanFalse);
        }
    }

    if (_displayLayer.status == AVQueuedSampleBufferRenderingStatusFailed) {
        os_log(videoLog(), "display layer failed, error=%@", _displayLayer.error);
        [_displayLayer flush];
    }

    if (verbose) {
        os_log(videoLog(), "enqueueing sample, displayLayer.isReadyForMoreMediaData=%d", _displayLayer.isReadyForMoreMediaData);
    }
    [_displayLayer enqueueSampleBuffer:sampleBuffer];
    CFRelease(sampleBuffer);

    return DR_OK;
}

@end
