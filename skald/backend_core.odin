package skald

Backend_Image :: distinct rawptr

Backend_Image_Handle :: struct {
	key:   string,
	path:  bool,
	alive: bool,
}

Backend_Capability :: enum {
	Clipboard,
	Native_File_Dialogs,
	Text_Input_Mode,
	Multi_Window,
	Gamepad_Navigation,
}

Backend_Capabilities :: bit_set[Backend_Capability]

Input_Capture :: struct {
	mouse:           bool,
	keyboard:        bool,
	text:            bool,
	wheel:           bool,
	pointer_over_ui: bool,
}

Backend :: struct {
	state:        rawptr,
	capabilities: Backend_Capabilities,
	frame:        Backend_Frame,
	draw:         Backend_Draw,
	text:         Backend_Text,
	images:       Backend_Images,
	input:        Backend_Input,
	clipboard:    Backend_Clipboard,
	window:       Backend_Window,
	time:         Backend_Time,
}

Render_Context :: struct {
	backend:          ^Backend,
	renderer:         ^Renderer,
	frame_size:       [2]u32,
	widgets:          ^Widget_Store,
	overlays:         ^[dynamic]Overlay_Entry,
	alpha_multiplier: f32,
	scale:            f32,
}

render_context_from_backend :: proc(backend: ^Backend) -> Render_Context {
	assert(backend != nil, "render_context_from_backend requires backend")
	return Render_Context{backend = backend, alpha_multiplier = 1, scale = 1}
}

Backend_Frame :: struct {
	begin: proc(state: rawptr, clear: Color) -> bool,
	end:   proc(state: rawptr),
}

Backend_Draw :: struct {
	rect:          proc(state: rawptr, rect: Rect, color: Color, radius: f32),
	gradient_rect: proc(state: rawptr, rect: Rect, c_tl, c_tr, c_br, c_bl: Color, radius: f32),
	shadow:        proc(
		state: rawptr,
		rect: Rect,
		radius, blur: f32,
		color: Color,
		offset: [2]f32,
	),
	push_clip:     proc(state: rawptr, rect: Rect),
	pop_clip:      proc(state: rawptr),
	set_alpha:     proc(state: rawptr, alpha: f32),
}

Backend_Text :: struct {
	load_font: proc(state: rawptr, name: string, data: []byte) -> Font,
	measure:   proc(state: rawptr, text: string, size: f32, font: Font) -> (f32, f32),
	// Returned slices and strings must be valid through the current frame
	// unless the specific backend documents stronger ownership.
	wrap:      proc(state: rawptr, text: string, max_width, size: f32, font: Font) -> []string,
	ascent:    proc(state: rawptr, size: f32, font: Font) -> f32,
	draw:      proc(state: rawptr, text: string, x, y: f32, color: Color, size: f32, font: Font),
	span_font: proc(state: rawptr, base_font: Font, span: Text_Span) -> Font,
}

Backend_Images :: struct {
	load_path:     proc(state: rawptr, path: string) -> Backend_Image,
	load_bytes:    proc(state: rawptr, name: string, bytes: []byte) -> Backend_Image,
	load_pixels:   proc(state: rawptr, name: string, w, h: u32, rgba: []u8) -> Backend_Image,
	update_pixels: proc(state: rawptr, image: Backend_Image, w, h: u32, rgba: []u8) -> bool,
	unload:        proc(state: rawptr, image: Backend_Image),
	size:          proc(state: rawptr, image: Backend_Image) -> (size: [2]f32, ok: bool),
	draw:          proc(state: rawptr, image: Backend_Image, rect: Rect, tint: Color),
	draw_fit:      proc(
		state: rawptr,
		image: Backend_Image,
		rect: Rect,
		fit: Image_Fit,
		tint: Color,
	) -> bool,
	draw_region: proc(
		state: rawptr,
		image: Backend_Image,
		src, dst: Rect,
		tint: Color,
	) -> bool,
}

Backend_Input :: struct {
	snapshot: proc(state: rawptr) -> Input,
	capture:  proc(state: rawptr) -> Input_Capture,
}

Backend_Clipboard :: struct {
	set_text: proc(state: rawptr, text: string) -> bool,
	// Returned strings must be valid through the current frame unless the
	// specific backend documents stronger ownership.
	get_text: proc(state: rawptr) -> string,
}

Backend_Window :: struct {
	size:           proc(state: rawptr) -> Size,
	scale:          proc(state: rawptr) -> f32,
	set_text_input: proc(state: rawptr, on: bool),
}

Backend_Time :: struct {
	now_ns: proc(state: rawptr) -> i64,
}

backend_draw_rect :: proc(rc: ^Render_Context, rect: Rect, color: Color, radius: f32 = 0) {
	assert(rc != nil, "backend_draw_rect requires render context")
	assert(rc.backend != nil, "backend_draw_rect requires backend")
	assert(rc.backend.draw.rect != nil, "backend_draw_rect requires draw.rect callback")
	rc.backend.draw.rect(rc.backend.state, rect, color, radius)
}

backend_draw_gradient_rect :: proc(
	rc: ^Render_Context,
	rect: Rect,
	c_tl, c_tr, c_br, c_bl: Color,
	radius: f32 = 0,
) {
	assert(rc != nil, "backend_draw_gradient_rect requires render context")
	assert(rc.backend != nil, "backend_draw_gradient_rect requires backend")
	assert(
		rc.backend.draw.gradient_rect != nil,
		"backend_draw_gradient_rect requires draw.gradient_rect callback",
	)
	rc.backend.draw.gradient_rect(rc.backend.state, rect, c_tl, c_tr, c_br, c_bl, radius)
}

backend_draw_shadow :: proc(
	rc: ^Render_Context,
	rect: Rect,
	radius: f32,
	blur: f32,
	color: Color,
	offset: [2]f32 = {0, 4},
) {
	assert(rc != nil, "backend_draw_shadow requires render context")
	assert(rc.backend != nil, "backend_draw_shadow requires backend")
	assert(rc.backend.draw.shadow != nil, "backend_draw_shadow requires draw.shadow callback")
	rc.backend.draw.shadow(rc.backend.state, rect, radius, blur, color, offset)
}

backend_push_clip :: proc(rc: ^Render_Context, rect: Rect) {
	assert(rc != nil, "backend_push_clip requires render context")
	assert(rc.backend != nil, "backend_push_clip requires backend")
	assert(rc.backend.draw.push_clip != nil, "backend_push_clip requires draw.push_clip callback")
	rc.backend.draw.push_clip(rc.backend.state, rect)
}

backend_pop_clip :: proc(rc: ^Render_Context) {
	assert(rc != nil, "backend_pop_clip requires render context")
	assert(rc.backend != nil, "backend_pop_clip requires backend")
	assert(rc.backend.draw.pop_clip != nil, "backend_pop_clip requires draw.pop_clip callback")
	rc.backend.draw.pop_clip(rc.backend.state)
}

backend_set_alpha :: proc(rc: ^Render_Context, alpha: f32) {
	assert(rc != nil, "backend_set_alpha requires render context")
	assert(rc.backend != nil, "backend_set_alpha requires backend")
	assert(rc.backend.draw.set_alpha != nil, "backend_set_alpha requires draw.set_alpha callback")
	rc.backend.draw.set_alpha(rc.backend.state, alpha)
}
