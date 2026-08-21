package audio

import "core:strings"

foreign import libaudio_capture {
	"libaudio_capture.a",
	"system:rnnoise",
	"system:m",
	"system:pthread",
}

Denoise_State :: struct {}

foreign libaudio_capture {
	audio_capture_init :: proc(sample_rate: u32) -> b32 ---
	audio_capture_shutdown :: proc() ---
	audio_capture_get_latest :: proc(dest: [^]f32, n: i32) ---
	audio_read_window :: proc(out: [^]f32, num_samples: i32) -> i32 ---

	denoise_init :: proc() -> ^Denoise_State ---
	denoise_process_frame :: proc(st: ^Denoise_State, input: [^]f32, speech: [^]f32, noise_residual: [^]f32) -> i32 ---
	denoise_destroy :: proc(st: ^Denoise_State) ---

	init_demuxer :: proc(model_path: cstring) -> rawptr ---
	process_separation :: proc(handle: rawptr, raw: [^]f32, vocals: [^]f32, bgm: [^]f32, noise: [^]f32, num_samples: i32) -> i32 ---
	free_demuxer :: proc(handle: rawptr) ---
}

Demuxer_State :: rawptr

demuxer_create :: proc(model_path: string = "models/2stem_separator_fp32.onnx") -> Demuxer_State {
	c_path := strings.clone_to_cstring(model_path, context.temp_allocator)
	return init_demuxer(c_path)
}

demuxer_process :: proc(handle: Demuxer_State, raw: []f32, vocals: []f32, bgm: []f32, noise: []f32 = nil) -> bool {
	if handle == nil || len(raw) == 0 || len(vocals) < len(raw) || len(bgm) < len(raw) {
		return false
	}
	n := i32(len(raw))
	noise_ptr: [^]f32 = nil
	if noise != nil && len(noise) >= len(raw) {
		noise_ptr = raw_data(noise)
	}
	res := process_separation(handle, raw_data(raw), raw_data(vocals), raw_data(bgm), noise_ptr, n)
	return res == 1
}

demuxer_free :: proc(handle: Demuxer_State) {
	if handle != nil {
		free_demuxer(handle)
	}
}

RNNOISE_FRAME_SIZE :: 480

init :: proc(sample_rate: u32 = 44100) -> bool {
	return bool(audio_capture_init(sample_rate))
}

shutdown :: proc() {
	audio_capture_shutdown()
}

get_latest_samples :: proc(dest: []f32) {
	audio_read_window(raw_data(dest), i32(len(dest)))
}

denoise_create :: proc() -> ^Denoise_State {
	return denoise_init()
}

denoise_free :: proc(st: ^Denoise_State) {
	denoise_destroy(st)
}

// Separates 480 input samples into speech and noise residual (Noise = Raw - Clean)
process_frame :: proc(st: ^Denoise_State, input: []f32, speech: []f32, noise_residual: []f32) -> bool {
	if len(input) < RNNOISE_FRAME_SIZE || len(speech) < RNNOISE_FRAME_SIZE || len(noise_residual) < RNNOISE_FRAME_SIZE {
		return false
	}
	res := denoise_process_frame(st, raw_data(input), raw_data(speech), raw_data(noise_residual))
	return res == 1
}
