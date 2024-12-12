#import "RNWhisperContext.h"
#import <Metal/Metal.h>
#include <vector>

#define NUM_BYTES_PER_BUFFER 16 * 1024

@implementation RNWhisperContext

+ (instancetype)initWithModelPath:(NSString *)modelPath
    contextId:(int)contextId
    noCoreML:(BOOL)noCoreML
    noMetal:(BOOL)noMetal
    useFlashAttn:(BOOL)useFlashAttn
{
    RNWhisperContext *context = [[RNWhisperContext alloc] init];
    context->contextId = contextId;
    struct whisper_context_params cparams;
    NSString *reasonNoMetal = @"";
    cparams.use_gpu = !noMetal;
    cparams.flash_attn = useFlashAttn;

    // TODO: Figure out why it leads to re-init crash
    cparams.dtw_token_timestamps = false;

    cparams.use_coreml = !noCoreML;
#ifndef WHISPER_USE_COREML
    if (cparams.use_coreml) {
        NSLog(@"[RNWhisper] CoreML is not enabled in this build, ignoring use_coreml option");
        cparams.use_coreml = false;
    }
#endif

#ifndef WSP_GGML_USE_METAL
    if (cparams.use_gpu) {
        NSLog(@"[RNWhisper] ggml-metal is not enabled in this build, ignoring use_gpu option");
        cparams.use_gpu = false;
    }
#endif

#ifdef WSP_GGML_USE_METAL
    if (cparams.use_gpu) {
#if TARGET_OS_SIMULATOR
        NSLog(@"[RNWhisper] ggml-metal is not available in simulator, ignoring use_gpu option: %@", reasonNoMetal);
        cparams.use_gpu = false;
#else // TARGET_OS_SIMULATOR
        // Check ggml-metal availability
        NSError * error = nil;
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        id<MTLLibrary> library = [device
            newLibraryWithSource:@"#include <metal_stdlib>\n"
                                    "using namespace metal;"
                                    "kernel void test() { simd_sum(0); }"
            options:nil
            error:&error
        ];
        if (error) {
            reasonNoMetal = [error localizedDescription];
        } else {
            id<MTLFunction> kernel = [library newFunctionWithName:@"test"];
            id<MTLComputePipelineState> pipeline = [device newComputePipelineStateWithFunction:kernel error:&error];
            if (pipeline == nil) {
                reasonNoMetal = [error localizedDescription];
                NSLog(@"[RNWhisper] ggml-metal is not available, ignoring use_gpu option: %@", reasonNoMetal);
                cparams.use_gpu = false;
            }
        }
#endif // TARGET_OS_SIMULATOR
    }
#endif // WSP_GGML_USE_METAL

    if (cparams.use_gpu && cparams.use_coreml) {
        NSLog(@"[RNWhisper] Both use_gpu and use_coreml are enabled, ignoring use_coreml option");
        cparams.use_coreml = false; // Skip CoreML if Metal is enabled
    }

    context->ctx = whisper_init_from_file_with_params([modelPath UTF8String], cparams);
    context->dQueue = dispatch_queue_create(
        [[NSString stringWithFormat:@"RNWhisperContext-%d", contextId] UTF8String],
        DISPATCH_QUEUE_SERIAL
    );
    context->isMetalEnabled = cparams.use_gpu;
    context->reasonNoMetal = reasonNoMetal;
    return context;
}

- (bool)isMetalEnabled {
    return isMetalEnabled;
}

- (NSString *)reasonNoMetal {
    return reasonNoMetal;
}

- (struct whisper_context *)getContext {
    return self->ctx;
}

- (dispatch_queue_t)getDispatchQueue {
    return self->dQueue;
}

