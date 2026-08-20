package dsp

import "core:math"

fft :: proc(data: []complex64) {
	n := len(data)
	if n <= 1 do return
	j := 0
	for i in 0..<n {
		if i < j {
			data[i], data[j] = data[j], data[i]
		}
		m := n >> 1
		for m >= 1 && j >= m {
			j -= m
			m >>= 1
		}
		j += m
	}
	for len_stage := 2; len_stage <= n; len_stage <<= 1 {
		half_len := len_stage >> 1
		angle := -2.0 * math.PI / f32(len_stage)
		w_step := complex(math.cos(angle), math.sin(angle))

		for i := 0; i < n; i += len_stage {
			w: complex64 = 1.0
			for k in 0..<half_len {
				u := data[i + k]
				t := w * data[i + k + half_len]
				data[i + k] = u + t
				data[i + k + half_len] = u - t
				w = w * w_step
			}
		}
	}
}
