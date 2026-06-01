package skald_karl2d

import k2 "../karl2d"
import skald "../skald"
import "core:time"

Backend_State :: struct {
	input:      skald.Input,
	capture:    skald.Input_Capture,
	alpha:      f32,
	clip_stack: [dynamic]skald.Rect,
	fonts:      [dynamic]k2.Font,
	images:     map[string]^Image_Entry,
}

backend_state_init :: proc(s: ^Backend_State) {
	s.alpha = 1
}

backend_state_destroy :: proc(s: ^Backend_State) {
	delete(s.clip_stack)
	s.clip_stack = nil
	for font in s.fonts {
		if font != k2.FONT_DEFAULT && font != k2.FONT_NONE {
			k2.destroy_font(font)
		}
	}
	delete(s.fonts)
	s.fonts = nil
	k2_image_cache_destroy(s)
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
			load_font = k2_load_font,
			measure = k2_measure_text,
			wrap = k2_wrap_text,
			ascent = k2_text_ascent,
			draw = k2_draw_text,
			span_font = k2_span_font,
		},
		images = skald.Backend_Images {
			load_path = k2_image_load_path,
			load_bytes = k2_image_load_bytes,
			load_pixels = k2_image_load_pixels,
			update_pixels = k2_image_update_pixels,
			unload = k2_image_unload,
			size = k2_image_size,
			draw = k2_image_draw,
			draw_fit = k2_image_draw_fit,
			draw_region = k2_image_draw_region,
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
	k2.draw_rect(to_k2_rect(rect), to_k2_color(color, s.alpha))
}

draw_gradient_rect :: proc(
	state: rawptr,
	rect: skald.Rect,
	c_tl, c_tr, c_br, c_bl: skald.Color,
	radius: f32,
) {
	s := (^Backend_State)(state)
	// Karl2D has no gradient primitive; use the first stop until the text/image
	// backend grows a richer draw path.
	k2.draw_rect(to_k2_rect(rect), to_k2_color(c_tl, s.alpha))
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
	k2.draw_rect(to_k2_rect(shadow_rect), to_k2_color(color, s.alpha))
}

push_clip :: proc(state: rawptr, rect: skald.Rect) {
	s := (^Backend_State)(state)
	append(&s.clip_stack, rect)
	k2.set_scissor_rect(to_k2_rect(rect))
}

pop_clip :: proc(state: rawptr) {
	s := (^Backend_State)(state)
	if len(s.clip_stack) == 0 {
		k2.set_scissor_rect(nil)
		return
	}

	ordered_remove(&s.clip_stack, len(s.clip_stack) - 1)
	if len(s.clip_stack) == 0 {
		k2.set_scissor_rect(nil)
		return
	}
	k2.set_scissor_rect(to_k2_rect(s.clip_stack[len(s.clip_stack) - 1]))
}

set_alpha :: proc(state: rawptr, alpha: f32) {
	s := (^Backend_State)(state)
	s.alpha = clamp01(alpha)
}

window_size :: proc(state: rawptr) -> skald.Size {
	return {i32(k2.get_screen_width()), i32(k2.get_screen_height())}
}

window_scale :: proc(state: rawptr) -> f32 {
	return k2.get_window_scale()
}

set_text_input :: proc(state: rawptr, on: bool) {
	// Karl2D does not currently expose text-input mode toggling through this API.
}

now_ns :: proc(state: rawptr) -> i64 {
	return time.now()._nsec
}

to_k2_rect :: proc(rect: skald.Rect) -> k2.Rect {
	return k2.Rect{rect.x, rect.y, rect.w, rect.h}
}

to_k2_color :: proc(color: skald.Color, alpha: f32 = 1) -> k2.Color {
	return {
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
