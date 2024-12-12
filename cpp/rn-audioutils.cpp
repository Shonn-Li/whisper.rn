#include "rn-audioutils.h"
#include "rn-whisper-log.h"

namespace rnaudioutils {

std::vector<uint8_t> concat_short_buffers(const std::vector<short*>& buffers, const std::vector<int>& slice_n_samples) {
    
    RNWHISPER_LOG_INFO("Concating short buffer");
    std::vector<uint8_t> output_data;

    for (size_t i = 0; i < buffers.size(); i++) {
        int size = slice_n_samples[i]; // Number of shorts
        short* slice = buffers[i];

        // Copy each short as two bytes
        for (int j = 0; j < size; j++) {
            output_data.push_back(static_cast<uint8_t>(slice[j] & 0xFF));         // Lower byte
            output_data.push_back(static_cast<uint8_t>((slice[j] >> 8) & 0xFF));  // Higher byte
        }
    }

    return output_data;
}

std::vector<uint8_t> remove_trailing_zeros(const std::vector<uint8_t>& audio_data) {
    auto last = std::find_if(audio_data.rbegin(), audio_data.rend(), [](uint8_t byte) { return byte != 0; });
    return std::vector<uint8_t>(audio_data.begin(), last.base());
}

void save_wav_file(const std::vector<uint8_t>& raw, const std::string& file) {

    RNWHISPER_LOG_INFO("Saving audio file: %s\n", file.c_str());
    std::vector<uint8_t> data = remove_trailing_zeros(raw);
    
    std::ofstream output(file, std::ios::binary);

    if (!output.is_open()) {
        RNWHISPER_LOG_ERROR("Failed to open file for writing: %s\n", file.c_str());
        return;
    }

    // WAVE header
    output.write("RIFF", 4);
    int32_t chunk_size = 36 + static_cast<int32_t>(data.size());
    output.write(reinterpret_cast<char*>(&chunk_size), sizeof(chunk_size));
    output.write("WAVE", 4);
    output.write("fmt ", 4);
    int32_t sub_chunk_size = 16;
    output.write(reinterpret_cast<char*>(&sub_chunk_size), sizeof(sub_chunk_size));
    short audio_format = 1;
    output.write(reinterpret_cast<char*>(&audio_format), sizeof(audio_format));
    short num_channels = 1;
    output.write(reinterpret_cast<char*>(&num_channels), sizeof(num_channels));
    int32_t sample_rate = WHISPER_SAMPLE_RATE;
    output.write(reinterpret_cast<char*>(&sample_rate), sizeof(sample_rate));
    int32_t byte_rate = WHISPER_SAMPLE_RATE * 2;
    output.write(reinterpret_cast<char*>(&byte_rate), sizeof(byte_rate));
    short block_align = 2;
    output.write(reinterpret_cast<char*>(&block_align), sizeof(block_align));
    short bits_per_sample = 16;
    output.write(reinterpret_cast<char*>(&bits_per_sample), sizeof(bits_per_sample));
    output.write("data", 4);
    int32_t sub_chunk2_size = static_cast<int32_t>(data.size());
    output.write(reinterpret_cast<char*>(&sub_chunk2_size), sizeof(sub_chunk2_size));
    output.write(reinterpret_cast<const char*>(data.data()), data.size());

    output.close();

    RNWHISPER_LOG_INFO("Saved audio file: %s\n", file.c_str());
}

void save_wav_file_incremental(const std::string& file, const std::vector<uint8_t>& data, bool append) {
    std::ofstream output;

    if (append) {
        output.open(file, std::ios::binary | std::ios::app);
        if (!output.is_open()) {
            RNWHISPER_LOG_ERROR("Failed to open file for appending: %s\n", file.c_str());
            return;
        }
    } else {
        output.open(file, std::ios::binary);
        if (!output.is_open()) {
            RNWHISPER_LOG_ERROR("Failed to open file for writing: %s\n", file.c_str());
            return;
        }
        // Write placeholder header (44 bytes)
        std::vector<uint8_t> header(44, 0);
        output.write(reinterpret_cast<const char*>(header.data()), header.size());
    }

    // Write audio data
    output.write(reinterpret_cast<const char*>(data.data()), data.size());
    output.close();
}

void finalize_wav_file(const std::string& file, int32_t dataSize) {
    std::fstream output(file, std::ios::binary | std::ios::in | std::ios::out);
    if (!output.is_open()) {
        RNWHISPER_LOG_ERROR("Failed to open file for updating: %s\n", file.c_str());
        return;
    }

    // Write WAV header with correct sizes
    output.seekp(0, std::ios::beg);
    // RIFF header
    output.write("RIFF", 4);
    int32_t chunk_size = 36 + dataSize;
    output.write(reinterpret_cast<char*>(&chunk_size), 4);
    output.write("WAVE", 4);
    // fmt subchunk
    output.write("fmt ", 4);
    int32_t sub_chunk_size = 16;
    output.write(reinterpret_cast<char*>(&sub_chunk_size), 4);
    short audio_format = 1;
    output.write(reinterpret_cast<char*>(&audio_format), 2);
    short num_channels = 1;
    output.write(reinterpret_cast<char*>(&num_channels), 2);
    int32_t sample_rate = WHISPER_SAMPLE_RATE;
    output.write(reinterpret_cast<char*>(&sample_rate), 4);
    int32_t byte_rate = WHISPER_SAMPLE_RATE * 2;
    output.write(reinterpret_cast<char*>(&byte_rate), 4);
    short block_align = 2;
    output.write(reinterpret_cast<char*>(&block_align), 2);
    short bits_per_sample = 16;
    output.write(reinterpret_cast<char*>(&bits_per_sample), 2);
    // data subchunk
    output.write("data", 4);
    output.write(reinterpret_cast<char*>(&dataSize), 4);

    output.close();
}

} // namespace rnaudioutils
