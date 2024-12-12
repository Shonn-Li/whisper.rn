
- (int)fullTranscribe:(rnwhisper::job *)job
  audioData:(float *)audioData
  audioDataCount:(int)audioDataCount
{
    whisper_reset_timings(self->ctx);
    int code = whisper_full(self->ctx, job->params, audioData, audioDataCount);
    if (job && job->is_aborted()) code = -999;
    // if (code == 0) {
    //     whisper_print_timings(self->ctx);
    // }
    return code;
}

- (NSMutableDictionary *)getTextSegments {
    NSString *text = @"";
    int n_segments = whisper_full_n_segments(self->ctx);

    NSMutableArray *segments = [[NSMutableArray alloc] init];
    NSLog(@"[Custom-RNWhisper] getTextSegments");
    for (int i = 0; i < n_segments; i++) {
        const char * text_cur = whisper_full_get_segment_text(self->ctx, i);
        NSMutableString *mutable_ns_text = [NSMutableString stringWithUTF8String:text_cur];
        if (!mutable_ns_text) {

            NSLog(@"[Custom-RNWhisper] mutable_ns_text is nil");
            // Handle gracefully or skip
            continue;
        }

        // Simplified condition
        if (self->recordState.options[@"tdrzEnable"] &&
            [self->recordState.options[@"tdrzEnable"] boolValue] &&
            whisper_full_get_segment_speaker_turn_next(self->ctx, i)) {
            [mutable_ns_text appendString:@" [SPEAKER_TURN]"];
        }

        text = [text stringByAppendingString:mutable_ns_text];

        const int64_t t0 = whisper_full_get_segment_t0(self->ctx, i);
        const int64_t t1 = whisper_full_get_segment_t1(self->ctx, i);
        NSDictionary *segment = @{
            @"text": [NSString stringWithString:mutable_ns_text],
            @"t0": [NSNumber numberWithLongLong:t0],
            @"t1": [NSNumber numberWithLongLong:t1]
        };
        [segments addObject:segment];
    }
    NSMutableDictionary *result = [[NSMutableDictionary alloc] init];
    result[@"result"] = text;
    result[@"segments"] = segments;
    return result;
}

void AudioInputCallback(void * inUserData,
    AudioQueueRef inAQ,
    AudioQueueBufferRef inBuffer,
    const AudioTimeStamp * inStartTime,
    UInt32 inNumberPacketDescriptions,
    const AudioStreamPacketDescription * inPacketDescs)
{
    RNWhisperContextRecordState *state = (RNWhisperContextRecordState *)inUserData;
    NSLog(@"[custom-RNWhisper] AudioInputCallback");

    if (!state->isCapturing) {
        NSLog(@"[RNWhisper] Not capturing, ignoring audio");
        if (!state->isTranscribing) {
            [state->mSelf finishRealtimeTranscribe:state result:@{}];
        }
        return;
    }

    int totalNSamples = 0;
    for (int i = 0; i < state->sliceNSamples.size(); i++) {
        totalNSamples += state->sliceNSamples[i];
    }

    const int n = inBuffer->mAudioDataByteSize / 2;

    int nSamples = state->sliceNSamples[state->sliceIndex];

    if (totalNSamples + n > state->job->audio_sec * WHISPER_SAMPLE_RATE) {
        NSLog(@"[RNWhisper] Audio buffer is full, stop capturing");
        state->isCapturing = false;
        [state->mSelf stopAudio];
        if (
            !state->isTranscribing &&
            nSamples == state->nSamplesTranscribing &&
            state->sliceIndex == state->transcribeSliceIndex
        ) {
            [state->mSelf finishRealtimeTranscribe:state result:@{}];
        } else if (
            !state->isTranscribing &&
            nSamples != state->nSamplesTranscribing
        ) {
            bool isSamplesEnough = nSamples / WHISPER_SAMPLE_RATE >= state->job->audio_min_sec;
            if (!isSamplesEnough || !vad(state, state->sliceIndex, nSamples, 0)) {
                [state->mSelf finishRealtimeTranscribe:state result:@{}];
                return;
            }
            state->isTranscribing = true;
            dispatch_async([state->mSelf getDispatchQueue], ^{
                [state->mSelf fullTranscribeSamples:state];
            });
        }
        return;
    }

    if (nSamples + n > state->job->audio_slice_sec * WHISPER_SAMPLE_RATE) {
        // next slice
        state->sliceIndex++;
        nSamples = 0;
        state->sliceNSamples.push_back(0);
    }

    NSLog(@"[custom-RNWhisper] Slice %d has %d samples, put %d samples", state->sliceIndex, nSamples, n);

    state->job->put_pcm_data((short*) inBuffer->mAudioData, state->sliceIndex, nSamples, n);

    bool isSpeech = vad(state, state->sliceIndex, nSamples, n);
    nSamples += n;
    state->sliceNSamples[state->sliceIndex] = nSamples;

    AudioQueueEnqueueBuffer(state->queue, inBuffer, 0, NULL);

    bool isSamplesEnough = nSamples / WHISPER_SAMPLE_RATE >= state->job->audio_min_sec;
    if (!isSamplesEnough || !isSpeech) return;

    if (!state->isTranscribing) {
        state->isTranscribing = true;
        dispatch_async([state->mSelf getDispatchQueue], ^{
            [state->mSelf fullTranscribeSamples:state];
        });
    }
}


