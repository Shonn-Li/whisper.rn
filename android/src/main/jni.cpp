#include <jni.h>
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>
#include <android/log.h>
#include <cstdlib>
#include <sys/sysinfo.h>
#include <string>
#include <thread>
#include <sstream>
#include <vector>
#include "whisper.h"
#include "rn-whisper.h"
#include "ggml.h"
#include "jni-utils.h"
// #include <unicode/ustring.h>

#define UNUSED(x) (void)(x)
#define TAG "JNI"

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,     TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR,    TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,     TAG, __VA_ARGS__)

static inline int min(int a, int b) {
    return (a < b) ? a : b;
}

// Load model from input stream (used for drawable / raw resources)
struct input_stream_context {
    JNIEnv *env;
    jobject input_stream;
};

static size_t input_stream_read(void *ctx, void *output, size_t read_size) {
    input_stream_context *context = (input_stream_context *)ctx;
    JNIEnv *env = context->env;
    jobject input_stream = context->input_stream;
    jclass input_stream_class = env->GetObjectClass(input_stream);

    jbyteArray buffer = env->NewByteArray(read_size);
    jint bytes_read = env->CallIntMethod(
        input_stream,
        env->GetMethodID(input_stream_class, "read", "([B)I"),
        buffer
    );

    if (bytes_read > 0) {
        env->GetByteArrayRegion(buffer, 0, bytes_read, (jbyte *) output);
    }

    env->DeleteLocalRef(buffer);

    return bytes_read;
}

static bool input_stream_is_eof(void *ctx) {
    input_stream_context *context = (input_stream_context *)ctx;
    JNIEnv *env = context->env;
    jobject input_stream = context->input_stream;

    jclass input_stream_class = env->GetObjectClass(input_stream);

    jbyteArray buffer = env->NewByteArray(1);
    jint bytes_read = env->CallIntMethod(
        input_stream,
        env->GetMethodID(input_stream_class, "read", "([B)I"),
        buffer
    );

    bool is_eof = (bytes_read == -1);
    if (!is_eof) {
        // If we successfully read a byte, "unread" it by pushing it back into the stream.
        env->CallVoidMethod(
            input_stream,
            env->GetMethodID(input_stream_class, "unread", "([BII)V"),
            buffer,
            0,
            1
        );
    }

    env->DeleteLocalRef(buffer);

    return is_eof;
}

static void input_stream_close(void *ctx) {
    input_stream_context *context = (input_stream_context *)ctx;
    JNIEnv *env = context->env;
    jobject input_stream = context->input_stream;
    jclass input_stream_class = env->GetObjectClass(input_stream);

    env->CallVoidMethod(
        input_stream,
        env->GetMethodID(input_stream_class, "close", "()V")
    );

    env->DeleteGlobalRef(input_stream);
}

static struct whisper_context *whisper_init_from_input_stream(
    JNIEnv *env,
    jobject input_stream, // PushbackInputStream
    struct whisper_context_params cparams
) {
    input_stream_context *context = new input_stream_context;
    context->env = env;
    context->input_stream = env->NewGlobalRef(input_stream);

    whisper_model_loader loader = {
        .context = context,
        .read = &input_stream_read,
        .eof = &input_stream_is_eof,
        .close = &input_stream_close
    };
    return whisper_init_with_params(&loader, cparams);
}

// Load model from asset
static size_t asset_read(void *ctx, void *output, size_t read_size) {
    return AAsset_read((AAsset *) ctx, output, read_size);
}

static bool asset_is_eof(void *ctx) {
    return AAsset_getRemainingLength64((AAsset *) ctx) <= 0;
}

static void asset_close(void *ctx) {
    AAsset_close((AAsset *) ctx);
}

static struct whisper_context *whisper_init_from_asset(
    JNIEnv *env,
    jobject assetManager,
    const char *asset_path,
    struct whisper_context_params cparams
) {
    LOGI("Loading model from asset '%s'\n", asset_path);
    AAssetManager *asset_manager = AAssetManager_fromJava(env, assetManager);
    AAsset *asset = AAssetManager_open(asset_manager, asset_path, AASSET_MODE_STREAMING);
    if (!asset) {
        LOGW("Failed to open '%s'\n", asset_path);
        return NULL;
    }
    whisper_model_loader loader = {
        .context = asset,
        .read = &asset_read,
        .eof = &asset_is_eof,
        .close = &asset_close
    };
    return whisper_init_with_params(&loader, cparams);
}

