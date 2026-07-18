package skald_raylib

import "core:c"
import "core:strings"
import rl "vendor:raylib"
import skald "../skald"

rl_load_font :: proc(state: rawptr, name: string, data: []byte) -> skald.Font {
	if len(data) == 0 {return 0}
	s := (^Backend_State)(state)
	font := rl.LoadFontFromMemory(".ttf", raw_data(data), c.int(len(data)), 32, nil, 0)
	if !rl.IsFontValid(font) {return 0}
	append(&s.fonts, font)
	return skald.Font(len(s.fonts))
}

rl_measure_text :: proc(state: rawptr, text: string, size: f32, font: skald.Font) -> (f32, f32) {
	c_text := strings.clone_to_cstring(text, context.temp_allocator)
	v := rl.MeasureTextEx(rl_font_for(state, font), c_text, size, 1)
	return v.x, v.y
}

rl_draw_text :: proc(
	state: rawptr,
	text: string,
	x, y: f32,
	color: skald.Color,
	size: f32,
	font: skald.Font,
) {
	c_text := strings.clone_to_cstring(text, context.temp_allocator)
	rl.DrawTextEx(rl_font_for(state, font), c_text, {x, y - rl_text_ascent(state, size, font)}, size, 1, to_rl_color(color))
}

rl_text_ascent :: proc(state: rawptr, size: f32, font: skald.Font) -> f32 {
	return size
}

rl_wrap_text :: proc(
	state: rawptr,
	text: string,
	max_width, size: f32,
	font: skald.Font,
) -> []string {
	if len(text) == 0 {return []string{}}
	words := strings.fields(text, context.temp_allocator)
	lines := make([dynamic]string, context.temp_allocator)
	line := ""

	for word in words {
		candidate := word
		if len(line) > 0 {
			candidate = strings.concatenate({line, " ", word}, context.temp_allocator)
		}
		w, _ := rl_measure_text(state, candidate, size, font)
		if w > max_width && len(line) > 0 {
			append(&lines, line)
			line = word
		} else {
			line = candidate
		}
	}

	if len(line) > 0 {append(&lines, line)}
	return lines[:]
}

rl_span_font :: proc(state: rawptr, base_font: skald.Font, span: skald.Text_Span) -> skald.Font {
	return base_font
}

rl_font_for :: proc(state: rawptr, font: skald.Font) -> rl.Font {
	idx := int(font)
	if idx <= 0 {return rl.GetFontDefault()}
	s := (^Backend_State)(state)
	idx -= 1
	if idx < 0 || idx >= len(s.fonts) {return rl.GetFontDefault()}
	return s.fonts[idx]
}
