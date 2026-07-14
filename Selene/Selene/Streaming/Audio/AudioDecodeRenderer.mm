#import "AudioDecodeRenderer.h"

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <os/log.h>

static os_log_t audioLog(void) {
    static os_log_t log;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        log = os_log_create("ch.polonium.selene", "audio");
    });
    return log;
}

static OSStatus InputDataProc(AudioConverterRef inAudioConverter,
                               UInt32 *ioNumberDataPackets,
                               AudioBufferList *ioData,
                               AudioStreamPacketDescription **outDataPacketDescription,
                               void *inUserData);

@implementation AudioDecodeRenderer {
    AudioConverterRef _converter;
    AVAudioEngine *_engine;
    AVAudioPlayerNode *_playerNode;
    AVAudioFormat *_pcmFormat;
    int _channelCount;
    int _samplesPerFrame;
    int _frameLogCount;

    // Scratch state read by InputDataProc - holds the single Opus packet
    // being converted "right now". AudioConverterFillComplexBuffer always
    // calls back synchronously on the calling thread, so this is safe
    // without extra locking as long as decodeAndPlaySample: isn't itself
    // called concurrently from multiple threads (moonlight-common-c calls
    // it serially from its own audio thread).
    const void *_pendingPacketData;
    UInt32 _pendingPacketSize;
    AudioStreamPacketDescription _pendingPacketDescription;
    int _inputProcCallCount;
    int _unexpectedNullDataLogCount;
    int _totalPacketCount;
    int _plcPlaceholderCountSinceHeartbeat;
    int _zeroOutputCountSinceHeartbeat;
    int _nonZeroOutputCountSinceHeartbeat;

    id _configChangeObserver;
}

- (void)dealloc {
    [self teardownConverter];
    [self removeConfigChangeObserver];
}

- (void)removeConfigChangeObserver {
    if (_configChangeObserver != nil) {
        [[NSNotificationCenter defaultCenter] removeObserver:_configChangeObserver];
        _configChangeObserver = nil;
    }
}

- (void)teardownConverter {
    if (_converter != NULL) {
        AudioConverterDispose(_converter);
        _converter = NULL;
    }
}

- (void)reset {
    [self stop];
    [self teardownConverter];
    [self removeConfigChangeObserver];
}