extern "C" {

JNIEXPORT jlong JNICALL
Java_com_rnwhisper_WhisperContext_initContext(
        JNIEnv *env, jobject thiz, jstring model_path_str) {
    UNUSED(thiz);
    struct whisper_context_params cparams;
    cparams.dtw_token_timestamps = false;

    struct whisper_context *context = nullptr;
    const char *model_path_chars = env->GetStringUTFChars(model_path_str, nullptr);
    context = whisper_init_from_file_with_params(model_path_chars, cparams);
    env->ReleaseStringUTFChars(model_path_str, model_path_chars);
    return reinterpret_cast<jlong>(context);
}

JNIEXPORT jlong JNICALL
Java_com_rnwhisper_WhisperContext_initContextWithAsset(
    JNIEnv *env,
    jobject thiz,
    jobject asset_manager,
    jstring model_path_str
) {
    UNUSED(thiz);
    struct whisper_context_params cparams;
    cparams.dtw_token_timestamps = false;

    struct whisper_context *context = nullptr;
    const char *model_path_chars = env->GetStringUTFChars(model_path_str, nullptr);
    context = whisper_init_from_asset(env, asset_manager, model_path_chars, cparams);
    env->ReleaseStringUTFChars(model_path_str, model_path_chars);
    return reinterpret_cast<jlong>(context);
}

JNIEXPORT jlong JNICALL
Java_com_rnwhisper_WhisperContext_initContextWithInputStream(
    JNIEnv *env,
    jobject thiz,
    jobject input_stream
) {
    UNUSED(thiz);
    struct whisper_context_params cparams;
    cparams.dtw_token_timestamps = false;

    struct whisper_context *context = nullptr;
    context = whisper_init_from_input_stream(env, input_stream, cparams);
    return reinterpret_cast<jlong>(context);
}


struct whisper_full_params createFullParams(JNIEnv *env, jobject options) {
    struct whisper_full_params params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);

    params.print_realtime = false;
    params.print_progress = false;
    params.print_timestamps = false;
    params.print_special = false;

    int max_threads = std::thread::hardware_concurrency();
    // Use 2 threads by default on 4-core devices, 4 threads on more cores
    int default_n_threads = max_threads == 4 ? 2 : min(4, max_threads);
    int n_threads = readablemap::getInt(env, options, "maxThreads", default_n_threads);
    params.n_threads = n_threads > 0 ? n_threads : default_n_threads;
    params.translate = readablemap::getBool(env, options, "translate", false);
    params.token_timestamps = readablemap::getBool(env, options, "tokenTimestamps", false);
    params.tdrz_enable = readablemap::getBool(env, options, "tdrzEnable", false);
    params.offset_ms = 0;
    params.no_context = true;
    params.single_segment = false;

    int beam_size = readablemap::getInt(env, options, "beamSize", -1);
    if (beam_size > -1) {
        params.strategy = WHISPER_SAMPLING_BEAM_SEARCH;
        params.beam_search.beam_size = beam_size;
    }
    int best_of = readablemap::getInt(env, options, "bestOf", -1);
    if (best_of > -1) params.greedy.best_of = best_of;
    int max_len = readablemap::getInt(env, options, "maxLen", -1);
    if (max_len > -1) params.max_len = max_len;
    int max_context = readablemap::getInt(env, options, "maxContext", -1);
    if (max_context > -1) params.n_max_text_ctx = max_context;
    int offset = readablemap::getInt(env, options, "offset", -1);
    if (offset > -1) params.offset_ms = offset;
    int duration = readablemap::getInt(env, options, "duration", -1);
    if (duration > -1) params.duration_ms = duration;
    int word_thold = readablemap::getInt(env, options, "wordThold", -1);
    if (word_thold > -1) params.thold_pt = word_thold;
    float temperature = readablemap::getFloat(env, options, "temperature", -1);
    if (temperature > -1) params.temperature = temperature;
    float temperature_inc = readablemap::getFloat(env, options, "temperatureInc", -1);
    if (temperature_inc > -1) params.temperature_inc = temperature_inc;
    jstring prompt = readablemap::getString(env, options, "prompt", nullptr);
    if (prompt != nullptr) {
        params.initial_prompt = env->GetStringUTFChars(prompt, nullptr);
        env->DeleteLocalRef(prompt);
    }
    jstring language = readablemap::getString(env, options, "language", nullptr);
    if (language != nullptr) {
        params.language = env->GetStringUTFChars(language, nullptr);
        env->DeleteLocalRef(language);
    }
    return params;
}

