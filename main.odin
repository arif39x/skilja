package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "core:sys/posix"
import "core:time"
import "./audio"
import "./dsp"
import "./physics"
import "./tui"

FFT_SIZE :: 2048

main :: proc() {
	if !audio.init(44100) {
		fmt.eprintln("Failed to initialize audio capture.")
		os.exit(1)
	}
	defer audio.shutdown()

	tui.enter_alt_screen()
	defer tui.exit_alt_screen()

	orig_termios: posix.termios
	posix.tcgetattr(posix.STDIN_FILENO, &orig_termios)
	
	raw := orig_termios
	raw.c_lflag -= { .ECHO, .ICANON, .ISIG, .IEXTEN }
	raw.c_iflag -= { .IXON, .ICRNL }
	raw.c_cc[.VMIN] = 0
	raw.c_cc[.VTIME] = 0
	posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &raw)
	
	defer posix.tcsetattr(posix.STDIN_FILENO, .TCSAFLUSH, &orig_termios)
	window := make([]f32, FFT_SIZE)
	defer delete(window)
	dsp.hann_window_init(window)

	samples := make([]f32, FFT_SIZE)
	defer delete(samples)

	windowed := make([]f32, FFT_SIZE)
	defer delete(windowed)

	fft_data := make([]complex64, FFT_SIZE)
	defer delete(fft_data)

	ts := tui.get_terminal_size()
	num_bars := ts.width
	if num_bars <= 0 do num_bars = 40
	bars_state := make([]physics.Bar_State, num_bars)
	defer delete(bars_state)

	physics_config := physics.Physics_Config{
		gravity          = 0.03,
		peak_gravity     = 0.008,
		peak_hold_frames = 15,
		rise_smoothing   = 0.7,
		fall_smoothing   = 0.15,
	}

	bin_lows := make([]int, num_bars)
	bin_highs := make([]int, num_bars)
	defer delete(bin_lows)
	defer delete(bin_highs)

	dsp.calculate_bins(num_bars, FFT_SIZE, 44100.0, 20.0, 20000.0, bin_lows, bin_highs)

	raw_bars := make([]f32, num_bars)
	defer delete(raw_bars)

	normalized_bars := make([]f32, num_bars)
	defer delete(normalized_bars)

	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	max_val_seen: f32 = 0.05

	last_width, last_height := ts.width, ts.height

	for {
		ch: u8 = 0
		bytes_read := posix.read(posix.STDIN_FILENO, &ch, 1)
		if bytes_read > 0 {
			if ch == 'q' || ch == 'Q' || ch == 27 { // 'q', 'Q', or Esc
				break
			}
		}

		ts = tui.get_terminal_size()
		if ts.width != last_width || ts.height != last_height {
			tui.clear_screen()
			last_width = ts.width
			last_height = ts.height
			
			num_bars = ts.width
			if num_bars <= 0 do num_bars = 40
			
			delete(bars_state)
			bars_state = make([]physics.Bar_State, num_bars)
			
			delete(bin_lows)
			delete(bin_highs)
			bin_lows = make([]int, num_bars)
			bin_highs = make([]int, num_bars)
			dsp.calculate_bins(num_bars, FFT_SIZE, 44100.0, 20.0, 20000.0, bin_lows, bin_highs)
			
			delete(raw_bars)
			raw_bars = make([]f32, num_bars)
			
			delete(normalized_bars)
			normalized_bars = make([]f32, num_bars)
		}
		audio.get_latest_samples(samples)
		dsp.apply_window(samples, window, windowed)

		for i in 0..<FFT_SIZE {
			fft_data[i] = complex(windowed[i], f32(0.0))
		}

		dsp.fft(fft_data)

		dsp.bin_fft_data(fft_data, bin_lows, bin_highs, raw_bars)
		
		max_val_seen = math.max(max_val_seen * 0.995, 0.05)
		for val in raw_bars {
			if val > max_val_seen {
				max_val_seen = val
			}
		}

		for i in 0..<num_bars {
			normalized_bars[i] = raw_bars[i] / max_val_seen
		}

		physics.update_physics(bars_state, normalized_bars, physics_config)

		tui.render_frame(bars_state, ts.width, ts.height, &builder)

		time.sleep(16 * time.Millisecond)
	}
}
