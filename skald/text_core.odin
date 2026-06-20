package skald

import "core:strings"

// Font is an opaque handle to a loaded typeface. Obtain one via `font_load`
// or use the default handle returned from `font_default`.
Font :: distinct int

font_load_ctx :: proc(r: ^Render_Context, name: string, data: []byte) -> Font {
	assert(r != nil, "font_load_ctx requires render context")
	assert(r.backend != nil, "font_load_ctx requires backend")
	assert(r.backend.text.load_font != nil, "font_load_ctx requires text.load_font callback")
	return r.backend.text.load_font(r.backend.state, name, data)
}

draw_text_ctx :: proc(
	r:     ^Render_Context,
	text:  string,
	x, y:  f32,
	color: Color,
	size:  f32 = 14,
	font:  Font = 0,
) {
	assert(r != nil, "draw_text_ctx requires render context")
	assert(r.backend != nil, "draw_text_ctx requires backend")
	assert(r.backend.text.draw != nil, "draw_text_ctx requires text.draw callback")
	r.backend.text.draw(r.backend.state, text, x, y, color, size, font)
}

text_ascent_ctx :: proc(r: ^Render_Context, size: f32, font: Font = 0) -> f32 {
	assert(r != nil, "text_ascent_ctx requires render context")
	assert(r.backend != nil, "text_ascent_ctx requires backend")
	assert(r.backend.text.ascent != nil, "text_ascent_ctx requires text.ascent callback")
	return r.backend.text.ascent(r.backend.state, size, font)
}

measure_text_ctx :: proc(
	r:    ^Render_Context,
	text: string,
	size: f32 = 14,
	font: Font = 0,
) -> (width, line_height: f32) {
	assert(r != nil, "measure_text_ctx requires render context")
	assert(r.backend != nil, "measure_text_ctx requires backend")
	assert(r.backend.text.measure != nil, "measure_text_ctx requires text.measure callback")
	return r.backend.text.measure(r.backend.state, text, size, font)
}

@(private)
text_line_advances_ctx :: proc(
	r:    ^Render_Context,
	text: string,
	size: f32 = 14,
	font: Font = 0,
	allocator := context.temp_allocator,
) -> []f32 {
	if r != nil && r.renderer != nil {
		return text_line_advances(r.renderer, text, size, font, allocator)
	}
	out := make([]f32, len(text) + 1, allocator)
	if r == nil || len(text) == 0 {return out}
	for i := 0; i < len(text); {
		next := i + utf8_step(text, i)
		out[next], _ = measure_text_ctx(r, text[:next], size, font)
		i = next
	}
	fill_missing_advances(out)
	return out
}

wrap_text_ctx :: proc(
	r:         ^Render_Context,
	text:      string,
	max_width: f32,
	size:      f32 = 14,
	font:      Font = 0,
) -> []string {
	assert(r != nil, "wrap_text_ctx requires render context")
	assert(r.backend != nil, "wrap_text_ctx requires backend")
	assert(r.backend.text.wrap != nil, "wrap_text_ctx requires text.wrap callback")
	return r.backend.text.wrap(r.backend.state, text, max_width, size, font)
}

@(private)
utf8_step :: proc(s: string, i: int) -> int {
	if i >= len(s) {return 0}
	b := s[i]
	switch {
	case b < 0x80: return 1
	case b < 0xC0: return 1
	case b < 0xE0: return 2
	case b < 0xF0: return 3
	}
	return 4
}

split_lines :: proc(s: string) -> []string {
	lines: [dynamic]string
	lines.allocator = context.temp_allocator
	if len(s) == 0 {
		append(&lines, "")
		return lines[:]
	}
	line_start := 0
	i := 0
	for i < len(s) {
		if s[i] == '\n' {
			append(&lines, s[line_start:i])
			i += 1
			line_start = i
		} else if s[i] == '\r' {
			append(&lines, s[line_start:i])
			i += 1
			if i < len(s) && s[i] == '\n' {i += 1}
			line_start = i
		} else {
			i += 1
		}
	}
	if line_start < len(s) {append(&lines, s[line_start:])}
	if len(lines) == 0 {append(&lines, "")}
	return lines[:]
}

TAB_WIDTH :: 4

expand_tabs :: proc(s: string) -> string {
	if !strings.contains_rune(s, '\t') {return s}
	sb := strings.builder_make(context.temp_allocator)
	strings.builder_grow(&sb, len(s) + TAB_WIDTH)
	for i in 0..<len(s) {
		if s[i] == '\t' {
			for _ in 0..<TAB_WIDTH {strings.write_byte(&sb, ' ')}
		} else {
			strings.write_byte(&sb, s[i])
		}
	}
	return strings.to_string(sb)
}

@(private)
fill_missing_advances :: proc(out: []f32) {
	prev: f32
	for b in 1..<len(out) {
		if out[b] == 0 {
			out[b] = prev
		} else {
			prev = out[b]
		}
	}
}

Rich_Segment :: struct {
	span_idx:   int,
	byte_start: int,
	byte_end:   int,
	x_offset:   f32,
	width:      f32,
}

Rich_Line :: struct {
	segments: []Rich_Segment,
	width:    f32,
	ascent:   f32,
	height:   f32,
}
