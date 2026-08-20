package tui

import "core:fmt"
import "core:math"
import "core:strings"
import "core:sys/linux"
import "../physics"

TIOCGWINSZ :: 0x5413

Winsize :: struct {
    ws_row:    u16,
    ws_col:    u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
}

Terminal_Size :: struct {
    width:  int,
    height: int,
}

get_terminal_size :: proc() -> Terminal_Size {
    ws: Winsize
    res := linux.ioctl(linux.Fd(1), TIOCGWINSZ, uintptr(&ws))
    if transmute(int)res >= 0 {
        return Terminal_Size{width = int(ws.ws_col), height = int(ws.ws_row)}
    }
    return Terminal_Size{width = 80, height = 24}
}

enter_alt_screen :: proc() {
    fmt.print("\x1b[?1049h\x1b[?25l\x1b[2J")
}

exit_alt_screen :: proc() {
    fmt.print("\x1b[?25h\x1b[?1049l")
}

clear_screen :: proc() {
    fmt.print("\x1b[2J")
}

get_waveform_color :: proc(dist_from_center: f32) -> (r, g, b: int) {
    d := clamp(dist_from_center, 0.0, 1.0)

    if d < 0.12 {
        return 245, 255, 255
    } else if d < 0.35 {
        t := (d - 0.12) / 0.23
        r = int(120.0 * (1.0 - t))
        g = int(220.0 + (150.0 - 220.0) * t)
        b = 255
    } else if d < 0.70 {
        t := (d - 0.35) / 0.35
        r = 0
        g = int(150.0 * (1.0 - t))
        b = int(255.0 + (180.0 - 255.0) * t)
    } else {
        t := (d - 0.70) / 0.30
        r = 0
        g = 0
        b = int(180.0 * (1.0 - t) + 60.0)
    }
    return
}

render_frame :: proc(bars: []physics.Bar_State, width, height: int, builder: ^strings.Builder) {
    strings.builder_reset(builder)
    strings.write_string(builder, "\x1b[H")

    num_bars := len(bars)
    if num_bars == 0 || width <= 0 || height <= 0 do return

    mid_y := f32(height) / 2.0
    half_h := mid_y

    for y := height - 1; y >= 0; y -= 1 {
        dist_y := math.abs(f32(y) - mid_y + 0.5) / half_h

        r, g, b := get_waveform_color(dist_y)
        color_seq := fmt.tprintf("\x1b[38;2;%d;%d;%dm", r, g, b)
        strings.write_string(builder, color_seq)

        for x in 0..<width {
            nx := (f32(x) / f32(width)) * 2.0 - 1.0
            envelope := 1.0 - math.pow(math.abs(nx), 1.25)
            envelope = clamp(envelope, 0.05, 1.0)

            bar_idx := int((f32(x) / f32(width)) * f32(num_bars))
            if bar_idx >= num_bars do bar_idx = num_bars - 1

            bar_amp := clamp(bars[bar_idx].value * envelope, 0.0, 1.0)
            if bar_amp >= dist_y {
                strings.write_string(builder, "│")
            } else if bar_amp >= dist_y - (0.4 / half_h) {
                strings.write_string(builder, "·")
            } else {
                strings.write_string(builder, " ")
            }
        }
        strings.write_string(builder, "\n")
    }

    strings.write_string(builder, "\x1b[0m")
    fmt.print(strings.to_string(builder^))
}