- (int)setupWithOpusConfig:(POPUS_MULTISTREAM_CONFIGURATION)opusConfig {
    [self teardownConverter];

    _channelCount = opusConfig->channelCount;
    _samplesPerFrame = opusConfig->samplesPerFrame;

    AudioStreamBasicDescription inputFormat = {0};
    inputFormat.mFormatID = kAudioFormatOpus;
    inputFormat.mSampleRate = opusConfig->sampleRate;
    inputFormat.mChannelsPerFrame = (UInt32)opusConfig->channelCount;
    // Deliberately left at 0 (variable) rather than opusConfig->samplesPerFrame:
    // declaring a fixed frame count here made AudioConverter believe every
    // packet must decode to exactly that many frames. When a real packet
    // decoded to fewer, it asked our input proc for a second packet to make
    // up the "missing" frames; we had none to give, and that "no more data"
    // response got treated as a permanent end-of-stream, silently killing all
    // decoding for the rest of the connection. Leaving this at 0 lets the
    // decoder read the true per-packet frame count from the Opus bitstream
    // itself instead of enforcing our (wrong) assumption.
    inputFormat.mFramesPerPacket = 0;

    // AVAudioEngine requires non-interleaved buffers to connect nodes - for
    // non-interleaved PCM, mBytesPerFrame/mBytesPerPacket describe a single
    // channel's buffer (AudioBufferList carries one buffer per channel), not
    // channelCount * bytesPerSample as interleaved formats would.
    AudioStreamBasicDescription outputFormat = {0};
    outputFormat.mFormatID = kAudioFormatLinearPCM;
    outputFormat.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved;
    outputFormat.mSampleRate = opusConfig->sampleRate;
    outputFormat.mChannelsPerFrame = (UInt32)opusConfig->channelCount;
    outputFormat.mBitsPerChannel = 32;
    outputFormat.mBytesPerFrame = 4;
    outputFormat.mFramesPerPacket = 1;
    outputFormat.mBytesPerPacket = 4;

    OSStatus status = AudioConverterNew(&inputFormat, &outputFormat, &_converter);
    if (status != noErr) {
        os_log(audioLog(), "AudioConverterNew failed: %d", (int)status);
        return -1;
    }


    // AudioConverter doesn't know the actual Opus stream layout (sample rate,
    // channel count, stream/coupled-stream mapping) just from the ASBD above -
    // without this it silently decodes to garbage/silence rather than
    // erroring. This is the standard Ogg "OpusHead" identification header
    // (RFC 7845 section 5.1), built from the fields moonlight-common-c already
    // gives us in OPUS_MULTISTREAM_CONFIGURATION.
    NSMutableData *magicCookie = [NSMutableData data];
    [magicCookie appendBytes:"OpusHead" length:8];
    uint8_t version = 1;
    [magicCookie appendBytes:&version length:1];
    uint8_t channelCount = (uint8_t)opusConfig->channelCount;
    [magicCookie appendBytes:&channelCount length:1];
    uint16_t preSkip = 0;
    [magicCookie appendBytes:&preSkip length:2];
    uint32_t inputSampleRate = (uint32_t)opusConfig->sampleRate;
    [magicCookie appendBytes:&inputSampleRate length:4];
    int16_t outputGain = 0;
    [magicCookie appendBytes:&outputGain length:2];
    // Per RFC 7845, mapping family 0 (mono/stereo with the implicit L/R
    // layout) must NOT be followed by the stream/coupled-stream counts or
    // mapping table below - including them for a plain stereo stream is what
    // made AudioConverter reject the cookie as malformed. Family 1 (explicit
    // table) is only needed once we go beyond 2 channels.
    uint8_t mappingFamily = opusConfig->channelCount > 2 ? 1 : 0;
    [magicCookie appendBytes:&mappingFamily length:1];
    if (mappingFamily != 0) {
        uint8_t streamCount = (uint8_t)opusConfig->streams;
        uint8_t coupledCount = (uint8_t)opusConfig->coupledStreams;
        [magicCookie appendBytes:&streamCount length:1];
        [magicCookie appendBytes:&coupledCount length:1];
        [magicCookie appendBytes:opusConfig->mapping length:opusConfig->channelCount];
    }

    status = AudioConverterSetProperty(_converter, kAudioConverterDecompressionMagicCookie,
                                        (UInt32)magicCookie.length, magicCookie.bytes);
    if (status != noErr) {
        os_log(audioLog(), "Setting Opus magic cookie failed: %d", (int)status);
        return -1;
    }

    _pcmFormat = [[AVAudioFormat alloc] initWithStreamDescription:&outputFormat];
    if (_pcmFormat == nil) {
        os_log(audioLog(), "Failed to build AVAudioFormat from output ASBD");
        return -1;
    }

    _engine = [[AVAudioEngine alloc] init];
    _playerNode = [[AVAudioPlayerNode alloc] init];
    [_engine attachNode:_playerNode];
    [_engine connect:_playerNode to:_engine.mainMixerNode format:_pcmFormat];

    // AVAudioEngine silently stops itself whenever the system's audio
    // hardware configuration changes (default device/route change, sample
    // rate change, etc.) and posts this notification instead of erroring
    // out anywhere we'd notice - without restarting it here, playback goes
    // dead until the whole session is torn down and restarted. This is the
    // documented, standard way to keep an AVAudioEngine alive long-term.
    [self removeConfigChangeObserver];
    __weak AudioDecodeRenderer *weakSelf = self;
    _configChangeObserver = [[NSNotificationCenter defaultCenter]
        addObserverForName:AVAudioEngineConfigurationChangeNotification
                    object:_engine
                     queue:nil
                usingBlock:^(NSNotification *note) {
        AudioDecodeRenderer *strongSelf = weakSelf;
        if (strongSelf == nil) {
            return;
        }
        os_log(audioLog(), "AVAudioEngine configuration changed - restarting");
        NSError *restartError = nil;
        if (![strongSelf->_engine startAndReturnError:&restartError]) {
            os_log(audioLog(), "AVAudioEngine restart after config change failed: %@", restartError);
            return;
        }
        [strongSelf->_playerNode play];
    }];

    os_log(audioLog(), "setup ok: sampleRate=%d channels=%d samplesPerFrame=%d",
           opusConfig->sampleRate, _channelCount, _samplesPerFrame);

    return 0;
}