- (void)prepareRealtime:(int)jobId options:(NSDictionary *)options {
    self->recordState.options = options;

    self->recordState.dataFormat.mSampleRate = WHISPER_SAMPLE_RATE; // 16000
    self->recordState.dataFormat.mFormatID = kAudioFormatLinearPCM;
    self->recordState.dataFormat.mFramesPerPacket = 1;
    self->recordState.dataFormat.mChannelsPerFrame = 1; // mono
    self->recordState.dataFormat.mBytesPerFrame = 2;
    self->recordState.dataFormat.mBytesPerPacket = 2;
    self->recordState.dataFormat.mBitsPerChannel = 16;
    self->recordState.dataFormat.mReserved = 0;
    self->recordState.dataFormat.mFormatFlags = kLinearPCMFormatFlagIsSignedInteger;

    self->recordState.isRealtime = true;
    self->recordState.isTranscribing = false;
    self->recordState.isCapturing = false;
    self->recordState.isStoppedByAction = false;

    self->recordState.sliceIndex = 0;
    self->recordState.transcribeSliceIndex = 0;
    self->recordState.nSamplesTranscribing = 0;

    self->recordState.sliceNSamples.clear();
    self->recordState.sliceNSamples.push_back(0);

    self->recordState.job = rnwhisper::job_new(jobId, [self createParams:options jobId:jobId]);
    self->recordState.job->set_realtime_params(
        {
            .use_vad = options[@"useVad"] != nil ? [options[@"useVad"] boolValue] : false,
            .vad_ms = options[@"vadMs"] != nil ? [options[@"vadMs"] intValue] : 2000,
            .vad_thold = options[@"vadThold"] != nil ? [options[@"vadThold"] floatValue] : 0.6f,
            .freq_thold = options[@"vadFreqThold"] != nil ? [options[@"vadFreqThold"] floatValue] : 100.0f
        },
        options[@"realtimeAudioSec"] != nil ? [options[@"realtimeAudioSec"] intValue] : 0,
        options[@"realtimeAudioSliceSec"] != nil ? [options[@"realtimeAudioSliceSec"] intValue] : 0,
        options[@"realtimeAudioMinSec"] != nil ? [options[@"realtimeAudioMinSec"] floatValue] : 0,
        options[@"audioOutputPath"] != nil ? [options[@"audioOutputPath"] UTF8String] : nullptr
    );
    self->recordState.isUseSlices = self->recordState.job->audio_slice_sec < self->recordState.job->audio_sec;

    self->recordState.mSelf = self;

        // Set default values if not provided
    self->recordState.step_ms = options[@"stepMs"] ? [options[@"stepMs"] intValue] : 500;
    self->recordState.length_ms = options[@"lengthMs"] ? [options[@"lengthMs"] intValue] : 5000;
    self->recordState.keep_ms = options[@"keepMs"] ? [options[@"keepMs"] intValue] : 2000;

    // Convert milliseconds to number of samples
    self->recordState.step_samples = (self->recordState.step_ms * WHISPER_SAMPLE_RATE) / 1000;
    self->recordState.length_samples = (self->recordState.length_ms * WHISPER_SAMPLE_RATE) / 1000;
    self->recordState.keep_samples = (self->recordState.keep_ms * WHISPER_SAMPLE_RATE) / 1000;

    // Initialize PCM buffer
    self->recordState.pcm_buffer = [NSMutableData data];
}

bool vad(RNWhisperContextRecordState *state, int sliceIndex, int nSamples, int n)
{
    if (state->isTranscribing) return true;
    return state->job->vad_simple(sliceIndex, nSamples, n);
}


- (bool)isCapturing {
    return self->recordState.isCapturing;
}

- (bool)isTranscribing {
    return self->recordState.isTranscribing;
}

- (bool)isStoppedByAction {
    return self->recordState.isStoppedByAction;
}

- (OSStatus)transcribeRealtime:(int)jobId
    options:(NSDictionary *)options
    onTranscribe:(void (^)(int, NSString *, NSDictionary *))onTranscribe
{
    self->recordState.transcribeHandler = onTranscribe;
    [self prepareRealtime:jobId options:options];

    OSStatus status = AudioQueueNewInput(
        &self->recordState.dataFormat,
        AudioInputCallback,
        &self->recordState,
        NULL,
        kCFRunLoopCommonModes,
        0,
        &self->recordState.queue
    );

    if (status == 0) {
        for (int i = 0; i < NUM_BUFFERS; i++) {
            AudioQueueAllocateBuffer(self->recordState.queue, NUM_BYTES_PER_BUFFER, &self->recordState.buffers[i]);
            AudioQueueEnqueueBuffer(self->recordState.queue, self->recordState.buffers[i], 0, NULL);
        }
        status = AudioQueueStart(self->recordState.queue, NULL);
        if (status == 0) {
            self->recordState.isCapturing = true;
        }
    }
    return status;
}

