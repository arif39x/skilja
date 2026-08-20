package audio

foreign import libaudio_capture "libaudio_capture.a"

foreign libaudio_capture {
	audio_capture_init :: proc(sample_rate: u32) -> b32 ---
	audio_capture_shutdown :: proc() ---
	audio_capture_get_latest :: proc(dest: [^]f32, n: i32) ---
	audio_read_window :: proc(out: [^]f32, num_samples: i32) -> i32 ---
}

init :: proc(sample_rate: u32 = 44100) -> bool {
	return bool(audio_capture_init(sample_rate))
}

shutdown :: proc() {
	audio_capture_shutdown()
}

get_latest_samples :: proc(dest: []f32) {
	audio_read_window(raw_data(dest), i32(len(dest)))
}