- (void)start {
    if (_engine == nil) {
        return;
    }
    NSError *error = nil;
    if (![_engine startAndReturnError:&error]) {
        os_log(audioLog(), "AVAudioEngine start failed: %@", error);
        return;
    }
    [_playerNode play];
    os_log(audioLog(), "engine started: isRunning=%d playerNode.isPlaying=%d outputVolume=%f",
           _engine.isRunning, _playerNode.isPlaying, _engine.mainMixerNode.outputVolume);
}

- (void)stop {
    [_playerNode stop];
    [_engine stop];
}

- (OSStatus)fillInputData:(UInt32 *)ioNumberDataPackets
                bufferList:(AudioBufferList *)ioData
        packetDescriptions:(AudioStreamPacketDescription **)outDataPacketDescription {
    _inputProcCallCount++;
    if (_frameLogCount < 5) {
        os_log(audioLog(), "fillInputData call #%d, pendingData=%p requestedPackets=%u",
               _inputProcCallCount, _pendingPacketData, (unsigned)*ioNumberDataPackets);
    }
    if (_pendingPacketData == NULL) {
        // Per Apple's documented contract, AudioConverterFillComplexBuffer()
        // only calls this synchronously, on the calling thread, during the
        // call it made from decodeAndPlaySample: - which always has fresh
        // data set right before making that call. So this should never
        // happen. But we've already proven this exact "no more data"
        // response gets latched by this codec as permanent end-of-stream
        // (see decodeAndPlaySample:), so if some undocumented behavior in
        // the Opus codec component ever calls back outside that window,
        // THIS is where audio would go silent forever - log it unconditionally
        // (capped, not gated behind the first-N-calls diagnostic) so it's
        // provable instead of theoretical if it ever happens.
        if (_unexpectedNullDataLogCount < 20) {
            _unexpectedNullDataLogCount++;
            os_log(audioLog(), "fillInputData called with no pending packet (unexpected #%d) - audio will likely go silent from here", _unexpectedNullDataLogCount);
        }
        *ioNumberDataPackets = 0;
        return noErr;
    }

    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mData = (void *)_pendingPacketData;
    ioData->mBuffers[0].mDataByteSize = _pendingPacketSize;
    ioData->mBuffers[0].mNumberChannels = (UInt32)_channelCount;

    _pendingPacketDescription.mStartOffset = 0;
    _pendingPacketDescription.mVariableFramesInPacket = 0;
    _pendingPacketDescription.mDataByteSize = _pendingPacketSize;

    if (outDataPacketDescription != NULL) {
        *outDataPacketDescription = &_pendingPacketDescription;
    }

    *ioNumberDataPackets = 1;

    // Deliberately NOT clearing _pendingPacketData here. Ever returning
    // "no more data" (*ioNumberDataPackets = 0) mid-stream gets latched by
    // this codec as a permanent end-of-stream - every later packet's decode
    // silently produces 0 frames from then on, even with fresh valid data
    // (confirmed by testing). If the converter's read-ahead/priming logic
    // calls back again within this same FillComplexBuffer invocation, it
    // gets handed the same packet a second time instead, which is harmless
    // (a redundant decode of already-seen bytes) next to permanently
    // breaking playback. decodeAndPlaySample clears this once the call
    // returns, before the next real packet comes in.
    return noErr;
}

