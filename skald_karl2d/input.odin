package skald_karl2d

import k2 "gui:karl2d"
import skald "gui:skald"

input_snapshot :: proc(state: rawptr) -> skald.Input {
	s := (^Backend_State)(state)
	return s.input
}

input_capture :: proc(state: rawptr) -> skald.Input_Capture {
	s := (^Backend_State)(state)
	return s.capture
}

translate_input :: proc(s: ^Backend_State) {
	mouse := k2.get_mouse_position()
	delta := k2.get_mouse_delta()

	s.input = skald.Input {
		mouse_pos            = {mouse.x, mouse.y},
		mouse_delta          = {delta.x, delta.y},
		mouse_physical_moved = delta.x != 0 || delta.y != 0,
		scroll               = {0, k2.get_mouse_wheel_delta()},
	}

	s.input.mouse_buttons[.Left] = k2.mouse_button_is_held(.Left)
	s.input.mouse_pressed[.Left] = k2.mouse_button_went_down(.Left)
	s.input.mouse_released[.Left] = k2.mouse_button_went_up(.Left)
	s.input.mouse_buttons[.Middle] = k2.mouse_button_is_held(.Middle)
	s.input.mouse_pressed[.Middle] = k2.mouse_button_went_down(.Middle)
	s.input.mouse_released[.Middle] = k2.mouse_button_went_up(.Middle)
	s.input.mouse_buttons[.Right] = k2.mouse_button_is_held(.Right)
	s.input.mouse_pressed[.Right] = k2.mouse_button_went_down(.Right)
	s.input.mouse_released[.Right] = k2.mouse_button_went_up(.Right)

	s.input.keys_down = keys_down_from_karl2d()
	s.input.keys_pressed = keys_pressed_from_karl2d()
	s.input.keys_released = keys_released_from_karl2d()
	s.input.modifiers = modifiers_from_karl2d()

	s.capture = skald.input_capture_from_frame(s.input, s.frame_state)
}

keys_down_from_karl2d :: proc() -> skald.Keys {
	return {}
}

keys_pressed_from_karl2d :: proc() -> skald.Keys {
	return {}
}

keys_released_from_karl2d :: proc() -> skald.Keys {
	return {}
}

modifiers_from_karl2d :: proc() -> skald.Modifiers {
	return {}
}
