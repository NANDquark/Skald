package skald

render_context_push_clip :: proc(r: ^Render_Context, rect: Rect) {
	if r.widgets != nil {
		new_rect := rect
		if len(r.widgets.clip_stack) > 0 {
			new_rect = rect_intersect(r.widgets.clip_stack[len(r.widgets.clip_stack) - 1], rect)
		}
		append(&r.widgets.clip_stack, new_rect)
	}
	backend_push_clip(r, rect)
}

render_context_pop_clip :: proc(r: ^Render_Context) {
	if r.widgets != nil && len(r.widgets.clip_stack) > 0 {
		pop(&r.widgets.clip_stack)
	}
	backend_pop_clip(r)
}

@(private)
rect_intersect :: proc(a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(a.x + a.w, b.x + b.w)
	y1 := min(a.y + a.h, b.y + b.h)
	if x1 <= x0 || y1 <= y0 {
		return Rect{0, 0, 0, 0}
	}
	return Rect{x0, y0, x1 - x0, y1 - y0}
}