struct callback_context {
    JNIEnv *env;
    jobject callback_instance;
};

JNIEXPORT jint JNICALL
Java_com_rnwhisper_WhisperContext_fullWithNewJob(
    JNIEnv *env,
    jobject thiz,
    jint job_id,
    jlong context_ptr,
    jfloatArray audio_data,
    jint audio_data_len,
    jobject options,
    jobject callback_instance
) {
    UNUSED(thiz);
    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);
    jfloat *audio_data_arr = env->GetFloatArrayElements(audio_data, nullptr);

    LOGI("About to create params");

    whisper_full_params params = createFullParams(env, options);

    if (callback_instance != nullptr) {
        callback_context *cb_ctx = new callback_context;
        cb_ctx->env = env;
        cb_ctx->callback_instance = env->NewGlobalRef(callback_instance);

        params.progress_callback = [](struct whisper_context * /*ctx*/, struct whisper_state * /*state*/, int progress, void * user_data) {
            callback_context *cb_ctx = (callback_context *)user_data;
            JNIEnv *env = cb_ctx->env;
            jobject callback_instance = cb_ctx->callback_instance;
            jclass callback_class = env->GetObjectClass(callback_instance);
            jmethodID onProgress = env->GetMethodID(callback_class, "onProgress", "(I)V");
            env->CallVoidMethod(callback_instance, onProgress, progress);
        };
        params.progress_callback_user_data = cb_ctx;

        params.new_segment_callback = [](struct whisper_context * /*ctx*/, struct whisper_state * /*state*/, int n_new, void * user_data) {
            callback_context *cb_ctx = (callback_context *)user_data;
            JNIEnv *env = cb_ctx->env;
            jobject callback_instance = cb_ctx->callback_instance;
            jclass callback_class = env->GetObjectClass(callback_instance);
            jmethodID onNewSegments = env->GetMethodID(callback_class, "onNewSegments", "(I)V");
            env->CallVoidMethod(callback_instance, onNewSegments, n_new);
        };
        params.new_segment_callback_user_data = cb_ctx;
    }

    rnwhisper::job* job = rnwhisper::job_new(job_id, params);

    LOGI("About to reset timings");
    whisper_reset_timings(context);

    LOGI("About to run whisper_full");
    int code = whisper_full(context, params, audio_data_arr, audio_data_len);
    if (code == 0) {
        // whisper_print_timings(context);
    }
    env->ReleaseFloatArrayElements(audio_data, audio_data_arr, JNI_ABORT);

    if (job->is_aborted()) code = -999;
    rnwhisper::job_remove(job_id);
    return code;
}

JNIEXPORT void JNICALL
Java_com_rnwhisper_WhisperContext_createRealtimeTranscribeJob(
    JNIEnv *env,
    jobject thiz,
    jint job_id,
    jlong context_ptr,
    jobject options
) {
    whisper_full_params params = createFullParams(env, options);
    rnwhisper::job* job = rnwhisper::job_new(job_id, params);
    rnwhisper::vad_params vad;
    vad.use_vad = readablemap::getBool(env, options, "useVad", false);
    vad.vad_ms = readablemap::getInt(env, options, "vadMs", 2000);
    vad.vad_thold = readablemap::getFloat(env, options, "vadThold", 0.6f);
    vad.freq_thold = readablemap::getFloat(env, options, "vadFreqThold", 100.0f);

    jstring audio_output_path = readablemap::getString(env, options, "audioOutputPath", nullptr);
    const char* audio_output_path_str = nullptr;
    if (audio_output_path != nullptr) {
        audio_output_path_str = env->GetStringUTFChars(audio_output_path, nullptr);
        env->DeleteLocalRef(audio_output_path);
    }
    job->set_realtime_params(
        vad,
        readablemap::getInt(env, options, "realtimeAudioSec", 0),
        readablemap::getInt(env, options, "realtimeAudioSliceSec", 0),
        readablemap::getFloat(env, options, "realtimeAudioMinSec", 0),
        audio_output_path_str
    );
}

