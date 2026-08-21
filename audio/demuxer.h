#ifndef DEMUXER_H
#define DEMUXER_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct DemuxerState DemuxerState;

// Initializes the ONNX demuxer session from the given model path
// Returns a handle pointer on success, NULL on failure
DemuxerState* init_demuxer(const char* model_path);

// Processes input audio frame (num_samples floats) and separates stems
// raw -> input audio buffer
// vocals -> destination buffer for isolated vocal stem (num_samples floats)
// bgm -> destination buffer for isolated background music stem (num_samples floats)
// noise -> destination buffer for residual noise stem (num_samples floats)
// Returns 1 on success, 0 on failure
int process_separation(DemuxerState* handle, const float* raw, float* vocals, float* bgm, float* noise, int num_samples);

// Frees demuxer handle and ONNX runtime resources
void free_demuxer(DemuxerState* handle);

#ifdef __cplusplus
}
#endif

#endif // DEMUXER_H