void AudioInputCallback(void *inUserData, AudioQueueRef inAQ, AudioQueueBufferRef inBuffer,
                        const AudioTimeStamp *inStartTime, UInt32 inNumberPacketDescriptions,
                        const AudioStreamPacketDescription *inPacketDescs) {
    RNWhisperContextRecordState *state = (RNWhisperContextRecordState *)inUserData;
    NSLog(@"[RNWhisper] AudioInputCallback");
    if (!state->isCapturing) {
        NSLog(@"[RNWhisper] Not capturing, ignoring audio");
        if (!state->isTranscribing) {
            [state->mSelf finishRealtimeTranscribe:state result:@{}];
        }
        return;
    }

    // Append new audio samples to the buffer
    [state->pcm_buffer appendBytes:inBuffer->mAudioData length:inBuffer->mAudioDataByteSize];

    // Update the number of new samples since last transcription
    state->new_samples_count += inBuffer->mAudioDataByteSize / sizeof(int16_t);

    // Check if we have enough new samples to trigger transcription
    if (state->new_samples_count >= state->step_samples) {
        if (!state->isTranscribing) {
            state->isTranscribing = true;
            state->new_samples_count = 0;
            dispatch_async([state->mSelf getDispatchQueue], ^{
                [state->mSelf processAudioChunk:state];
            });
        }
    }

    // Enqueue the buffer again for more data
    AudioQueueEnqueueBuffer(state->queue, inBuffer, 0, NULL);
}
- (void)processAudioChunk:(RNWhisperContextRecordState *)state {
    // Extract the number of samples in the buffer
    NSUInteger numSamples = state->pcm_buffer.length / sizeof(int16_t);

    // Ensure we have at least length_samples
    NSUInteger processSamples = MIN(numSamples, state->length_samples);

    // Prepare audio data for processing
    NSRange processRange = NSMakeRange(0, processSamples * sizeof(int16_t));
    NSData *audioDataToProcess = [state->pcm_buffer subdataWithRange:processRange];

    // Keep last 'keep_samples' for context
    NSUInteger keepSamplesStart = numSamples > state->keep_samples ? (numSamples - state->keep_samples) : 0;
    NSRange keepRange = NSMakeRange(keepSamplesStart * sizeof(int16_t), state->keep_samples * sizeof(int16_t));

    // Trim the buffer to keep only 'keep_samples' for context
    state->pcm_buffer = [[state->pcm_buffer subdataWithRange:keepRange] mutableCopy];

    // Convert NSData to float array
    NSUInteger sampleCount = audioDataToProcess.length / sizeof(int16_t);
    int16_t *samples = (int16_t *)audioDataToProcess.bytes;

    float *pcm_f32 = malloc(sampleCount * sizeof(float));
    for (NSUInteger i = 0; i < sampleCount; i++) {
        pcm_f32[i] = samples[i] / 32768.0f;
    }

    // Prepare whisper parameters
    struct whisper_full_params params = [self createParams:state->options jobId:state->job->job_id];

    // Use prompt tokens for context
    if (state->prompt_tokens && params.no_context == false) {
        params.prompt_tokens = state->prompt_tokens;
        params.prompt_n_tokens = state->n_prompt_tokens;
    }

    // Run transcription
    int ret = whisper_full(self->ctx, params, pcm_f32, (int)sampleCount);

    if (ret != 0) {
        NSLog(@"Failed to run whisper on audio chunk");
        free(pcm_f32);
        state->isTranscribing = false;
        return;
    }

    // Store prompt tokens
    state->n_prompt_tokens = whisper_full_n_tokens(self->ctx);
    if (state->prompt_tokens) {
        free(state->prompt_tokens);
    }
    state->prompt_tokens = malloc(state->n_prompt_tokens * sizeof(int32_t));
    for (int i = 0; i < state->n_prompt_tokens; i++) {
        state->prompt_tokens[i] = whisper_full_get_token_id(self->ctx, i);
    }

    // Get transcription result
    if (!state->isCapturing && !state->isTranscribing) {
        [self finishRealtimeTranscribe:state result:result];
    } else {
        state->transcribeHandler(state->job->job_id, @"transcribe", result);
    }


    // Call transcribeHandler with the result
    NSMutableDictionary *handlerResult = [result mutableCopy];
    handlerResult[@"isCapturing"] = @(state->isCapturing);
    handlerResult[@"isStoppedByAction"] = @(state->isStoppedByAction);

    state->transcribeHandler(state->job->job_id, @"transcribe", handlerResult);

    // Append audio data to file
    [self appendAudioDataToFile:audioDataToProcess];

    free(pcm_f32);
    state->isTranscribing = false;
}

