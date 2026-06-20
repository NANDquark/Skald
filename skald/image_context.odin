package skald

image_load_path_ctx :: proc(r: ^Render_Context, path: string) -> Backend_Image {
	assert(r != nil, "image_load_path_ctx requires render context")
	assert(r.backend != nil, "image_load_path_ctx requires backend")
	assert(
		r.backend.images.load_path != nil,
		"image_load_path_ctx requires images.load_path callback",
	)
	return r.backend.images.load_path(r.backend.state, path)
}

image_load_bytes_ctx :: proc(r: ^Render_Context, name: string, bytes: []byte) -> Backend_Image {
	if r == nil || r.backend == nil || r.backend.images.load_bytes == nil {
		return Backend_Image(nil)
	}
	return r.backend.images.load_bytes(r.backend.state, name, bytes)
}

image_size_ctx :: proc(r: ^Render_Context, image: Backend_Image) -> (size: [2]f32, ok: bool) {
	if r == nil || r.backend == nil || r.backend.images.size == nil || rawptr(image) == nil {
		return {}, false
	}
	return r.backend.images.size(r.backend.state, image)
}

image_load_pixels_ctx :: proc(
	r: ^Render_Context,
	name: string,
	w, h: u32,
	rgba: []u8,
) -> Backend_Image {
	assert(r != nil, "image_load_pixels_ctx requires render context")
	assert(r.backend != nil, "image_load_pixels_ctx requires backend")
	assert(
		r.backend.images.load_pixels != nil,
		"image_load_pixels_ctx requires images.load_pixels callback",
	)
	return r.backend.images.load_pixels(r.backend.state, name, w, h, rgba)
}

image_update_pixels_ctx :: proc(
	r: ^Render_Context,
	image: Backend_Image,
	w, h: u32,
	rgba: []u8,
) -> bool {
	assert(r != nil, "image_update_pixels_ctx requires render context")
	assert(r.backend != nil, "image_update_pixels_ctx requires backend")
	assert(
		r.backend.images.update_pixels != nil,
		"image_update_pixels_ctx requires images.update_pixels callback",
	)
	return r.backend.images.update_pixels(r.backend.state, image, w, h, rgba)
}

image_unload_ctx :: proc(r: ^Render_Context, image: Backend_Image) {
	assert(r != nil, "image_unload_ctx requires render context")
	assert(r.backend != nil, "image_unload_ctx requires backend")
	assert(r.backend.images.unload != nil, "image_unload_ctx requires images.unload callback")
	r.backend.images.unload(r.backend.state, image)
}

draw_image_ctx :: proc(
	r: ^Render_Context,
	image: Backend_Image,
	rect: Rect,
	tint: Color = Color{1, 1, 1, 1},
) {
	assert(r != nil, "draw_image_ctx requires render context")
	assert(r.backend != nil, "draw_image_ctx requires backend")
	assert(r.backend.images.draw != nil, "draw_image_ctx requires images.draw callback")
	r.backend.images.draw(r.backend.state, image, rect, tint)
}

draw_image_fit_ctx :: proc(
	r: ^Render_Context,
	image: Backend_Image,
	rect: Rect,
	fit: Image_Fit = .Cover,
	tint: Color = Color{1, 1, 1, 1},
) -> bool {
	assert(r != nil, "draw_image_fit_ctx requires render context")
	assert(r.backend != nil, "draw_image_fit_ctx requires backend")
	assert(
		r.backend.images.draw_fit != nil,
		"draw_image_fit_ctx requires images.draw_fit callback",
	)
	return r.backend.images.draw_fit(r.backend.state, image, rect, fit, tint)
}

draw_image_region_ctx :: proc(
	r: ^Render_Context,
	image: Backend_Image,
	src, dst: Rect,
	tint: Color = Color{1, 1, 1, 1},
) -> bool {
	if r == nil || r.backend == nil || r.backend.images.draw_region == nil || rawptr(image) == nil {
		return false
	}
	return r.backend.images.draw_region(r.backend.state, image, src, dst, tint)
}
