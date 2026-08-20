package audio

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