- (NSMutableDictionary *)getTextSegmentsWithState:(RNWhisperContextRecordState *)state {
    NSMutableString *text = [NSMutableString string];
    int n_segments = whisper_full_n_segments(self->ctx);

    NSMutableArray *segments = [NSMutableArray array];
    for (int i = 0; i < n_segments; i++) {
        const char * text_cstr = whisper_full_get_segment_text(self->ctx, i);
        if (text_cstr == NULL) {
            continue;
        }
        NSMutableString *mutable_ns_text = [NSMutableString stringWithUTF8String:text_cstr];

        // Handle tinydiarize if enabled
        if (state->options[@"tdrzEnable"] &&
            [state->options[@"tdrzEnable"] boolValue] &&
            whisper_full_get_segment_speaker_turn_next(self->ctx, i)) {
            [mutable_ns_text appendString:@" [SPEAKER_TURN]"];
        }

        [text appendString:mutable_ns_text];

        int64_t t0 = whisper_full_get_segment_t0(self->ctx, i);
        int64_t t1 = whisper_full_get_segment_t1(self->ctx, i);

        NSDictionary *segment = @{
            @"text": [mutable_ns_text copy],
            @"t0": @(t0),
            @"t1": @(t1)
        };
        [segments addObject:segment];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"result"] = [text copy];
    result[@"segments"] = segments;
    return result;
}
- (NSString *)getTranscriptionResult {
    NSMutableString *result = [NSMutableString string];
    int n_segments = whisper_full_n_segments(self->ctx);
    for (int i = 0; i < n_segments; ++i) {
        const char *text = whisper_full_get_segment_text(self->ctx, i);
        [result appendString:[NSString stringWithUTF8String:text]];
    }
    return result;
}

- (void)appendAudioDataToFile:(NSData *)audioData {
    if (!audioFilePath) {
        NSString *filePath = [NSString stringWithUTF8String:state->job->audio_output_path];
        audioFilePath = filePath;
        audioDataSize = 0;

        // Initialize file with placeholder header
        [self initializeAudioFileAtPath:filePath];
    }

    // Write audio data
    [self writeAudioData:audioData toFile:audioFilePath];

    audioDataSize += (int32_t)audioData.length;
}
- (void)initializeAudioFileAtPath:(NSString *)filePath {
    // Create file and write placeholder header
    [[NSFileManager defaultManager] createFileAtPath:filePath contents:nil attributes:nil];
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];

    // Write placeholder header (44 bytes of zeros)
    uint8_t header[44] = {0};
    NSData *headerData = [NSData dataWithBytes:header length:44];
    [fileHandle writeData:headerData];

    [fileHandle closeFile];
}

- (void)writeAudioData:(NSData *)data toFile:(NSString *)filePath {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:filePath];
    [fileHandle seekToEndOfFile];
    [fileHandle writeData:data];
    [fileHandle closeFile];
}

- (void)finalizeAudioFile {
    if (audioFilePath && audioDataSize > 0) {
        [self updateWAVHeaderAtPath:audioFilePath dataSize:audioDataSize];
        audioFilePath = nil;
        audioDataSize = 0;
    }
}
- (void)updateWAVHeaderAtPath:(NSString *)filePath dataSize:(int32_t)dataSize {
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForUpdatingAtPath:filePath];
    if (!fileHandle) {
        NSLog(@"Failed to open file for updating: %@", filePath);
        return;
    }

    // Update WAV header
    [fileHandle seekToFileOffset:0];

    // Construct WAV header with correct sizes
    NSMutableData *header = [NSMutableData data];

    // RIFF header
    [header appendBytes:"RIFF" length:4];
    int32_t chunkSize = 36 + dataSize;
    [header appendBytes:&chunkSize length:4];
    [header appendBytes:"WAVE" length:4];

    // fmt subchunk
    [header appendBytes:"fmt " length:4];
    int32_t subChunk1Size = 16;
    [header appendBytes:&subChunk1Size length:4];
    int16_t audioFormat = 1;
    [header appendBytes:&audioFormat length:2];
    int16_t numChannels = 1;
    [header appendBytes:&numChannels length:2];
    int32_t sampleRate = WHISPER_SAMPLE_RATE;
    [header appendBytes:&sampleRate length:4];
    int32_t byteRate = WHISPER_SAMPLE_RATE * 2;
    [header appendBytes:&byteRate length:4];
    int16_t blockAlign = 2;
    [header appendBytes:&blockAlign length:2];
    int16_t bitsPerSample = 16;
    [header appendBytes:&bitsPerSample length:2];

    // data subchunk
    [header appendBytes:"data" length:4];
    [header appendBytes:&dataSize length:4];

    // Write the header
    [fileHandle writeData:header];
    [fileHandle closeFile];
}
- (void)finishRealtimeTranscribe:(RNWhisperContextRecordState*) state result:(NSDictionary*)result {
    // Finalize WAV file if needed
    if (state->job->audio_output_path != nullptr) {
        [self finalizeAudioFile];
    }
    state->transcribeHandler(state->job->job_id, @"end", result);
    rnwhisper::job_remove(state->job->job_id);
}

