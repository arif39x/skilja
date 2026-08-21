#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include "onnxruntime_c_api.h"

#define INPUT_SAMPLES 2048
#define NUM_STEMS 2

#define CHECK_ORT_STATUS(api, status) \
    do { \
        OrtStatus* s = (status); \
        if (s != NULL) { \
            const char* msg = (api)->GetErrorMessage(s); \
            fprintf(stderr, "ONNX Runtime Error: %s\n", msg); \
            (api)->ReleaseStatus(s); \
            return 1; \
        } \
    } while (0)

int main(int argc, char** argv) {
    const char* model_path = "models/2stem_separator_fp32.onnx";
    if (argc > 1) {
        model_path = argv[1];
    }
    printf(" ONNX Runtime C API Verification\n");
    printf("Testing model: %s\n", model_path);

    const OrtApi* g_ort = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (!g_ort) {
        fprintf(stderr, "Failed to get ONNX Runtime API.\n");
        return 1;
    }

    OrtEnv* env = NULL;
    CHECK_ORT_STATUS(g_ort, g_ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "onnx_verify", &env));

    OrtSessionOptions* session_options = NULL;
    CHECK_ORT_STATUS(g_ort, g_ort->CreateSessionOptions(&session_options));
    CHECK_ORT_STATUS(g_ort, g_ort->SetIntraOpNumThreads(session_options, 1));
    CHECK_ORT_STATUS(g_ort, g_ort->SetSessionGraphOptimizationLevel(session_options, ORT_ENABLE_ALL));

    OrtSession* session = NULL;
    printf(" Model loading into session...\n");
    CHECK_ORT_STATUS(g_ort, g_ort->CreateSession(env, model_path, session_options, &session));
    printf("      -> Session successfully created.\n");

    OrtAllocator* allocator = NULL;
    CHECK_ORT_STATUS(g_ort, g_ort->GetAllocatorWithDefaultOptions(&allocator));
    float input_buffer[INPUT_SAMPLES];
    for (int i = 0; i < INPUT_SAMPLES; i++) {
        float t = (float)i / 44100.0f;
        input_buffer[i] = 0.5f * sinf(2.0f * (float)M_PI * 440.0f * t) + 0.1f * ((float)rand() / (float)RAND_MAX - 0.5f);
    }

    int64_t input_shape[3] = {1, 1, INPUT_SAMPLES};
    size_t input_shape_len = 3;
    size_t input_bytes = sizeof(float) * INPUT_SAMPLES;

    OrtMemoryInfo* memory_info = NULL;
    CHECK_ORT_STATUS(g_ort, g_ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &memory_info));

    OrtValue* input_tensor = NULL;
    CHECK_ORT_STATUS(g_ort, g_ort->CreateTensorWithDataAsOrtValue(
        memory_info,
        input_buffer,
        input_bytes,
        input_shape,
        input_shape_len,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &input_tensor
    ));

    const char* input_names[] = {"input_audio"};
    const char* output_names[] = {"stems_output"};

    OrtValue* output_tensor = NULL;

    printf("Performing warm-up inference...\n");
    CHECK_ORT_STATUS(g_ort, g_ort->Run(
        session,
        NULL,
        input_names,
        (const OrtValue* const*)&input_tensor,
        1,
        output_names,
        1,
        &output_tensor
    ));
    printf("      -> Warm-up inference complete.\n");

    int benchmark_runs = 100;
    printf("Benchmarking %d runs...\n", benchmark_runs);
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);

    for (int i = 0; i < benchmark_runs; i++) {
        if (output_tensor) {
            g_ort->ReleaseValue(output_tensor);
            output_tensor = NULL;
        }
        CHECK_ORT_STATUS(g_ort, g_ort->Run(
            session,
            NULL,
            input_names,
            (const OrtValue* const*)&input_tensor,
            1,
            output_names,
            1,
            &output_tensor
        ));
    }

    clock_gettime(CLOCK_MONOTONIC, &end);
    double elapsed_ms = (end.tv_sec - start.tv_sec) * 1000.0 + (end.tv_nsec - start.tv_nsec) / 1000000.0;
    double avg_latency = elapsed_ms / benchmark_runs;
    printf("      -> Total Time: %.2f ms, Avg Latency: %.3f ms / frame\n", elapsed_ms, avg_latency);

    printf("Validating output tensor dimensions and contents...\n");
    OrtTensorTypeAndShapeInfo* shape_info = NULL;
    CHECK_ORT_STATUS(g_ort, g_ort->GetTensorTypeAndShape(output_tensor, &shape_info));

    size_t dim_count = 0;
    CHECK_ORT_STATUS(g_ort, g_ort->GetDimensionsCount(shape_info, &dim_count));
    int64_t dims[3];
    CHECK_ORT_STATUS(g_ort, g_ort->GetDimensions(shape_info, dims, dim_count));

    printf("      -> Output dimensions: [%ld, %ld, %ld]\n", (long)dims[0], (long)dims[1], (long)dims[2]);
    if (dim_count != 3 || dims[0] != 1 || dims[1] != 2 || dims[2] != INPUT_SAMPLES) {
        fprintf(stderr, "Error: Unexpected output shape!\n");
        return 1;
    }

    float* output_data = NULL;
    CHECK_ORT_STATUS(g_ort, g_ort->GetTensorMutableData(output_tensor, (void**)&output_data));
    float vocal_rms = 0.0f;
    float bgm_rms = 0.0f;
    float* vocal_data = output_data; 
    float* bgm_data = output_data + INPUT_SAMPLES; 

    int has_nan = 0;
    for (int i = 0; i < INPUT_SAMPLES; i++) {
        if (isnan(vocal_data[i]) || isnan(bgm_data[i]) || isinf(vocal_data[i]) || isinf(bgm_data[i])) {
            has_nan = 1;
            break;
        }
        vocal_rms += vocal_data[i] * vocal_data[i];
        bgm_rms += bgm_data[i] * bgm_data[i];
    }
    vocal_rms = sqrtf(vocal_rms / INPUT_SAMPLES);
    bgm_rms = sqrtf(bgm_rms / INPUT_SAMPLES);

    if (has_nan) {
        fprintf(stderr, "Error: NaN or Inf detected in output!\n");
        return 1;
    }

    printf("      -> Vocal Stem RMS: %.4f\n", vocal_rms);
    printf("      -> BGM Stem RMS:   %.4f\n", bgm_rms);

    printf("[5/5] Cleanup resources...\n");
    g_ort->ReleaseTensorTypeAndShapeInfo(shape_info);
    g_ort->ReleaseMemoryInfo(memory_info);
    g_ort->ReleaseValue(input_tensor);
    g_ort->ReleaseValue(output_tensor);
    g_ort->ReleaseSession(session);
    g_ort->ReleaseSessionOptions(session_options);
    g_ort->ReleaseEnv(env);

    printf("ONNX C API Verification PASSED!\n");
    return 0;
}
