package dsp

import "core:math"

calculate_bins :: proc(
	num_bars: int,
	fft_size: int,
	sample_rate: f32,
	min_freq: f32,
	max_freq: f32,
	bin_lows: []int,
	bin_highs: []int,
) {
	fft_half := fft_size / 2
	for i in 0..<num_bars {
		f_low  := min_freq * math.pow(max_freq / min_freq, f32(i) / f32(num_bars))
		f_high := min_freq * math.pow(max_freq / min_freq, f32(i + 1) / f32(num_bars))
		low_idx  := int(f_low * f32(fft_size) / sample_rate)
		high_idx := int(f_high * f32(fft_size) / sample_rate)
		if low_idx < 1 do low_idx = 1
		if high_idx <= low_idx do high_idx = low_idx + 1
		if low_idx >= fft_half do low_idx = fft_half - 1
		if high_idx > fft_half do high_idx = fft_half
		bin_lows[i]  = low_idx
		bin_highs[i] = high_idx
	}
}
bin_fft_data :: proc(
	fft_data: []complex64,
	bin_lows: []int,
	bin_highs: []int,
	bars: []f32,
) {
	num_bars := len(bars)
	for i in 0..<num_bars {
		low := bin_lows[i]
		high := bin_highs[i]
		sum: f32 = 0.0
		for k in low..<high {
			r := real(fft_data[k])
			im := imag(fft_data[k])
			mag := math.sqrt(r*r + im*im)
			sum += mag
		}
		avg := sum / f32(high - low)
		boost := 1.0 + 3.0 * (f32(i) / f32(num_bars))
		bars[i] = avg * boost
	}
}
