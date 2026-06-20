#+build js
package skald

draw_rect :: proc(r: ^Render_Context, rect: Rect, color: Color, radius: f32 = 0) {
	render_context_draw_rect(r, rect, color, radius)
}

draw_shadow :: proc(r: ^Render_Context, rect: Rect, radius, blur: f32, color: Color, offset: [2]f32 = {0, 4}) {
	render_context_draw_shadow(r, rect, radius, blur, color, offset)
}

draw_gradient_rect :: proc(r: ^Render_Context, rect: Rect, c_tl, c_tr, c_br, c_bl: Color, radius: f32 = 0) {
	render_context_draw_gradient_rect(r, rect, c_tl, c_tr, c_br, c_bl, radius)
}

draw_triangles :: proc(r: ^Renderer, verts: [][2]f32, color: Color) {
	_, _, _ = r, verts, color
}

draw_triangle_strip :: proc(r: ^Renderer, verts: [][2]f32, color: Color) {
	_, _, _ = r, verts, color
}

draw_stroke :: proc(r: ^Renderer, samples: []Stroke_Sample, base_width: f32, color: Color) {
	_, _, _, _ = r, samples, base_width, color
}
