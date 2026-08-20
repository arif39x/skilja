#define MINIAUDIO_IMPLEMENTATION
#include "/usr/lib/odin/vendor/miniaudio/src/miniaudio.h"
#include <pthread.h>
#include <string.h>

#define BUFFER_SIZE 16384

static float g_buffer[BUFFER_SIZE];
static int g_write_pos = 0;
static ma_device g_device;
static ma_context g_context;
static int g_initialized = 0;

void audio_capture_callback(ma_device* pDevice, void* pOutput, const void* pInput, ma_uint32 frameCount) {
    if (pInput == NULL) return;
    const float* samples = (const float*)pInput;

    int write_pos = __atomic_load_n(&g_write_pos, __ATOMIC_RELAXED);
    for (ma_uint32 i = 0; i < frameCount; ++i) {
        g_buffer[write_pos] = samples[i];
        write_pos = (write_pos + 1) % BUFFER_SIZE;
    }
    __atomic_store_n(&g_write_pos, write_pos, __ATOMIC_RELEASE);
}

/* miniaudio's PulseAudio backend does not support ma_device_type_loopback, so we
   stay on ma_device_type_capture and explicitly target the default sink's monitor
   source, which carries whatever the system is currently playing. */
static const ma_device_id* find_loopback_source_id(ma_context* pContext) {
    ma_device_info* pCaptureInfos = NULL;
    ma_uint32 captureCount = 0;

    if (ma_context_get_devices(pContext, NULL, NULL, &pCaptureInfos, &captureCount) != MA_SUCCESS) {
        return NULL;
    }

    for (ma_uint32 i = 0; i < captureCount; ++i) {
        if (strstr(pCaptureInfos[i].id.pulse, ".monitor") != NULL) {
            return &pCaptureInfos[i].id;
        }
    }
    return NULL;
}

int audio_capture_init(unsigned int sample_rate) {
    if (ma_context_init(NULL, 0, NULL, &g_context) != MA_SUCCESS) {
        return 0;
    }

    ma_device_config deviceConfig;
    deviceConfig = ma_device_config_init(ma_device_type_capture);
    deviceConfig.capture.format   = ma_format_f32;
    deviceConfig.capture.channels = 1;
    deviceConfig.sampleRate       = sample_rate;
    deviceConfig.dataCallback     = audio_capture_callback;
    deviceConfig.pUserData        = NULL;

    const ma_device_id* pMonitorID = find_loopback_source_id(&g_context);
    if (pMonitorID != NULL) {
        deviceConfig.capture.pDeviceID = pMonitorID;
        fprintf(stderr, "skilja: capturing system audio (monitor source)\n");
    } else {
        fprintf(stderr, "skilja: warning: no monitor source found, falling back to default input (microphone)\n");
    }

    if (ma_device_init(&g_context, &deviceConfig, &g_device) != MA_SUCCESS) {
        ma_context_uninit(&g_context);
        return 0;
    }

    if (ma_device_start(&g_device) != MA_SUCCESS) {
        ma_device_uninit(&g_device);
        ma_context_uninit(&g_context);
        return 0;
    }

    g_initialized = 1;
    return 1;
}

void audio_capture_shutdown() {
    if (g_initialized) {
        ma_device_uninit(&g_device);
        ma_context_uninit(&g_context);
        g_initialized = 0;
    }
}

int audio_read_window(float* out, int num_samples) {
    if (num_samples > BUFFER_SIZE) num_samples = BUFFER_SIZE;
    int write_pos = __atomic_load_n(&g_write_pos, __ATOMIC_ACQUIRE);
    int start_pos = (write_pos - num_samples + BUFFER_SIZE) % BUFFER_SIZE;
    for (int i = 0; i < num_samples; ++i) {
        out[i] = g_buffer[(start_pos + i) % BUFFER_SIZE];
    }
    return 1;
}

void audio_capture_get_latest(float* dest, int n) {
    audio_read_window(dest, n);
}
