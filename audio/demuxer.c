#include "demuxer.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "onnxruntime_c_api.h"

struct DemuxerState {
    const OrtApi* ort;
    OrtEnv* env;
    OrtSessionOptions* session_options;
    OrtSession* session;
    OrtMemoryInfo* memory_info;
};

DemuxerState* init_demuxer(const char* model_path) {
    if (!model_path) {
        model_path = "models/2stem_separator_fp32.onnx";
    }

    DemuxerState* handle = (DemuxerState*)calloc(1, sizeof(DemuxerState));
    if (!handle) return NULL;

    handle->ort = OrtGetApiBase()->GetApi(ORT_API_VERSION);
    if (!handle->ort) {
        free(handle);
        return NULL;
    }

    if (handle->ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "skilja_demuxer", &handle->env) != NULL) {
        free(handle);
        return NULL;
    }

    if (handle->ort->CreateSessionOptions(&handle->session_options) != NULL) {
        handle->ort->ReleaseEnv(handle->env);
        free(handle);
        return NULL;
    }

    OrtStatus* status = handle->ort->SetIntraOpNumThreads(handle->session_options, 1);
    if (status != NULL) {
        handle->ort->ReleaseStatus(status);
    }
    status = handle->ort->SetSessionGraphOptimizationLevel(handle->session_options, ORT_ENABLE_ALL);
    if (status != NULL) {
        handle->ort->ReleaseStatus(status);
    }

    if (handle->ort->CreateSession(handle->env, model_path, handle->session_options, &handle->session) != NULL) {
        handle->ort->ReleaseSessionOptions(handle->session_options);
        handle->ort->ReleaseEnv(handle->env);
        free(handle);
        return NULL;
    }

    if (handle->ort->CreateCpuMemoryInfo(OrtArenaAllocator, OrtMemTypeDefault, &handle->memory_info) != NULL) {
        handle->ort->ReleaseSession(handle->session);
        handle->ort->ReleaseSessionOptions(handle->session_options);
        handle->ort->ReleaseEnv(handle->env);
        free(handle);
        return NULL;
    }

    return handle;
}

int process_separation(DemuxerState* handle, const float* raw, float* vocals, float* bgm, float* noise, int num_samples) {
    if (!handle || !raw || !vocals || !bgm || num_samples <= 0) {
        return 0;
    }

    int64_t input_shape[3] = {1, 1, (int64_t)num_samples};
    size_t input_bytes = sizeof(float) * num_samples;

    OrtValue* input_tensor = NULL;
    OrtStatus* status = handle->ort->CreateTensorWithDataAsOrtValue(
        handle->memory_info,
        (void*)raw,
        input_bytes,
        input_shape,
        3,
        ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,
        &input_tensor
    );
    if (status != NULL) {
        handle->ort->ReleaseStatus(status);
        return 0;
    }

    const char* input_names[] = {"input_audio"};
    const char* output_names[] = {"stems_output"};
    OrtValue* output_tensor = NULL;

    status = handle->ort->Run(
        handle->session,
        NULL,
        input_names,
        (const OrtValue* const*)&input_tensor,
        1,
        output_names,
        1,
        &output_tensor
    );

    if (status != NULL) {
        handle->ort->ReleaseStatus(status);
        handle->ort->ReleaseValue(input_tensor);
        return 0;
    }

    float* output_data = NULL;
    status = handle->ort->GetTensorMutableData(output_tensor, (void**)&output_data);
    if (status != NULL || !output_data) {
        if (status) handle->ort->ReleaseStatus(status);
        handle->ort->ReleaseValue(output_tensor);
        handle->ort->ReleaseValue(input_tensor);
        return 0;
    }

    // output tensor shape is [1, 2, num_samples]
    float* vocal_src = output_data;
    float* bgm_src = output_data + num_samples;

    for (int i = 0; i < num_samples; i++) {
        vocals[i] = vocal_src[i];
        bgm[i] = bgm_src[i];
        if (noise) {
            noise[i] = raw[i] - vocals[i] - bgm[i];
        }
    }

    handle->ort->ReleaseValue(output_tensor);
    handle->ort->ReleaseValue(input_tensor);
    return 1;
}

void free_demuxer(DemuxerState* handle) {
    if (!handle) return;
    if (handle->ort) {
        if (handle->memory_info) handle->ort->ReleaseMemoryInfo(handle->memory_info);
        if (handle->session) handle->ort->ReleaseSession(handle->session);
        if (handle->session_options) handle->ort->ReleaseSessionOptions(handle->session_options);
        if (handle->env) handle->ort->ReleaseEnv(handle->env);
    }
    free(handle);
}