- (void)decodeAndPlaySample:(const char *)sampleData length:(int)sampleLength {
    if (_converter == NULL || _pcmFormat == nil) {
        return;
    }

    // Heartbeat so a future "audio just stops" report tells us whether
    // moonlight-common-c ever stopped calling us at all (network/upstream
    // issue) versus us still receiving packets but silently failing to
    // play them. engineRunning/playerNodePlaying alone don't prove audio is
    // actually flowing - both stay true even if every decode has been
    // silently producing 0 frames - so this also tracks how many packets
    // since the last heartbeat decoded to nonzero output.
    _totalPacketCount++;
    if (sampleData == NULL) {
        // moonlight-common-c asking for packet-loss-concealment on a dropped
        // network packet (see AudioStream.c) - not an error. Deliberately
        // NOT run through AudioConverterFillComplexBuffer: doing so means
        // the input proc has nothing to hand back, which is exactly the
        // "no more data" response that gets latched by this codec as a
        // permanent end-of-stream (see fillInputData: and the note in
        // setupWithOpusConfig: about mFramesPerPacket). Skipping the decode
        // for this one frame trades proper Opus PLC synthesis for a tiny,
        // safe gap instead of risking killing audio for the rest of the
        // session - on a lossy connection (VPN) this triggers often; on a
        // clean LAN it should barely ever happen.
        _plcPlaceholderCountSinceHeartbeat++;
    }
    if (_totalPacketCount % 1000 == 0) {
        os_log(audioLog(), "heartbeat: totalPackets=%d engineRunning=%d playerNodePlaying=%d nonZeroOutput=%d zeroOutput=%d plcPlaceholders=%d",
               _totalPacketCount, _engine.isRunning, _playerNode.isPlaying,
               _nonZeroOutputCountSinceHeartbeat, _zeroOutputCountSinceHeartbeat, _plcPlaceholderCountSinceHeartbeat);
        _nonZeroOutputCountSinceHeartbeat = 0;
        _zeroOutputCountSinceHeartbeat = 0;
        _plcPlaceholderCountSinceHeartbeat = 0;
    }
    if (sampleData == NULL) {
        return;
    }

    _pendingPacketData = sampleData;
    _pendingPacketSize = (UInt32)sampleLength;
    _inputProcCallCount = 0;

    AVAudioPCMBuffer *pcmBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_pcmFormat
                                                                 frameCapacity:(AVAudioFrameCount)_samplesPerFrame];
    if (pcmBuffer == nil) {
        _pendingPacketData = NULL;
        return;
    }
    pcmBuffer.frameLength = (AVAudioFrameCount)_samplesPerFrame;

    UInt32 outputPacketCount = (UInt32)_samplesPerFrame;
    OSStatus status = AudioConverterFillComplexBuffer(
        _converter, InputDataProc, (__bridge void *)self, &outputPacketCount, pcmBuffer.mutableAudioBufferList, NULL);

    _pendingPacketData = NULL;

    if (status != noErr) {
        _zeroOutputCountSinceHeartbeat++;
        if (_frameLogCount < 10) {
            _frameLogCount++;
            os_log(audioLog(), "AudioConverterFillComplexBuffer failed: %d", (int)status);
        }
        return;
    }

    pcmBuffer.frameLength = outputPacketCount;

    if (outputPacketCount == 0) {
        _zeroOutputCountSinceHeartbeat++;
    } else {
        _nonZeroOutputCountSinceHeartbeat++;
    }

    if (_frameLogCount < 5) {
        _frameLogCount++;
        float peak = 0;
        if (pcmBuffer.floatChannelData != NULL) {
            float *channel0 = pcmBuffer.floatChannelData[0];
            for (AVAudioFrameCount i = 0; i < outputPacketCount; i++) {
                float v = fabsf(channel0[i]);
                if (v > peak) peak = v;
            }
        }
        os_log(audioLog(), "decoded frame: inBytes=%d outputPacketCount=%u peak=%f enginePlaying=%d inputProcCalls=%d",
               sampleLength, (unsigned)outputPacketCount, peak, _playerNode.isPlaying, _inputProcCallCount);
    }

    [_playerNode scheduleBuffer:pcmBuffer completionHandler:nil];
}

@end

static OSStatus InputDataProc(AudioConverterRef inAudioConverter,
                               UInt32 *ioNumberDataPackets,
                               AudioBufferList *ioData,
                               AudioStreamPacketDescription **outDataPacketDescription,
                               void *inUserData) {
    AudioDecodeRenderer *renderer = (__bridge AudioDecodeRenderer *)inUserData;
    return [renderer fillInputData:ioNumberDataPackets bufferList:ioData packetDescriptions:outDataPacketDescription];
}
