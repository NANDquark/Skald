package skald

Stroke_Sample :: struct {
	pos:      [2]f32,
	pressure: f32,
}

render_context_draw_rect :: proc(r: ^Render_Context, rect: Rect, color: Color, radius: f32 = 0) {
	backend_draw_rect(r, rect, color, radius)
}

render_context_draw_shadow :: proc(
	r: ^Render_Context,
	rect: Rect,
	radius: f32,
	blur: f32,
	color: Color,
	offset: [2]f32 = {0, 4},
) {
	backend_draw_shadow(r, rect, radius, blur, color, offset)
}

render_context_draw_gradient_rect :: proc(
	r: ^Render_Context,
	rect: Rect,
	c_tl, c_tr, c_br, c_bl: Color,
	radius: f32 = 0,
) {
	backend_draw_gradient_rect(r, rect, c_tl, c_tr, c_br, c_bl, radius)
}
