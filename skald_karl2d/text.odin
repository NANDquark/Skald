package skald_karl2d

import "core:strings"
import k2 "gui:karl2d"
import skald "gui:skald"

k2_load_font :: proc(state: rawptr, name: string, data: []byte) -> skald.Font {
	if len(data) == 0 {return 0}
	s := (^Backend_State)(state)
	font := k2.load_dynamic_font_from_bytes(data)
	if font == k2.FONT_NONE {return 0}
	append(&s.fonts, font)
	return skald.Font(len(s.fonts))
}

k2_measure_text :: proc(state: rawptr, text: string, size: f32, font: skald.Font) -> (f32, f32) {
	v := k2.measure_text(text, size, k2_font_for(state, font))
	return v.x, v.y
}

k2_draw_text :: proc(
	state: rawptr,
	text: string,
	x, y: f32,
	color: skald.Color,
	size: f32,
	font: skald.Font,
) {
	k2.draw_text(
		text,
		{x, y - k2_text_ascent(state, size, font)},
		size,
		to_k2_color(color),
		k2_font_for(state, font),
	)
}

k2_text_ascent :: proc(state: rawptr, size: f32, font: skald.Font) -> f32 {
	return size
}

k2_wrap_text :: proc(
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
		w, _ := k2_measure_text(state, candidate, size, font)
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

k2_span_font :: proc(state: rawptr, base_font: skald.Font, span: skald.Text_Span) -> skald.Font {
	return base_font
}

k2_font_for :: proc(state: rawptr, font: skald.Font) -> k2.Font {
	idx := int(font)
	if idx <= 0 {return k2.FONT_DEFAULT}
	s := (^Backend_State)(state)
	idx -= 1
	if idx < 0 || idx >= len(s.fonts) {return k2.FONT_DEFAULT}
	return s.fonts[idx]
}
