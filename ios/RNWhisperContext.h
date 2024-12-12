#ifdef __cplusplus
#import "whisper.h"
#import "rn-whisper.h"
#endif

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioQueue.h>

#define NUM_BUFFERS 3
#define DEFAULT_MAX_AUDIO_SEC 30

typedef struct {
    __unsafe_unretained id mSelf;
    NSDictionary* options;

    struct rnwhisper::job * job;

    bool isTranscribing;
    bool isRealtime;
    bool isCapturing;
    bool isStoppedByAction;
    int nSamplesTranscribing;
    std::vector<int> sliceNSamples;
    bool isUseSlices;
    int sliceIndex;
    int transcribeSliceIndex;
    NSString* audioOutputPath;
    
    int step_ms;
    int length_ms;
    int keep_ms;

    int step_samples;
    int length_samples;
    int keep_samples;

    NSMutableData *pcm_buffer;

    int32_t *prompt_tokens;
    int n_prompt_tokens;
    AudioQueueRef queue;
    AudioStreamBasicDescription dataFormat;
    AudioQueueBufferRef buffers[NUM_BUFFERS];

    void (^transcribeHandler)(int, NSString *, NSDictionary *);
    
    NSUInteger new_samples_count;
} RNWhisperContextRecordState;

@interface RNWhisperContext : NSObject {
    int contextId;
    dispatch_queue_t dQueue;
    struct whisper_context * ctx;
    RNWhisperContextRecordState recordState;
    NSString * reasonNoMetal;
    bool isMetalEnabled;
}

+ (instancetype)initWithModelPath:(NSString *)modelPath contextId:(int)contextId noCoreML:(BOOL)noCoreML noMetal:(BOOL)noMetal useFlashAttn:(BOOL)useFlashAttn;
- (bool)isMetalEnabled;
- (NSString *)reasonNoMetal;
- (struct whisper_context *)getContext;
- (dispatch_queue_t)getDispatchQueue;
- (OSStatus)transcribeRealtime:(int)jobId
    options:(NSDictionary *)options
    onTranscribe:(void (^)(int, NSString *, NSDictionary *))onTranscribe;
- (void)transcribeData:(int)jobId
    audioData:(float *)audioData
    audioDataCount:(int)audioDataCount
    options:(NSDictionary *)options
    onProgress:(void (^)(int))onProgress
    onNewSegments:(void (^)(NSDictionary *))onNewSegments
    onEnd:(void (^)(int))onEnd;
- (void)stopTranscribe:(int)jobId;
- (void)stopCurrentTranscribe;
- (bool)isCapturing;
- (bool)isTranscribing;
- (bool)isStoppedByAction;
- (NSMutableDictionary *)getTextSegments;
- (NSString *)bench:(int)maxThreads;
- (void)invalidate;

@end
