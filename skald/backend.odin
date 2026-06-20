#+build !js
package skald

import "core:strings"

renderer_render_context :: proc(backend: ^Backend, r: ^Renderer) -> Render_Context {
	assert(r != nil, "renderer_render_context requires renderer")
	rc := render_context_from_backend(backend)
	rc.renderer = r
	rc.frame_size = r.fb_size
	rc.widgets = r.widgets
	rc.overlays = &r.overlays
	rc.alpha_multiplier = r.alpha_multiplier
	rc.scale = r.scale
	return rc
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
	r := (^Renderer)(state)
	entry := image_cache_get(r, path)
	if entry == nil {return Backend_Image(nil)}
	return renderer_backend_image_handle(r, path, true)
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
	return renderer_backend_image_handle(r, name, false)
}

renderer_backend_image_update_pixels :: proc(
	state: rawptr,
	image: Backend_Image,
	w, h: u32,
	rgba: []u8,
) -> bool {
	handle := (^Backend_Image_Handle)(rawptr(image))
	if handle == nil || !handle.alive || handle.path {return false}
	return image_update_pixels((^Renderer)(state), handle.key, w, h, rgba)
}

renderer_backend_image_unload :: proc(state: rawptr, image: Backend_Image) {
	handle := (^Backend_Image_Handle)(rawptr(image))
	if handle == nil || !handle.alive {return}
	if !handle.path {
		image_unload((^Renderer)(state), handle.key)
	}
	handle.alive = false
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
	if handle == nil || !handle.alive {return false}
	r := (^Renderer)(state)
	entry: ^Image_Entry
	if handle.path {
		entry = image_cache_get(r, handle.key)
	} else if r.images.entries != nil {
		entry = r.images.entries[handle.key]
		if entry != nil {
			r.images.use_counter += 1
			entry.last_use = r.images.use_counter
		}
	}
	if entry == nil {return false}
	return image_draw_entry(r, entry, rect, fit, tint)
}

renderer_backend_image_handle :: proc(r: ^Renderer, key: string, path: bool) -> Backend_Image {
	if key == "" {return Backend_Image(nil)}
	if r.images.handles == nil {
		r.images.handles = make(map[string]^Backend_Image_Handle)
	}
	if handle, ok := r.images.handles[key]; ok && handle != nil {
		handle.path = path
		handle.alive = true
		return Backend_Image(handle)
	}
	handle := new(Backend_Image_Handle)
	cloned := strings.clone(key)
	handle^ = Backend_Image_Handle {
		key = cloned,
		path = path,
		alive = true,
	}
	r.images.handles[cloned] = handle
	return Backend_Image(handle)
}