- (NSData *)generateWAVHeaderWithDataSize:(NSInteger)dataSize {
    // Implement WAV header generation
    // Return NSData containing the WAV header

    // Omitted for brevity
    return headerData;
}


- (void)stopAudio {
    AudioQueueStop(self->recordState.queue, true);
    for (int i = 0; i < NUM_BUFFERS; i++) {
        AudioQueueFreeBuffer(self->recordState.queue, self->recordState.buffers[i]);
    }
    AudioQueueDispose(self->recordState.queue, true);
}

- (void)stopTranscribe:(int)jobId {
    NSLog(@"[custom-RNWhisper] Stop transcribe");
    if (self->recordState.job) self->recordState.job->abort();
    if (self->recordState.isRealtime && self->recordState.isCapturing) {
        [self stopAudio];
        if (!self->recordState.isTranscribing) {
            // Handle for VAD case
            self->recordState.transcribeHandler(jobId, @"end", @{});
        }
    }
    self->recordState.isCapturing = false;
    self->recordState.isStoppedByAction = true;
    dispatch_barrier_sync(dQueue, ^{});
}

- (void)stopCurrentTranscribe {
    if (self->recordState.job == nullptr) return;
    [self stopTranscribe:self->recordState.job->job_id];
}

- (struct whisper_full_params)createParams:(NSDictionary *)options jobId:(int)jobId {
    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

    const int n_threads = options[@"maxThreads"] != nil ?
      [options[@"maxThreads"] intValue] : 0;

    const int max_threads = (int) [[NSProcessInfo processInfo] processorCount];
    // Use 2 threads by default on 4-core devices, 4 threads on more cores
    const int default_n_threads = max_threads == 4 ? 2 : MIN(4, max_threads);

    if (options[@"beamSize"] != nil) {
        params.strategy = WHISPER_SAMPLING_BEAM_SEARCH;
        params.beam_search.beam_size = [options[@"beamSize"] intValue];
    }

    params.print_realtime   = false;
    params.print_progress   = false;
    params.print_timestamps = false;
    params.print_special    = false;
    params.translate        = options[@"translate"] != nil ? [options[@"translate"] boolValue] : false;
    params.language         = options[@"language"] != nil ? strdup([options[@"language"] UTF8String]) : "auto";
    params.n_threads        = n_threads > 0 ? n_threads : default_n_threads;
    params.offset_ms        = 0;
    params.no_context       = false;
    params.split_on_word = true; // whisper.cpp also set to true
    params.single_segment   = false;

    if (options[@"maxLen"] != nil) {
        params.max_len = [options[@"maxLen"] intValue];
    }
    params.token_timestamps = options[@"tokenTimestamps"] != nil ? [options[@"tokenTimestamps"] boolValue] : false;
    params.tdrz_enable = options[@"tdrzEnable"] != nil ? [options[@"tdrzEnable"] boolValue] : false;

    if (options[@"bestOf"] != nil) {
        params.greedy.best_of = [options[@"bestOf"] intValue];
    }
    if (options[@"maxContext"] != nil) {
        params.n_max_text_ctx = [options[@"maxContext"] intValue];
    }
    if (options[@"offset"] != nil) {
        params.offset_ms = [options[@"offset"] intValue];
    }
    if (options[@"duration"] != nil) {
        params.duration_ms = [options[@"duration"] intValue];
    }
    if (options[@"wordThold"] != nil) {
        params.thold_pt = [options[@"wordThold"] intValue];
    }
    if (options[@"temperature"] != nil) {
        params.temperature = [options[@"temperature"] floatValue];
    }
    if (options[@"temperatureInc"] != nil) {
        params.temperature_inc = [options[@"temperature_inc"] floatValue];
    }
    if (options[@"prompt"] != nil) {
        params.initial_prompt = strdup([options[@"prompt"] UTF8String]);
    }

    return params;
}

