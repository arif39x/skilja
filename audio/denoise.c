#include "denoise.h"
#include <rnnoise.h>
#include <stdlib.h>
#include <string.h>

DenoiseState* denoise_init(void) {
    return rnnoise_create(NULL);
}

int denoise_process_frame(DenoiseState* st, const float* input, float* speech, float* noise_residual) {
    if (!st || !input || !speech || !noise_residual) {
        return 0;
    }

    /* RNNoise expects 480 float samples scaled roughly to standard 16-bit range (-32768 to 32767) 
       or float [-1.0, 1.0] scaled up by 32767.0f */
    float in_buf[RNNOISE_FRAME_SIZE];
    float out_buf[RNNOISE_FRAME_SIZE];

    for (int i = 0; i < RNNOISE_FRAME_SIZE; ++i) {
        in_buf[i] = input[i] * 32767.0f;
    }

    rnnoise_process_frame(st, out_buf, in_buf);

    for (int i = 0; i < RNNOISE_FRAME_SIZE; ++i) {
        speech[i] = out_buf[i] / 32767.0f;
        noise_residual[i] = input[i] - speech[i];
    }

    return 1;
}

void denoise_destroy(DenoiseState* st) {
    if (st) {
        rnnoise_destroy(st);
    }
}
