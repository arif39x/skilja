package dsp

import "core:math"

hann_window_init :: proc(window: []f32) {
	n := len(window)
	if n <= 1 do return
	for i in 0..<n {
		window[i] = 0.5 * (1.0 - math.cos(2.0 * math.PI * f32(i) / f32(n - 1)))
	}
}
apply_window :: proc(input: []f32, window: []f32, output: []f32) {
	n := len(input)
	for i in 0..<n {
		output[i] = input[i] * window[i]
	}
}
