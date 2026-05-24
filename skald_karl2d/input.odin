package skald_karl2d

import k2 "gui:karl2d"
import skald "gui:skald"

key_pairs :: [?]struct {
	k2_key:    k2.Keyboard_Key,
	skald_key: skald.Key,
} {
	{.Backspace, .Backspace},
	{.Delete, .Delete},
	{.Left, .Left},
	{.Right, .Right},
	{.Up, .Up},
	{.Down, .Down},
	{.Home, .Home},
	{.End, .End},
	{.Page_Up, .Page_Up},
	{.Page_Down, .Page_Down},
	{.Enter, .Enter},
	{.Tab, .Tab},
	{.Escape, .Escape},
	{.Space, .Space},
	{.A, .A},
	{.B, .B},
	{.C, .C},
	{.D, .D},
	{.E, .E},
	{.F, .F},
	{.G, .G},
	{.H, .H},
	{.I, .I},
	{.J, .J},
	{.K, .K},
	{.L, .L},
	{.M, .M},
	{.N, .N},
	{.O, .O},
	{.P, .P},
	{.Q, .Q},
	{.R, .R},
	{.S, .S},
	{.T, .T},
	{.U, .U},
	{.V, .V},
	{.W, .W},
	{.X, .X},
	{.Y, .Y},
	{.Z, .Z},
	{.N0, .N0},
	{.N1, .N1},
	{.N2, .N2},
	{.N3, .N3},
	{.N4, .N4},
	{.N5, .N5},
	{.N6, .N6},
	{.N7, .N7},
	{.N8, .N8},
	{.N9, .N9},
	{.F1, .F1},
	{.F2, .F2},
	{.F3, .F3},
	{.F4, .F4},
	{.F5, .F5},
	{.F6, .F6},
	{.F7, .F7},
	{.F8, .F8},
	{.F9, .F9},
	{.F10, .F10},
	{.F11, .F11},
	{.F12, .F12},
	{.Minus, .Minus},
	{.Equal, .Equals},
	{.Left_Bracket, .Left_Bracket},
	{.Right_Bracket, .Right_Bracket},
	{.Semicolon, .Semicolon},
	{.Apostrophe, .Apostrophe},
	{.Comma, .Comma},
	{.Period, .Period},
	{.Slash, .Slash},
	{.Backslash, .Backslash},
	{.Backtick, .Grave},
}

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
	out: skald.Keys
	for p in key_pairs {
		if k2.key_is_held(p.k2_key) {out += {p.skald_key}}
	}
	return out
}

keys_pressed_from_karl2d :: proc() -> skald.Keys {
	out: skald.Keys
	for p in key_pairs {
		if k2.key_went_down(p.k2_key) {out += {p.skald_key}}
	}
	return out
}

keys_released_from_karl2d :: proc() -> skald.Keys {
	out: skald.Keys
	for p in key_pairs {
		if k2.key_went_up(p.k2_key) {out += {p.skald_key}}
	}
	return out
}

modifiers_from_karl2d :: proc() -> skald.Modifiers {
	out: skald.Modifiers
	mods := k2.get_held_modifiers()
	if .Shift in mods {out += {.Shift}}
	if .Control in mods {out += {.Ctrl}}
	if .Alt in mods {out += {.Alt}}
	if .Super in mods {out += {.Super}}
	return out
}
