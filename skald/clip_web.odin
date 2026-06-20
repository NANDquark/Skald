#+build js
package skald

push_clip :: proc(r: ^Render_Context, rect: Rect) {
	render_context_push_clip(r, rect)
}

pop_clip :: proc(r: ^Render_Context) {
	render_context_pop_clip(r)
}
