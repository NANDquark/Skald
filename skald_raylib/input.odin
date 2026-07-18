package skald_raylib

import "core:unicode/utf8"
import rl "vendor:raylib"
import skald "../skald"

key_pairs :: [?]struct {
	rl_key:    rl.KeyboardKey,
	skald_key: skald.Key,
} {
	{.BACKSPACE, .Backspace},
	{.DELETE, .Delete},
	{.LEFT, .Left},
	{.RIGHT, .Right},
	{.UP, .Up},
	{.DOWN, .Down},
	{.HOME, .Home},
	{.END, .End},
	{.PAGE_UP, .Page_Up},
	{.PAGE_DOWN, .Page_Down},
	{.ENTER, .Enter},
	{.TAB, .Tab},
	{.ESCAPE, .Escape},
	{.SPACE, .Space},
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
	{.ZERO, .N0},
	{.ONE, .N1},
	{.TWO, .N2},
	{.THREE, .N3},
	{.FOUR, .N4},
	{.FIVE, .N5},
	{.SIX, .N6},
	{.SEVEN, .N7},
	{.EIGHT, .N8},
	{.NINE, .N9},
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
	{.MINUS, .Minus},
	{.EQUAL, .Equals},
	{.LEFT_BRACKET, .Left_Bracket},
	{.RIGHT_BRACKET, .Right_Bracket},
	{.SEMICOLON, .Semicolon},
	{.APOSTROPHE, .Apostrophe},
	{.COMMA, .Comma},
	{.PERIOD, .Period},
	{.SLASH, .Slash},
	{.BACKSLASH, .Backslash},
	{.GRAVE, .Grave},
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
	mouse := rl.GetMousePosition()
	delta := rl.GetMouseDelta()

	s.input = skald.Input {
		mouse_pos            = {mouse.x, mouse.y},
		mouse_delta          = {delta.x, delta.y},
		mouse_physical_moved = delta.x != 0 || delta.y != 0,
		scroll               = rl.GetMouseWheelMoveV(),
	}

	s.input.mouse_buttons[.Left] = rl.IsMouseButtonDown(.LEFT)
	s.input.mouse_pressed[.Left] = rl.IsMouseButtonPressed(.LEFT)
	s.input.mouse_released[.Left] = rl.IsMouseButtonReleased(.LEFT)
	s.input.mouse_buttons[.Middle] = rl.IsMouseButtonDown(.MIDDLE)
	s.input.mouse_pressed[.Middle] = rl.IsMouseButtonPressed(.MIDDLE)
	s.input.mouse_released[.Middle] = rl.IsMouseButtonReleased(.MIDDLE)
	s.input.mouse_buttons[.Right] = rl.IsMouseButtonDown(.RIGHT)
	s.input.mouse_pressed[.Right] = rl.IsMouseButtonPressed(.RIGHT)
	s.input.mouse_released[.Right] = rl.IsMouseButtonReleased(.RIGHT)

	s.input.keys_down = keys_down_from_raylib()
	s.input.keys_pressed = keys_pressed_from_raylib()
	s.input.keys_released = keys_released_from_raylib()
	s.input.modifiers = modifiers_from_raylib()

	text_bytes := make([dynamic]u8, context.temp_allocator)
	for {
		ch := rl.GetCharPressed()
		if ch == 0 {break}
		if utf8.valid_rune(ch) {
			buf, n := utf8.encode_rune(ch)
			append(&text_bytes, ..buf[:n])
		}
	}
	if len(text_bytes) > 0 {
		s.input.text = string(text_bytes[:])
	}
}

keys_down_from_raylib :: proc() -> skald.Keys {
	out: skald.Keys
	for p in key_pairs {
		if rl.IsKeyDown(p.rl_key) {out += {p.skald_key}}
	}
	return out
}

keys_pressed_from_raylib :: proc() -> skald.Keys {
	out: skald.Keys
	for p in key_pairs {
		if rl.IsKeyPressed(p.rl_key) {out += {p.skald_key}}
	}
	return out
}

keys_released_from_raylib :: proc() -> skald.Keys {
	out: skald.Keys
	for p in key_pairs {
		if rl.IsKeyReleased(p.rl_key) {out += {p.skald_key}}
	}
	return out
}

modifiers_from_raylib :: proc() -> skald.Modifiers {
	out: skald.Modifiers
	if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) {out += {.Shift}}
	if rl.IsKeyDown(.LEFT_CONTROL) || rl.IsKeyDown(.RIGHT_CONTROL) {out += {.Ctrl}}
	if rl.IsKeyDown(.LEFT_ALT) || rl.IsKeyDown(.RIGHT_ALT) {out += {.Alt}}
	if rl.IsKeyDown(.LEFT_SUPER) || rl.IsKeyDown(.RIGHT_SUPER) {out += {.Super}}
	return out
}
