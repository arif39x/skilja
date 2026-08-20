#ifndef DENOISE_H
#define DENOISE_H

#define RNNOISE_FRAME_SIZE 480

typedef struct DenoiseState DenoiseState;

#ifdef __cplusplus
extern "C" {
#endif

// Allocates and initializes an RNNoise denoiser context.
DenoiseState* denoise_init(void);

// Processes 480 samples of float32 audio.
// Takes input audio frame (480 samples) and outputs:
//   - speech: isolated denoised speech frame (480 samples)
//   - noise_residual: residual noise frame (480 samples) where Noise = Input - Speech
// Returns 1 on success, 0 on failure.
int denoise_process_frame(DenoiseState* st, const float* input, float* speech, float* noise_residual);

// Frees the denoiser context.
void denoise_destroy(DenoiseState* st);

#ifdef __cplusplus
}
#endif

#endif // DENOISE_H
