#+build js
package skald

font_default :: proc(r: ^Renderer) -> Font {
	_ = r
	return 0
}

text_shape_cache_size :: proc(r: ^Renderer) -> int {
	_ = r
	return 0
}

font_bold :: proc(r: ^Renderer) -> Font {
	_ = r
	return 0
}

font_italic :: proc(r: ^Renderer) -> Font {
	_ = r
	return 0
}

font_bold_italic :: proc(r: ^Renderer) -> Font {
	_ = r
	return 0
}

font_load :: proc(r: ^Renderer, name: string, data: []byte) -> Font {
	_, _, _ = r, name, data
	return 0
}

font_add_fallback :: proc(r: ^Renderer, base, fallback: Font) -> bool {
	_, _, _ = r, base, fallback
	return false
}

font_use_default_emoji :: proc(r: ^Renderer) -> Font {
	_ = r
	return 0
}

draw_text :: proc(r: ^Renderer, text: string, x, y: f32, color: Color, size: f32 = 14, font: Font = 0) {
	_, _, _, _, _, _, _ = r, text, x, y, color, size, font
}

text_ascent :: proc(r: ^Renderer, size: f32, font: Font = 0) -> f32 {
	_, _ = r, font
	return size * 0.8
}

measure_text :: proc(r: ^Renderer, text: string, size: f32 = 14, font: Font = 0) -> (width, line_height: f32) {
	_, _ = r, font
	return f32(len(text)) * size * 0.55, size * 1.2
}

@(private)
text_line_advances :: proc(r: ^Renderer, text: string, size: f32 = 14, font: Font = 0, allocator := context.temp_allocator) -> []f32 {
	_, _ = r, font
	out := make([]f32, len(text) + 1, allocator)
	for i := 0; i < len(text); {
		next := i + utf8_step(text, i)
		out[next] = f32(next) * size * 0.55
		i = next
	}
	fill_missing_advances(out)
	return out
}

byte_index_at_x :: proc(r: ^Renderer, text: string, size: f32 = 14, font: Font = 0, x: f32) -> int {
	if x <= 0 || len(text) == 0 {return 0}
	prev_w: f32
	prev_i := 0
	for i := 0; i < len(text); {
		next := i + utf8_step(text, i)
		w, _ := measure_text(r, text[:next], size, font)
		if w >= x {
			if x - prev_w < w - x {return prev_i}
			return next
		}
		prev_w = w
		prev_i = next
		i = next
	}
	return len(text)
}

wrap_text :: proc(r: ^Renderer, text: string, max_width: f32, size: f32 = 14, font: Font = 0) -> []string {
	if max_width <= 0 {return split_lines(text)}
	lines: [dynamic]string
	lines.allocator = context.temp_allocator
	for para_raw in split_lines(text) {
		para := expand_tabs(para_raw)
		if len(para) == 0 {
			append(&lines, "")
			continue
		}
		start := 0
		last_space := -1
		for i := 0; i < len(para); {
			next := i + utf8_step(para, i)
			w, _ := measure_text(r, para[start:next], size, font)
			if w > max_width && start < i {
				end := i
				if last_space > start {end = last_space}
				append(&lines, para[start:end])
				start = end
				for start < len(para) && para[start] == ' ' {start += 1}
				i = start
				last_space = -1
				continue
			}
			if para[i] == ' ' {last_space = i}
			i = next
		}
		if start < len(para) {append(&lines, para[start:])}
	}
	if len(lines) == 0 {append(&lines, "")}
	return lines[:]
}

wrap_rich_text :: proc(r: ^Renderer, spans: []Text_Span, base_size: f32, base_font: Font, max_width: f32) -> []Rich_Line {
	return wrap_rich_text_measured(r, nil, spans, base_size, base_font, max_width)
}

wrap_rich_text_ctx :: proc(r: ^Render_Context, spans: []Text_Span, base_size: f32, base_font: Font, max_width: f32) -> []Rich_Line {
	return wrap_rich_text_measured(nil, r, spans, base_size, base_font, max_width)
}

@(private)
wrap_rich_text_measured :: proc(
	r: ^Renderer,
	rc: ^Render_Context,
	spans: []Text_Span,
	base_size: f32,
	base_font: Font,
	max_width: f32,
) -> []Rich_Line {
	lines: [dynamic]Rich_Line
	lines.allocator = context.temp_allocator
	measure := proc(r: ^Renderer, rc: ^Render_Context, text: string, size: f32, font: Font) -> (f32, f32) {
		if rc != nil {return measure_text_ctx(rc, text, size, font)}
		return measure_text(r, text, size, font)
	}
	ascent_of := proc(r: ^Renderer, rc: ^Render_Context, size: f32, font: Font) -> f32 {
		if rc != nil {return text_ascent_ctx(rc, size, font)}
		return text_ascent(r, size, font)
	}
	span_font_of := proc(r: ^Renderer, rc: ^Render_Context, base: Font, sp: Text_Span) -> Font {
		if rc != nil {return rich_span_font_ctx(rc, base, sp)}
		return rich_span_font(r, base, sp)
	}
	if len(spans) == 0 {
		append(&lines, Rich_Line{ascent = ascent_of(r, rc, base_size, base_font), height = base_size * 1.2})
		return lines[:]
	}

	cur_segments: [dynamic]Rich_Segment
	cur_segments.allocator = context.temp_allocator
	cur_w, cur_a, cur_h: f32
	flush :: proc(lines: ^[dynamic]Rich_Line, segs: ^[dynamic]Rich_Segment, w, a, h: f32) {
		lh := h
		if lh == 0 {lh = 14}
		append(lines, Rich_Line{segments = segs[:], width = w, ascent = a, height = lh})
	}

	for sp, sp_idx in spans {
		fnt := span_font_of(r, rc, base_font, sp)
		sz := rich_span_size(base_size, sp)
		asc := ascent_of(r, rc, sz, fnt)
		_, lh := measure(r, rc, "", sz, fnt)
		pieces := split_lines(sp.str)
		for piece, piece_idx in pieces {
			if piece_idx > 0 {
				flush(&lines, &cur_segments, cur_w, cur_a, cur_h)
				clear(&cur_segments)
				cur_w, cur_a, cur_h = 0, 0, 0
			}
			if len(piece) == 0 {continue}
			w, _ := measure(r, rc, piece, sz, fnt)
			if max_width > 0 && cur_w > 0 && cur_w + w > max_width {
				flush(&lines, &cur_segments, cur_w, cur_a, cur_h)
				clear(&cur_segments)
				cur_w, cur_a, cur_h = 0, 0, 0
			}
			append(&cur_segments, Rich_Segment{
				span_idx = sp_idx,
				byte_start = 0,
				byte_end = len(piece),
				x_offset = cur_w,
				width = w,
			})
			cur_w += w
			cur_a = max(cur_a, asc)
			cur_h = max(cur_h, lh)
		}
	}
	if len(cur_segments) > 0 || len(lines) == 0 {
		flush(&lines, &cur_segments, cur_w, cur_a, cur_h)
	}
	return lines[:]
}