JNIEXPORT void JNICALL
Java_com_rnwhisper_WhisperContext_finishRealtimeTranscribeJob(
    JNIEnv *env,
    jobject thiz,
    jint job_id,
    jlong context_ptr,
    jintArray slice_n_samples
) {
    UNUSED(env);
    UNUSED(thiz);
    UNUSED(context_ptr);

    rnwhisper::job *job = rnwhisper::job_get(job_id);
    if (job->audio_output_path != nullptr) {
        RNWHISPER_LOG_INFO("job->params.language: %s\n", job->params.language);
        std::vector<int> slice_n_samples_vec;
        jint *slice_n_samples_arr = env->GetIntArrayElements(slice_n_samples, nullptr);
        slice_n_samples_vec = std::vector<int>(slice_n_samples_arr, slice_n_samples_arr + env->GetArrayLength(slice_n_samples));
        env->ReleaseIntArrayElements(slice_n_samples, slice_n_samples_arr, JNI_ABORT);
    }
    rnwhisper::job_remove(job_id);
}

JNIEXPORT jboolean JNICALL
Java_com_rnwhisper_WhisperContext_vadSimple(
    JNIEnv *env,
    jobject thiz,
    jint job_id,
    jint slice_index,
    jint n_samples,
    jint n
) {
    UNUSED(thiz);
    rnwhisper::job* job = rnwhisper::job_get(job_id);
    return job->vad_simple(slice_index, n_samples, n);
}

JNIEXPORT void JNICALL
Java_com_rnwhisper_WhisperContext_putPcmData(
    JNIEnv *env,
    jobject thiz,
    jint job_id,
    jshortArray pcm,
    jint slice_index,
    jint n_samples,
    jint n
) {
    UNUSED(thiz);
    rnwhisper::job* job = rnwhisper::job_get(job_id);
    jshort *pcm_arr = env->GetShortArrayElements(pcm, nullptr);
    job->put_pcm_data(pcm_arr, slice_index, n_samples, n);
    env->ReleaseShortArrayElements(pcm, pcm_arr, JNI_ABORT);
}

JNIEXPORT jint JNICALL
Java_com_rnwhisper_WhisperContext_fullWithJob(
    JNIEnv *env,
    jobject thiz,
    jint job_id,
    jlong context_ptr,
    jint slice_index,
    jint n_samples
) {
    UNUSED(thiz);
    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);

    rnwhisper::job* job = rnwhisper::job_get(job_id);
    float* pcmf32 = job->pcm_slice_to_f32(slice_index, n_samples);
    int code = whisper_full(context, job->params, pcmf32, n_samples);
    free(pcmf32);
    if (code == 0) {
        // whisper_print_timings(context);
    }
    if (job->is_aborted()) code = -999;
    return code;
}

JNIEXPORT void JNICALL
Java_com_rnwhisper_WhisperContext_abortTranscribe(
    JNIEnv *env,
    jobject thiz,
    jint job_id
) {
    UNUSED(thiz);
    rnwhisper::job *job = rnwhisper::job_get(job_id);
    if (job) job->abort();
}

JNIEXPORT void JNICALL
Java_com_rnwhisper_WhisperContext_abortAllTranscribe(
    JNIEnv *env,
    jobject thiz
) {
    UNUSED(thiz);
    rnwhisper::job_abort_all();
}

JNIEXPORT jint JNICALL
Java_com_rnwhisper_WhisperContext_getTextSegmentCount(
        JNIEnv *env, jobject thiz, jlong context_ptr) {
    UNUSED(env);
    UNUSED(thiz);
    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);
    return whisper_full_n_segments(context);
}