- (NSString *)bench:(int)maxThreads {
    const int n_threads = maxThreads > 0 ? maxThreads : 0;

    const int max_threads = (int) [[NSProcessInfo processInfo] processorCount];
    // Use 2 threads by default on 4-core devices, 4 threads on more cores
    const int default_n_threads = max_threads == 4 ? 2 : MIN(4, max_threads);
    NSString *result = [NSString stringWithUTF8String:rnwhisper::bench(self->ctx, n_threads).c_str()];
    return result;
}

- (void)invalidate {
    if (self->recordState.isCapturing) {
        [self stopAudio];
    }

    if (self->prompt_tokens) {
        free(self->prompt_tokens);
        self->prompt_tokens = NULL;
    }

    [self finalizeAudioFile];

    // Other cleanup code...
}


struct rnwhisper_segments_callback_data {
    void (^onNewSegments)(NSDictionary *);
    int total_n_new;
    bool tdrzEnable;
};

- (void)transcribeData:(int)jobId
    audioData:(float *)audioData
    audioDataCount:(int)audioDataCount
    options:(NSDictionary *)options
    onProgress:(void (^)(int))onProgress
    onNewSegments:(void (^)(NSDictionary *))onNewSegments
    onEnd:(void (^)(int))onEnd
{
    dispatch_async(dQueue, ^{
        self->recordState.isStoppedByAction = false;
        self->recordState.isTranscribing = true;

        whisper_full_params params = [self createParams:options jobId:jobId];

        if (options[@"onProgress"] && [options[@"onProgress"] boolValue]) {
            params.progress_callback = [](struct whisper_context * /*ctx*/, struct whisper_state * /*state*/, int progress, void * user_data) {
                void (^onProgress)(int) = (__bridge void (^)(int))user_data;
                onProgress(progress);
            };
            params.progress_callback_user_data = (__bridge void *)(onProgress);
        }

        if (options[@"onNewSegments"] && [options[@"onNewSegments"] boolValue]) {
            params.new_segment_callback = [](struct whisper_context * ctx, struct whisper_state * /*state*/, int n_new, void * user_data) {
                struct rnwhisper_segments_callback_data *data = (struct rnwhisper_segments_callback_data *)user_data;
                data->total_n_new += n_new;

                NSString *text = @"";
                NSMutableArray *segments = [[NSMutableArray alloc] init];
                for (int i = data->total_n_new - n_new; i < data->total_n_new; i++) {
                    const char * text_cur = whisper_full_get_segment_text(ctx, i);
                    if (text_cur == NULL) {
                        // Skip this segment or handle it safely
                        continue;
                    }
                    NSMutableString *mutable_ns_text = [NSMutableString stringWithUTF8String:text_cur];
                    if (!mutable_ns_text) {
                        // This means text_cur could not be converted to a string; skip or handle
                        continue;
                    }

                    if (data->tdrzEnable && whisper_full_get_segment_speaker_turn_next(ctx, i)) {
                        [mutable_ns_text appendString:@" [SPEAKER_TURN]"];
                    }

                    text = [text stringByAppendingString:mutable_ns_text];

                    const int64_t t0 = whisper_full_get_segment_t0(ctx, i);
                    const int64_t t1 = whisper_full_get_segment_t1(ctx, i);
                    NSDictionary *segment = @{
                        @"text": [NSString stringWithString:mutable_ns_text],
                        @"t0": [NSNumber numberWithLongLong:t0],
                        @"t1": [NSNumber numberWithLongLong:t1]
                    };
                    [segments addObject:segment];
                }

                NSDictionary *result = @{
                    @"nNew": [NSNumber numberWithInt:n_new],
                    @"totalNNew": [NSNumber numberWithInt:data->total_n_new],
                    @"result": text,
                    @"segments": segments
                };
                void (^onNewSegments)(NSDictionary *) = (void (^)(NSDictionary *))data->onNewSegments;
                onNewSegments(result);
            };
            struct rnwhisper_segments_callback_data user_data = {
                .onNewSegments = onNewSegments,
                .tdrzEnable = options[@"tdrzEnable"] && [options[@"tdrzEnable"] boolValue],
                .total_n_new = 0,
            };
            params.new_segment_callback_user_data = &user_data;
        }

        rnwhisper::job* job = rnwhisper::job_new(jobId, params);
        self->recordState.job = job;
        int code = [self fullTranscribe:job audioData:audioData audioDataCount:audioDataCount];
        rnwhisper::job_remove(jobId);
        self->recordState.isTranscribing = false;
        onEnd(code);
    });
}

@end

