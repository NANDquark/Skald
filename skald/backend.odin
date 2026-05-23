package skald

import "core:strings"

Backend_Image :: distinct rawptr

Backend_Image_Handle :: struct {
	key:   string,
	path:  bool,
	owned: bool,
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

renderer_render_context :: proc(backend: ^Backend, r: ^Renderer) -> Render_Context {
	assert(r != nil, "renderer_render_context requires renderer")
	rc := render_context_from_backend(backend)
	rc.frame_size = r.fb_size
	rc.widgets = r.widgets
	rc.overlays = &r.overlays
	rc.alpha_multiplier = r.alpha_multiplier
	rc.scale = r.scale
	return rc
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
	load_pixels:   proc(state: rawptr, name: string, w, h: u32, rgba: []u8) -> Backend_Image,
	update_pixels: proc(state: rawptr, image: Backend_Image, w, h: u32, rgba: []u8) -> bool,
	unload:        proc(state: rawptr, image: Backend_Image),
	draw:          proc(state: rawptr, image: Backend_Image, rect: Rect, tint: Color),
	draw_fit:      proc(
		state: rawptr,
		image: Backend_Image,
		rect: Rect,
		fit: Image_Fit,
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

renderer_backend :: proc(r: ^Renderer) -> Backend {
	assert(r != nil, "renderer_backend requires renderer")
	return Backend {
		state = r,
		// Advertise service capabilities only when their backend groups are wired.
		capabilities = {},
		draw = Backend_Draw {
			rect = renderer_backend_rect,
			gradient_rect = renderer_backend_gradient_rect,
			shadow = renderer_backend_shadow,
			push_clip = renderer_backend_push_clip,
			pop_clip = renderer_backend_pop_clip,
			set_alpha = renderer_backend_set_alpha,
		},
		text = Backend_Text {
			load_font = renderer_backend_font_load,
			measure = renderer_backend_text_measure,
			wrap = renderer_backend_text_wrap,
			ascent = renderer_backend_text_ascent,
			draw = renderer_backend_text_draw,
			span_font = renderer_backend_text_span_font,
		},
		images = Backend_Images {
			load_path = renderer_backend_image_load_path,
			load_pixels = renderer_backend_image_load_pixels,
			update_pixels = renderer_backend_image_update_pixels,
			unload = renderer_backend_image_unload,
			draw = renderer_backend_image_draw,
			draw_fit = renderer_backend_image_draw_fit,
		},
	}
}

renderer_backend_rect :: proc(state: rawptr, rect: Rect, color: Color, radius: f32) {
	renderer_draw_rect((^Renderer)(state), rect, color, radius)
}

renderer_backend_gradient_rect :: proc(
	state: rawptr,
	rect: Rect,
	c_tl, c_tr, c_br, c_bl: Color,
	radius: f32,
) {
	renderer_draw_gradient_rect((^Renderer)(state), rect, c_tl, c_tr, c_br, c_bl, radius)
}

renderer_backend_shadow :: proc(
	state: rawptr,
	rect: Rect,
	radius: f32,
	blur: f32,
	color: Color,
	offset: [2]f32,
) {
	renderer_draw_shadow((^Renderer)(state), rect, radius, blur, color, offset)
}

renderer_backend_push_clip :: proc(state: rawptr, rect: Rect) {
	renderer_push_clip((^Renderer)(state), rect)
}

renderer_backend_pop_clip :: proc(state: rawptr) {
	renderer_pop_clip((^Renderer)(state))
}

renderer_backend_set_alpha :: proc(state: rawptr, alpha: f32) {
	(^Renderer)(state).alpha_multiplier = alpha
}

renderer_backend_font_load :: proc(state: rawptr, name: string, data: []byte) -> Font {
	return font_load((^Renderer)(state), name, data)
}

renderer_backend_text_measure :: proc(
	state: rawptr,
	text: string,
	size: f32,
	font: Font,
) -> (f32, f32) {
	return measure_text((^Renderer)(state), text, size, font)
}

renderer_backend_text_wrap :: proc(
	state: rawptr,
	text: string,
	max_width, size: f32,
	font: Font,
) -> []string {
	return wrap_text((^Renderer)(state), text, max_width, size, font)
}

renderer_backend_text_ascent :: proc(state: rawptr, size: f32, font: Font) -> f32 {
	return text_ascent((^Renderer)(state), size, font)
}

renderer_backend_text_draw :: proc(
	state: rawptr,
	text: string,
	x, y: f32,
	color: Color,
	size: f32,
	font: Font,
) {
	draw_text((^Renderer)(state), text, x, y, color, size, font)
}

renderer_backend_text_span_font :: proc(state: rawptr, base_font: Font, span: Text_Span) -> Font {
	return rich_span_font((^Renderer)(state), base_font, span)
}

renderer_backend_image_load_path :: proc(state: rawptr, path: string) -> Backend_Image {
	entry := image_cache_get((^Renderer)(state), path)
	if entry == nil {return Backend_Image(nil)}
	return renderer_backend_image_handle(path, true)
}

renderer_backend_image_load_pixels :: proc(
	state: rawptr,
	name: string,
	w, h: u32,
	rgba: []u8,
) -> Backend_Image {
	r := (^Renderer)(state)
	if !image_load_pixels(r, name, w, h, rgba) {return Backend_Image(nil)}
	entry := image_cache_get(r, name)
	if entry == nil {return Backend_Image(nil)}
	return renderer_backend_image_handle(name, false)
}

renderer_backend_image_update_pixels :: proc(
	state: rawptr,
	image: Backend_Image,
	w, h: u32,
	rgba: []u8,
) -> bool {
	handle := (^Backend_Image_Handle)(rawptr(image))
	if handle == nil || handle.path {return false}
	return image_update_pixels((^Renderer)(state), handle.key, w, h, rgba)
}

renderer_backend_image_unload :: proc(state: rawptr, image: Backend_Image) {
	handle := (^Backend_Image_Handle)(rawptr(image))
	if handle == nil {return}
	if !handle.path {
		image_unload((^Renderer)(state), handle.key)
	}
	if handle.owned {
		delete(handle.key)
		free(handle)
	}
}

renderer_backend_image_draw :: proc(state: rawptr, image: Backend_Image, rect: Rect, tint: Color) {
	renderer_backend_image_draw_fit(state, image, rect, .Cover, tint)
}

renderer_backend_image_draw_fit :: proc(
	state: rawptr,
	image: Backend_Image,
	rect: Rect,
	fit: Image_Fit,
	tint: Color,
) -> bool {
	handle := (^Backend_Image_Handle)(rawptr(image))
	if handle == nil {return false}
	entry := image_cache_get((^Renderer)(state), handle.key)
	if entry == nil {return false}
	return image_draw_entry((^Renderer)(state), entry, rect, fit, tint)
}

renderer_backend_image_handle :: proc(key: string, path: bool) -> Backend_Image {
	handle := new(Backend_Image_Handle)
	handle^ = Backend_Image_Handle {
		key = strings.clone(key),
		path = path,
		owned = true,
	}
	return Backend_Image(handle)
}