JNIEXPORT jstring JNICALL
Java_com_rnwhisper_WhisperContext_getTextSegment(
        JNIEnv *env, jobject thiz, jlong context_ptr, jint index) {
    UNUSED(thiz);
    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);
    const char *text = whisper_full_get_segment_text(context, index);
    jstring string = env->NewStringUTF(text);
    return string;
}

// Helper function to validate UTF-8

// Helper function to manually check if a string is valid UTF-8
bool isValidUtf8S(const std::string& str) {
    size_t i = 0;
    while (i < str.size()) {
        unsigned char c = str[i];
        
        // Single-byte characters (ASCII)
        if (c <= 0x7F) {
            ++i;
        }
        // Two-byte characters
        else if ((c & 0xE0) == 0xC0) {
            if (i + 1 < str.size() && (str[i+1] & 0xC0) == 0x80) {
                i += 2;
            } else {
                return false;
            }
        }
        // Three-byte characters
        else if ((c & 0xF0) == 0xE0) {
            if (i + 2 < str.size() && (str[i+1] & 0xC0) == 0x80 && (str[i+2] & 0xC0) == 0x80) {
                i += 3;
            } else {
                return false;
            }
        }
        // Four-byte characters
        else if ((c & 0xF8) == 0xF0) {
            if (i + 3 < str.size() && (str[i+1] & 0xC0) == 0x80 && (str[i+2] & 0xC0) == 0x80 && (str[i+3] & 0xC0) == 0x80) {
                i += 4;
            } else {
                return false;
            }
        } else {
            return false;  // Invalid byte
        }
    }
    return true;
}
struct Segment {
    std::string text;
    int t0;
    int t1;
};

// Utility function to convert the segments into a JSON string
std::string toJson(const std::vector<Segment>& segments, const std::string& combinedText) {
    std::stringstream jsonStream;
    jsonStream << "{";
    jsonStream << "\"result\": \"" << combinedText << "\",";
    jsonStream << "\"segments\": [";

    for (size_t i = 0; i < segments.size(); ++i) {
        const Segment& segment = segments[i];
        jsonStream << "{";
        jsonStream << "\"text\": \"" << segment.text << "\",";
        jsonStream << "\"t0\": " << segment.t0 << ",";
        jsonStream << "\"t1\": " << segment.t1;
        jsonStream << "}";
        if (i < segments.size() - 1) {
            jsonStream << ",";
        }
    }
    jsonStream << "]}";
    return jsonStream.str();
}
// Helper function to manually validate UTF-8
bool isValidUtf8(const std::vector<char>& buffer) {
    int i = 0;
    while (i < buffer.size()) {
        unsigned char byte = static_cast<unsigned char>(buffer[i]);
        
        // Check for 1-byte character (ASCII)
        if ((byte & 0x80) == 0) {
            i++;
        }
        // Check for 2-byte character
        else if ((byte & 0xE0) == 0xC0) {
            if (i + 1 < buffer.size() && (static_cast<unsigned char>(buffer[i + 1]) & 0xC0) == 0x80) {
                i += 2;
            } else {
                return false;
            }
        }
        // Check for 3-byte character
        else if ((byte & 0xF0) == 0xE0) {
            if (i + 2 < buffer.size() && (static_cast<unsigned char>(buffer[i + 1]) & 0xC0) == 0x80
                && (static_cast<unsigned char>(buffer[i + 2]) & 0xC0) == 0x80) {
                i += 3;
            } else {
                return false;
            }
        }
        // Check for 4-byte character
        else if ((byte & 0xF8) == 0xF0) {
            if (i + 3 < buffer.size() && (static_cast<unsigned char>(buffer[i + 1]) & 0xC0) == 0x80
                && (static_cast<unsigned char>(buffer[i + 2]) & 0xC0) == 0x80
                && (static_cast<unsigned char>(buffer[i + 3]) & 0xC0) == 0x80) {
                i += 4;
            } else {
                return false;
            }
        }
        else {
            return false;  // Invalid byte
        }
    }
    return true;
}

