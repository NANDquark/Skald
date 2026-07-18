package skald_raylib

import "core:c"
import "core:time"
import rl "vendor:raylib"
import skald "../skald"

Backend_State :: struct {
	input:      skald.Input,
	capture:    skald.Input_Capture,
	alpha:      f32,
	clip_stack: [dynamic]skald.Rect,
	fonts:      [dynamic]rl.Font,
	images:     map[string]^Image_Entry,
}

backend_state_init :: proc(s: ^Backend_State) {
	s.alpha = 1
}

backend_state_destroy :: proc(s: ^Backend_State) {
	delete(s.clip_stack)
	s.clip_stack = nil
	for font in s.fonts {
		if rl.IsFontValid(font) {
			rl.UnloadFont(font)
		}
	}
	delete(s.fonts)
	s.fonts = nil
	rl_image_cache_destroy(s)
}

backend :: proc(state: ^Backend_State) -> skald.Backend {
	return skald.Backend {
		state = state,
		capabilities = {},
		frame = skald.Backend_Frame{begin = frame_begin, end = frame_end},
		draw = skald.Backend_Draw {
			rect = draw_rect,
			gradient_rect = draw_gradient_rect,
			shadow = draw_shadow,
			push_clip = push_clip,
			pop_clip = pop_clip,
			set_alpha = set_alpha,
		},
		text = skald.Backend_Text {
			load_font = rl_load_font,
			measure = rl_measure_text,
			wrap = rl_wrap_text,
			ascent = rl_text_ascent,
			draw = rl_draw_text,
			span_font = rl_span_font,
		},
		images = skald.Backend_Images {
			load_path = rl_image_load_path,
			load_bytes = rl_image_load_bytes,
			load_pixels = rl_image_load_pixels,
			update_pixels = rl_image_update_pixels,
			unload = rl_image_unload,
			size = rl_image_size,
			draw = rl_image_draw,
			draw_fit = rl_image_draw_fit,
			draw_region = rl_image_draw_region,
		},
		input = skald.Backend_Input{snapshot = input_snapshot, capture = input_capture},
		window = skald.Backend_Window {
			size = window_size,
			scale = window_scale,
			set_text_input = set_text_input,
		},
		time = skald.Backend_Time{now_ns = now_ns},
	}
}

frame_begin :: proc(state: rawptr, clear: skald.Color) -> bool {
	return true
}

frame_end :: proc(state: rawptr) {}

draw_rect :: proc(state: rawptr, rect: skald.Rect, color: skald.Color, radius: f32) {
	s := (^Backend_State)(state)
	rl.DrawRectangleRec(to_rl_rect(rect), to_rl_color(color, s.alpha))
}

draw_gradient_rect :: proc(
	state: rawptr,
	rect: skald.Rect,
	c_tl, c_tr, c_br, c_bl: skald.Color,
	radius: f32,
) {
	s := (^Backend_State)(state)
	// Raylib has no rounded multi-stop gradient primitive; use the first stop
	// until the backend grows a richer draw path.
	// backend grows a richer draw path.
	rl.DrawRectangleRec(to_rl_rect(rect), to_rl_color(c_tl, s.alpha))
}

draw_shadow :: proc(
	state: rawptr,
	rect: skald.Rect,
	radius, blur: f32,
	color: skald.Color,
	offset: [2]f32,
) {
	if color[3] <= 0 {return}
	s := (^Backend_State)(state)
	shadow_rect := skald.Rect{rect.x + offset.x, rect.y + offset.y, rect.w, rect.h}
	rl.DrawRectangleRec(to_rl_rect(shadow_rect), to_rl_color(color, s.alpha))
}

push_clip :: proc(state: rawptr, rect: skald.Rect) {
	s := (^Backend_State)(state)
	new_rect := rect
	if len(s.clip_stack) > 0 {
		prev := s.clip_stack[len(s.clip_stack) - 1]
		x0 := max(prev.x, rect.x)
		y0 := max(prev.y, rect.y)
		x1 := min(prev.x + prev.w, rect.x + rect.w)
		y1 := min(prev.y + prev.h, rect.y + rect.h)
		new_rect = {x0, y0, max(x1 - x0, 0), max(y1 - y0, 0)}
	}
	append(&s.clip_stack, new_rect)
	rl.BeginScissorMode(c.int(new_rect.x), c.int(new_rect.y), c.int(new_rect.w), c.int(new_rect.h))
}

pop_clip :: proc(state: rawptr) {
	s := (^Backend_State)(state)
	if len(s.clip_stack) == 0 {
		rl.EndScissorMode()
		return
	}

	ordered_remove(&s.clip_stack, len(s.clip_stack) - 1)
	rl.EndScissorMode()
	if len(s.clip_stack) == 0 {
		return
	}
	rect := s.clip_stack[len(s.clip_stack) - 1]
	rl.BeginScissorMode(c.int(rect.x), c.int(rect.y), c.int(rect.w), c.int(rect.h))
}

set_alpha :: proc(state: rawptr, alpha: f32) {
	s := (^Backend_State)(state)
	s.alpha = clamp01(alpha)
}

window_size :: proc(state: rawptr) -> skald.Size {
	return {i32(rl.GetScreenWidth()), i32(rl.GetScreenHeight())}
}

window_scale :: proc(state: rawptr) -> f32 {
	return 1
}

set_text_input :: proc(state: rawptr, on: bool) {
	// Raylib queues text input continuously via GetCharPressed.
}

now_ns :: proc(state: rawptr) -> i64 {
	return time.now()._nsec
}

to_rl_rect :: proc(rect: skald.Rect) -> rl.Rectangle {
	return rl.Rectangle{rect.x, rect.y, rect.w, rect.h}
}

to_rl_color :: proc(color: skald.Color, alpha: f32 = 1) -> rl.Color {
	return rl.Color{
		u8(clamp01(color[0]) * 255 + 0.5),
		u8(clamp01(color[1]) * 255 + 0.5),
		u8(clamp01(color[2]) * 255 + 0.5),
		u8(clamp01(color[3] * alpha) * 255 + 0.5),
	}
}

clamp01 :: proc(v: f32) -> f32 {
	if v < 0 {return 0}
	if v > 1 {return 1}
	return v
}
