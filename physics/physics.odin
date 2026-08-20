package physics

import "core:math"

Bar_State :: struct {
	value:     f32,
	peak:      f32,
	peak_hold: int,
}

Physics_Config :: struct {
	gravity:          f32,
	peak_gravity:     f32,
	peak_hold_frames: int,
	rise_smoothing:   f32,
	fall_smoothing:   f32,
}
update_physics :: proc(
	states: []Bar_State,
	target_values: []f32,
	config: Physics_Config,
) {
	for i in 0..<len(states) {
		target := target_values[i]
		state := &states[i]

		if target > state.value {
			state.value = math.lerp(state.value, target, config.rise_smoothing)
		} else {
			state.value = math.lerp(state.value, target, config.fall_smoothing)
			state.value = math.max(0.0, state.value - config.gravity)
		}

		if state.value < 0.0 do state.value = 0.0
		if state.value > 1.0 do state.value = 1.0

		if state.value >= state.peak {
			state.peak = state.value
			state.peak_hold = config.peak_hold_frames
		} else {
			if state.peak_hold > 0 {
				state.peak_hold -= 1
			} else {
				state.peak = math.max(0.0, state.peak - config.peak_gravity)
			}
		}

		if state.peak > 1.0 do state.peak = 1.0
	}
}