JNIEXPORT jstring JNICALL
Java_com_rnwhisper_WhisperContext_JNIGetTextSegments(
    JNIEnv *env, jobject thiz, jlong context_ptr, jint start, jint count, jboolean tdrzEnable) {

    LOGI("JNIGetTextSegments: Start");

    UNUSED(thiz);

    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);
    std::vector<Segment> segments;

    std::vector<char> tempData;  // Buffer for raw text data
    std::string combinedText;    // Final combined text result

    LOGI("JNIGetTextSegments: Looping over segments, start: %d, count: %d", start, count);
    for (int i = start; i < start + count; i++) {
        LOGI("JNIGetTextSegments: Processing segment %d", i);

        const char *text = whisper_full_get_segment_text(context, i);
        if (text == NULL || strlen(text) == 0) {
            LOGW("JNIGetTextSegments: Skipping empty or NULL text in segment %d", i);
            continue;
        }

        size_t textLength = strlen(text);
        LOGI("JNIGetTextSegments: Text length for segment %d: %zu", i, textLength);

        tempData.insert(tempData.end(), text, text + textLength);

        // Ensure valid UTF-8
        tempData.push_back(0); // Null-terminate for UTF-8 validation
        if (isValidUtf8(tempData)) {
            std::string validText(tempData.begin(), tempData.end() - 1);  // Remove null terminator
            combinedText += validText;

            Segment segment;
            segment.text = validText;
            LOGI("JNIGetTextSegments: Text for segment %d: %s", i, segment.text.c_str());
            segment.t0 = whisper_full_get_segment_t0(context, i);
            segment.t1 = whisper_full_get_segment_t1(context, i);

            // Handle speaker turn if enabled
            if (tdrzEnable && whisper_full_get_segment_speaker_turn_next(context, i)) {
                segment.text += " [SPEAKER_TURN]";
                combinedText += " [SPEAKER_TURN]";
            }

            segments.push_back(segment);
            tempData.clear();
        } else {
            LOGW("JNIGetTextSegments: UTF-8 validation failed for segment %d", i);
            // If not valid yet, remove the null terminator and wait for next segment
            tempData.pop_back(); // Remove last byte if invalid UTF-8
        }
    }

    LOGI("JNIGetTextSegments: Finished processing segments with text: %s", combinedText.c_str());
    
    // Convert result into a JSON string
    std::string jsonString = toJson(segments, combinedText);
    LOGI("JNIGetTextSegments: JSON string: %s", jsonString.c_str());

    // Return the JSON string as jstring
    return env->NewStringUTF(jsonString.c_str());
}

JNIEXPORT jint JNICALL
Java_com_rnwhisper_WhisperContext_getTextSegmentT0(
        JNIEnv *env, jobject thiz, jlong context_ptr, jint index) {
    UNUSED(env);
    UNUSED(thiz);
    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);
    return whisper_full_get_segment_t0(context, index);
}

JNIEXPORT jint JNICALL
Java_com_rnwhisper_WhisperContext_getTextSegmentT1(
        JNIEnv *env, jobject thiz, jlong context_ptr, jint index) {
    UNUSED(env);
    UNUSED(thiz);
    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);
    return whisper_full_get_segment_t1(context, index);
}

JNIEXPORT void JNICALL
Java_com_rnwhisper_WhisperContext_freeContext(
        JNIEnv *env, jobject thiz, jlong context_ptr) {
    UNUSED(env);
    UNUSED(thiz);
    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);
    whisper_free(context);
}

JNIEXPORT jboolean JNICALL
Java_com_rnwhisper_WhisperContext_getTextSegmentSpeakerTurnNext(
        JNIEnv *env, jobject thiz, jlong context_ptr, jint index) {
    UNUSED(env);
    UNUSED(thiz);
    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);
    return whisper_full_get_segment_speaker_turn_next(context, index);
}

JNIEXPORT jstring JNICALL
Java_com_rnwhisper_WhisperContext_bench(
    JNIEnv *env,
    jobject thiz,
    jlong context_ptr,
    jint n_threads
) {
    UNUSED(thiz);
    struct whisper_context *context = reinterpret_cast<struct whisper_context *>(context_ptr);
    std::string result = rnwhisper::bench(context, n_threads);
    return env->NewStringUTF(result.c_str());
}

} // extern "C"