- (void)finishRealtimeTranscribe:(RNWhisperContextRecordState*) state result:(NSDictionary*)result {
    // Save wav if needed
    NSLog(@"[custom-RNWhisper] audio output path: %s", state->job->audio_output_path);
    if (state->job->audio_output_path != nullptr) {
        NSLog(@"[custom-RNWhisper] audio output path not null");
        // TODO: Append in real time so we don't need to keep all slices & also reduce memory usage
        rnaudioutils::save_wav_file(
            rnaudioutils::concat_short_buffers(state->job->pcm_slices, state->sliceNSamples),
            state->job->audio_output_path
        );
        NSLog(@"[custom-RNWhisper] save_wav_file excuted");
    }
    state->transcribeHandler(state->job->job_id, @"end", result);
    rnwhisper::job_remove(state->job->job_id);
}

- (void)fullTranscribeSamples:(RNWhisperContextRecordState*) state {
    int nSamplesOfIndex = state->sliceNSamples[state->transcribeSliceIndex];
    state->nSamplesTranscribing = nSamplesOfIndex;
    NSLog(@"[RNWhisper] Transcribing %d samples", state->nSamplesTranscribing);

    float* pcmf32 = state->job->pcm_slice_to_f32(state->transcribeSliceIndex, state->nSamplesTranscribing);

    CFTimeInterval timeStart = CACurrentMediaTime();
    int code = [state->mSelf fullTranscribe:state->job audioData:pcmf32 audioDataCount:state->nSamplesTranscribing];
    free(pcmf32);
    CFTimeInterval timeEnd = CACurrentMediaTime();
    const float timeRecording = (float) state->nSamplesTranscribing / (float) state->dataFormat.mSampleRate;

    NSDictionary* base = @{
        @"code": [NSNumber numberWithInt:code],
        @"processTime": [NSNumber numberWithInt:(timeEnd - timeStart) * 1E3],
        @"recordingTime": [NSNumber numberWithInt:timeRecording * 1E3],
        @"isUseSlices": @(state->isUseSlices),
        @"sliceIndex": @(state->transcribeSliceIndex),
    };

    NSMutableDictionary* result = [base mutableCopy];

    if (code == 0) {
        result[@"data"] = [state->mSelf getTextSegments];
    } else {
        result[@"error"] = [NSString stringWithFormat:@"Transcribe failed with code %d", code];
    }

    nSamplesOfIndex = state->sliceNSamples[state->transcribeSliceIndex];

    bool isStopped = state->isStoppedByAction || (
        !state->isCapturing &&
        state->nSamplesTranscribing == nSamplesOfIndex &&
        state->sliceIndex == state->transcribeSliceIndex
    );

    if (
      // If no more samples on current slice, move to next slice
      state->nSamplesTranscribing == nSamplesOfIndex &&
      state->transcribeSliceIndex != state->sliceIndex
    ) {
        state->transcribeSliceIndex++;
        state->nSamplesTranscribing = 0;
    }

    bool continueNeeded = !state->isCapturing &&
        state->nSamplesTranscribing != nSamplesOfIndex;

    if (isStopped && !continueNeeded) {
        NSLog(@"[RNWhisper] Transcribe end");
        result[@"isStoppedByAction"] = @(state->isStoppedByAction);
        result[@"isCapturing"] = @(false);

        [state->mSelf finishRealtimeTranscribe:state result:result];
    } else if (code == 0) {
        result[@"isCapturing"] = @(true);
        state->transcribeHandler(state->job->job_id, @"transcribe", result);
    } else {
        result[@"isCapturing"] = @(true);
        state->transcribeHandler(state->job->job_id, @"transcribe", result);
    }

    if (continueNeeded) {
        state->isTranscribing = true;
        // Finish transcribing the rest of the samples
        [self fullTranscribeSamples:state];
    }
    state->isTranscribing = false;
}