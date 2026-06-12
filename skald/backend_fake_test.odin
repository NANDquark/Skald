package skald

import "core:testing"

Fake_Draw_Kind :: enum {
	Rect,
	Push_Clip,
	Pop_Clip,
	Set_Alpha,
	Image,
}

Fake_Draw_Op :: struct {
	kind:   Fake_Draw_Kind,
	rect:   Rect,
	src:    Rect,
	color:  Color,
	radius: f32,
	alpha:  f32,
	image:  Backend_Image,
	fit:    Image_Fit,
}

Fake_Backend_State :: struct {
	ops:               [dynamic]Fake_Draw_Op,
	image_load_path:   string,
	image_load_name:   string,
	image_w:           u32,
	image_h:           u32,
	image_rgba_len:    int,
	image_encoded_len: int,
	image_native_size: [2]f32,
	image_updated:     bool,
}

fake_draw_rect :: proc(state: rawptr, rect: Rect, color: Color, radius: f32) {
	s := (^Fake_Backend_State)(state)
	append(&s.ops, Fake_Draw_Op{kind = .Rect, rect = rect, color = color, radius = radius})
}

fake_push_clip :: proc(state: rawptr, rect: Rect) {
	s := (^Fake_Backend_State)(state)
	append(&s.ops, Fake_Draw_Op{kind = .Push_Clip, rect = rect})
}

fake_pop_clip :: proc(state: rawptr) {
	s := (^Fake_Backend_State)(state)
	append(&s.ops, Fake_Draw_Op{kind = .Pop_Clip})
}

fake_set_alpha :: proc(state: rawptr, alpha: f32) {
	s := (^Fake_Backend_State)(state)
	append(&s.ops, Fake_Draw_Op{kind = .Set_Alpha, alpha = alpha})
}

fake_measure_text :: proc(state: rawptr, text: string, size: f32, font: Font) -> (f32, f32) {
	return f32(len(text)) * size, size
}

fake_image_load_path :: proc(state: rawptr, path: string) -> Backend_Image {
	s := (^Fake_Backend_State)(state)
	s.image_load_path = path
	if path == "" {return Backend_Image(nil)}
	return Backend_Image(state)
}

fake_image_load_bytes :: proc(state: rawptr, name: string, bytes: []byte) -> Backend_Image {
	s := (^Fake_Backend_State)(state)
	s.image_load_name = name
	s.image_encoded_len = len(bytes)
	if len(name) == 0 || len(bytes) == 0 {return Backend_Image(nil)}
	return Backend_Image(state)
}

fake_image_load_pixels :: proc(
	state: rawptr,
	name: string,
	w, h: u32,
	rgba: []u8,
) -> Backend_Image {
	s := (^Fake_Backend_State)(state)
	s.image_load_name = name
	s.image_w = w
	s.image_h = h
	s.image_rgba_len = len(rgba)
	return Backend_Image(state)
}

fake_image_update_pixels :: proc(
	state: rawptr,
	image: Backend_Image,
	w, h: u32,
	rgba: []u8,
) -> bool {
	s := (^Fake_Backend_State)(state)
	s.image_updated = rawptr(image) != nil
	s.image_w = w
	s.image_h = h
	s.image_rgba_len = len(rgba)
	return s.image_updated
}

fake_image_unload :: proc(state: rawptr, image: Backend_Image) {}

fake_image_size :: proc(state: rawptr, image: Backend_Image) -> (size: [2]f32, ok: bool) {
	s := (^Fake_Backend_State)(state)
	return s.image_native_size, rawptr(image) != nil
}

fake_image_draw :: proc(state: rawptr, image: Backend_Image, rect: Rect, tint: Color) {
	s := (^Fake_Backend_State)(state)
	append(
		&s.ops,
		Fake_Draw_Op{kind = .Image, rect = rect, color = tint, image = image, fit = .Cover},
	)
}

fake_image_draw_fit :: proc(
	state: rawptr,
	image: Backend_Image,
	rect: Rect,
	fit: Image_Fit,
	tint: Color,
) -> bool {
	s := (^Fake_Backend_State)(state)
	append(
		&s.ops,
		Fake_Draw_Op{kind = .Image, rect = rect, color = tint, image = image, fit = fit},
	)
	return rawptr(image) != nil
}

fake_image_draw_region :: proc(
	state: rawptr,
	image: Backend_Image,
	src, dst: Rect,
	tint: Color,
) -> bool {
	s := (^Fake_Backend_State)(state)
	append(&s.ops, Fake_Draw_Op{kind = .Image, src = src, rect = dst, color = tint, image = image})
	return rawptr(image) != nil
}

fake_backend :: proc(state: ^Fake_Backend_State) -> Backend {
	return Backend {
		state = state,
		draw = Backend_Draw {
			rect = fake_draw_rect,
			push_clip = fake_push_clip,
			pop_clip = fake_pop_clip,
			set_alpha = fake_set_alpha,
		},
		images = Backend_Images {
			load_path = fake_image_load_path,
			load_bytes = fake_image_load_bytes,
			load_pixels = fake_image_load_pixels,
			update_pixels = fake_image_update_pixels,
			unload = fake_image_unload,
			size = fake_image_size,
			draw = fake_image_draw,
			draw_fit = fake_image_draw_fit,
			draw_region = fake_image_draw_region,
		},
	}
}

@(test)
backend_text_measure_uses_service :: proc(t: ^testing.T) {
	fake: Fake_Backend_State

	backend := fake_backend(&fake)
	backend.text.measure = fake_measure_text
	rc := render_context_from_backend(&backend)

	w, h := measure_text_ctx(&rc, "abc", 12, 0)

	testing.expect_value(t, w, f32(36))
	testing.expect_value(t, h, f32(12))
}

@(test)
backend_context_records_draws :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	defer delete(fake.ops)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)

	backend_draw_rect(&rc, {x = 10, y = 20, w = 30, h = 40}, rgb(0xFF0000), 4)
	backend_push_clip(&rc, {x = 0, y = 0, w = 100, h = 80})
	backend_pop_clip(&rc)

	if !testing.expect_value(t, len(fake.ops), 3) {
		return
	}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[0].rect, Rect{10, 20, 30, 40})
	testing.expect_value(t, fake.ops[0].color, rgb(0xFF0000))
	testing.expect_value(t, fake.ops[0].radius, f32(4))
	testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Push_Clip)
	testing.expect_value(t, fake.ops[2].kind, Fake_Draw_Kind.Pop_Clip)
}

@(test)
render_view_draws_rect_through_backend_context :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	defer delete(fake.ops)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)

	render_view(&rc, rect({10, 20}, rgb(0x00FF00), 3), {5, 6}, {100, 80})

	if !testing.expect_value(t, len(fake.ops), 1) {
		return
	}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[0].rect, Rect{5, 6, 10, 20})
	testing.expect_value(t, fake.ops[0].color, rgb(0x00FF00))
	testing.expect_value(t, fake.ops[0].radius, f32(3))
}

@(test)
image_context_helpers_dispatch_to_backend :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	defer delete(fake.ops)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	pixels := []u8{255, 0, 0, 255}

	img := image_load_pixels_ctx(&rc, "fake://pixel", 1, 1, pixels)
	testing.expect(t, rawptr(img) != nil)
	testing.expect_value(t, fake.image_load_name, "fake://pixel")
	testing.expect_value(t, fake.image_w, u32(1))
	testing.expect_value(t, fake.image_h, u32(1))
	testing.expect_value(t, fake.image_rgba_len, 4)

	updated := image_update_pixels_ctx(&rc, img, 1, 1, pixels)
	testing.expect_value(t, updated, true)
	testing.expect_value(t, fake.image_updated, true)

	draw_image_ctx(&rc, img, Rect{1, 2, 3, 4}, rgb(0xFFFFFF))
	if !testing.expect_value(t, len(fake.ops), 1) {
		return
	}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Image)
	testing.expect_value(t, fake.ops[0].rect, Rect{1, 2, 3, 4})
	testing.expect_value(t, fake.ops[0].fit, Image_Fit.Cover)

	image_unload_ctx(&rc, img)
}

@(test)
extended_image_context_helpers_dispatch_to_backend :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {64, 48}}
	defer delete(fake.ops)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	bytes := []byte{1, 2, 3, 4}

	img := image_load_bytes_ctx(&rc, "app://frame", bytes)
	testing.expect(t, rawptr(img) != nil)
	testing.expect_value(t, fake.image_load_name, "app://frame")
	testing.expect_value(t, fake.image_encoded_len, 4)

	size, ok := image_size_ctx(&rc, img)
	testing.expect_value(t, ok, true)
	testing.expect_value(t, size, [2]f32{64, 48})

	drawn := draw_image_region_ctx(
		&rc,
		img,
		Rect{1, 2, 3, 4},
		Rect{10, 20, 30, 40},
		rgba(0x80FFFFFF),
	)
	testing.expect_value(t, drawn, true)
	if !testing.expect_value(t, len(fake.ops), 1) {return}
	testing.expect_value(t, fake.ops[0].src, Rect{1, 2, 3, 4})
	testing.expect_value(t, fake.ops[0].rect, Rect{10, 20, 30, 40})
	testing.expect_value(t, fake.ops[0].color, rgba(0x80FFFFFF))
}

@(test)
optional_image_context_helpers_fail_without_backend_callbacks :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	backend := fake_backend(&fake)
	backend.images.load_bytes = nil
	backend.images.size = nil
	backend.images.draw_region = nil
	rc := render_context_from_backend(&backend)

	img := Backend_Image(rawptr(&fake))
	testing.expect(t, rawptr(image_load_bytes_ctx(&rc, "app://missing", []byte{1})) == nil)
	_, size_ok := image_size_ctx(&rc, img)
	testing.expect_value(t, size_ok, false)
	testing.expect_value(
		t,
		draw_image_region_ctx(&rc, img, Rect{0, 0, 1, 1}, Rect{0, 0, 1, 1}),
		false,
	)
}

@(test)
render_view_draws_image_through_backend_context :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	defer delete(fake.ops)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)

	render_view(
		&rc,
		View_Image {
			path = "fake://image",
			size = {20, 10},
			fit = .Contain,
			tint = rgba(0x80FFFFFF),
		},
		{5, 6},
		{100, 80},
	)

	if !testing.expect_value(t, len(fake.ops), 1) {
		return
	}
	testing.expect_value(t, fake.image_load_path, "fake://image")
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Image)
	testing.expect_value(t, fake.ops[0].rect, Rect{5, 6, 20, 10})
	testing.expect_value(t, fake.ops[0].fit, Image_Fit.Contain)
	testing.expect_value(t, fake.ops[0].color, rgba(0x80FFFFFF))
}

@(test)
image_builder_stores_optional_source_region :: proc(t: ^testing.T) {
	ctx: Ctx(int)
	src := Rect{32, 16, 64, 48}
	view := image(
		&ctx,
		"fake://atlas",
		width = 128,
		height = 96,
		fit = .Contain,
		tint = rgba(0x80FFFFFF),
		src = src,
	)

	#partial switch img in view {
	case View_Image:
		testing.expect_value(t, img.path, "fake://atlas")
		testing.expect_value(t, img.size, [2]f32{128, 96})
		testing.expect_value(t, img.fit, Image_Fit.Contain)
		testing.expect_value(t, img.tint, rgba(0x80FFFFFF))
		testing.expect_value(t, img.src, src)
	case:
		testing.expect(t, false)
	}
}

@(private)
expect_image_region_draw :: proc(t: ^testing.T, fit: Image_Fit, box, src, want_src, want_dst: Rect) {
	fake := Fake_Backend_State{image_native_size = {256, 128}}
	defer delete(fake.ops)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)

	render_view(
		&rc,
		View_Image {
			path = "fake://atlas",
			size = {box.w, box.h},
			fit = fit,
			tint = rgba(0x80FFFFFF),
			src = src,
		},
		{box.x, box.y},
		{box.w, box.h},
	)

	if !testing.expect_value(t, len(fake.ops), 3) {
		return
	}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Push_Clip)
	testing.expect_value(t, fake.ops[0].rect, box)
	testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Image)
	testing.expect_value(t, fake.ops[1].src, want_src)
	testing.expect_value(t, fake.ops[1].rect, want_dst)
	testing.expect_value(t, fake.ops[1].color, rgba(0x80FFFFFF))
	testing.expect_value(t, fake.ops[2].kind, Fake_Draw_Kind.Pop_Clip)
}

@(test)
render_view_draws_image_region_with_fill_fit :: proc(t: ^testing.T) {
	expect_image_region_draw(
		t,
		.Fill,
		{5, 6, 100, 80},
		{32, 16, 64, 48},
		{32, 16, 64, 48},
		{5, 6, 100, 80},
	)
}

@(test)
render_view_draws_image_region_with_none_fit :: proc(t: ^testing.T) {
	expect_image_region_draw(
		t,
		.None,
		{5, 6, 100, 80},
		{32, 16, 64, 48},
		{32, 16, 64, 48},
		{23, 22, 64, 48},
	)
}

@(test)
render_view_draws_image_region_with_contain_fit :: proc(t: ^testing.T) {
	expect_image_region_draw(
		t,
		.Contain,
		{5, 6, 100, 100},
		{32, 16, 64, 32},
		{32, 16, 64, 32},
		{5, 31, 100, 50},
	)
}

@(test)
render_view_draws_image_region_with_cover_fit :: proc(t: ^testing.T) {
	expect_image_region_draw(
		t,
		.Cover,
		{5, 6, 100, 100},
		{32, 16, 64, 32},
		{48, 16, 32, 32},
		{5, 6, 100, 100},
	)
}

@(test)
render_view_draws_placeholder_for_invalid_image_region :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {64, 64}}
	defer delete(fake.ops)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)

	render_view(
		&rc,
		View_Image {
			path = "fake://atlas",
			size = {20, 10},
			fit = .Fill,
			src = {63, 0, 2, 2},
		},
		{5, 6},
		{20, 10},
	)

	if !testing.expect_value(t, len(fake.ops), 1) {
		return
	}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[0].rect, Rect{5, 6, 20, 10})
	testing.expect_value(t, fake.ops[0].color, Color{1, 0, 1, 1})
}

@(test)
render_view_draws_placeholder_when_image_region_service_is_missing :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {64, 64}}
	defer delete(fake.ops)

	backend := fake_backend(&fake)
	backend.images.draw_region = nil
	rc := render_context_from_backend(&backend)

	render_view(
		&rc,
		View_Image {
			path = "fake://atlas",
			size = {20, 10},
			fit = .Fill,
			src = {0, 0, 2, 2},
		},
		{5, 6},
		{20, 10},
	)

	if !testing.expect_value(t, len(fake.ops), 1) {
		return
	}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[0].rect, Rect{5, 6, 20, 10})
	testing.expect_value(t, fake.ops[0].color, Color{1, 0, 1, 1})
}

@(test)
render_view_queues_overlay_on_render_context :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	defer delete(fake.ops)

	overlay_queue := make([dynamic]Overlay_Entry)
	defer delete(overlay_queue)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	rc.frame_size = {200, 100}
	rc.overlays = &overlay_queue

	render_view(
		&rc,
		overlay({x = 180, y = 10, w = 16, h = 20}, rect({40, 12}, rgb(0x00FF00))),
		{0, 0},
		{200, 100},
	)

	if !testing.expect_value(t, len(overlay_queue), 1) {
		return
	}
	testing.expect_value(t, overlay_queue[0].origin, [2]f32{160, 30})
	testing.expect_value(t, overlay_queue[0].size, [2]f32{40, 12})
	testing.expect_value(t, overlay_queue[0].shadow_radius, f32(8))
}

@(test)
render_view_queues_overlay_shadow_radius_from_call_site :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	defer delete(fake.ops)

	overlay_queue := make([dynamic]Overlay_Entry)
	defer delete(overlay_queue)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	rc.frame_size = {200, 100}
	rc.overlays = &overlay_queue

	render_view(
		&rc,
		overlay(
			{x = 20, y = 10, w = 16, h = 20},
			rect({40, 12}, rgb(0x00FF00)),
			shadow_radius = 3,
		),
		{0, 0},
		{200, 100},
	)

	if !testing.expect_value(t, len(overlay_queue), 1) {
		return
	}
	testing.expect_value(t, overlay_queue[0].shadow_radius, f32(3))
}

@(test)
render_overlays_uses_context_queue_and_restores_alpha :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	defer delete(fake.ops)

	overlay_queue := make([dynamic]Overlay_Entry)
	defer delete(overlay_queue)

	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	rc.overlays = &overlay_queue
	rc.alpha_multiplier = 0.5
	append(
		rc.overlays,
		Overlay_Entry {
			origin = {10, 20},
			size = {30, 40},
			child = rect({30, 40}, rgb(0x00FF00)),
			opacity = 0.25,
		},
	)

	render_overlays(&rc)

	if !testing.expect_value(t, rc.alpha_multiplier, f32(0.5)) {
		return
	}
	if !testing.expect_value(t, len(fake.ops), 3) {
		return
	}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Set_Alpha)
	testing.expect_value(t, fake.ops[0].alpha, f32(0.125))
	testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[1].rect, Rect{10, 20, 30, 40})
	testing.expect_value(t, fake.ops[2].kind, Fake_Draw_Kind.Set_Alpha)
	testing.expect_value(t, fake.ops[2].alpha, f32(0.5))
}

@(test)
render_context_can_hold_existing_renderer_pointer :: proc(t: ^testing.T) {
	r: Renderer
	backend := renderer_backend(&r)
	rc := render_context_from_backend(&backend)
	testing.expect(t, rc.backend.state == &r)
}

@(test)
render_context_carries_scale :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	testing.expect_value(t, rc.scale, f32(1))

	r: Renderer
	target: Window_Target
	r.cur = &target
	r.scale = 1.75
	renderer_backend := renderer_backend(&r)
	renderer_context := renderer_render_context(&renderer_backend, &r)
	testing.expect_value(t, renderer_context.scale, f32(1.75))
}

@(test)
renderer_backend_advertises_only_wired_capabilities :: proc(t: ^testing.T) {
	r: Renderer
	backend := renderer_backend(&r)

	testing.expect_value(t, backend.capabilities, Backend_Capabilities{})
}

@(test)
renderer_backend_set_alpha_updates_renderer :: proc(t: ^testing.T) {
	r: Renderer
	target: Window_Target
	r.cur = &target
	backend := renderer_backend(&r)

	backend.draw.set_alpha(backend.state, 0.35)

	testing.expect_value(t, r.alpha_multiplier, f32(0.35))
}

@(test)
render_context_draw_facades_append_to_renderer_batch :: proc(t: ^testing.T) {
	r: Renderer
	target: Window_Target
	r.cur = &target
	defer delete(target.batch.vertices)
	defer delete(target.batch.indices)

	backend := renderer_backend(&r)
	rc := render_context_from_backend(&backend)

	draw_rect(&rc, {x = 10, y = 20, w = 30, h = 40}, rgb(0xFF0000), 4)
	draw_gradient_rect(
		&rc,
		{x = 0, y = 0, w = 8, h = 8},
		rgb(0xFFFFFF),
		rgb(0xFF0000),
		rgb(0x000000),
		rgb(0x0000FF),
	)
	draw_shadow(&rc, {x = 5, y = 5, w = 10, h = 10}, 2, 4, rgba(0x00000080))

	testing.expect_value(t, len(target.batch.vertices), 12)
	testing.expect_value(t, len(target.batch.indices), 18)
}

@(test)
render_context_clip_facades_update_renderer_batch :: proc(t: ^testing.T) {
	r: Renderer
	target: Window_Target
	r.cur = &target
	target.fb_size = {200, 100}
	target.fb_size_px = {200, 100}
	target.scale = 1
	defer delete(target.batch.clip_stack)
	defer delete(target.batch.ranges)

	backend := renderer_backend(&r)
	rc := render_context_from_backend(&backend)

	push_clip(&rc, {x = 10, y = 20, w = 30, h = 40})

	if !testing.expect_value(t, len(target.batch.clip_stack), 1) {
		return
	}
	testing.expect_value(t, target.batch.clip_stack[0], Rect{10, 20, 30, 40})
	testing.expect_value(t, len(target.batch.ranges), 1)

	pop_clip(&rc)

	testing.expect_value(t, len(target.batch.clip_stack), 0)
	testing.expect_value(t, len(target.batch.ranges), 1)
	testing.expect_value(t, target.batch.ranges[0].clip, [4]u32{0, 0, 200, 100})
}

@(test)
capture_mouse_when_pointer_over_widget :: proc(t: ^testing.T) {
	input := Input {
		mouse_pos = {12, 16},
	}
	capture := input_capture_from_frame(
		input,
		Capture_Frame_State{pointer_regions = []Rect{{x = 10, y = 10, w = 80, h = 20}}},
	)

	testing.expect_value(t, capture.pointer_over_ui, true)
	testing.expect_value(t, capture.mouse, true)
	testing.expect_value(t, capture.keyboard, false)
}

@(test)
capture_mouse_when_pointer_over_current_overlay_rect :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	append(&ws.overlay_rects, Rect{x = 10, y = 10, w = 80, h = 20})

	input := Input{mouse_pos = {12, 16}}
	frame := capture_frame_from_widgets(&ws)
	capture := input_capture_from_frame(input, frame)

	testing.expect_value(t, capture.pointer_over_ui, true)
	testing.expect_value(t, capture.mouse, true)
}

@(test)
capture_mouse_when_pointer_over_previous_overlay_rect :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	append(&ws.overlay_rects, Rect{x = 10, y = 10, w = 80, h = 20})
	widget_store_frame_reset(&ws)

	input := Input{mouse_pos = {12, 16}}
	frame := capture_frame_from_previous_widgets(&ws, false)
	capture := input_capture_from_frame(input, frame)

	testing.expect_value(t, capture.pointer_over_ui, true)
	testing.expect_value(t, capture.mouse, true)
}

@(test)
capture_keyboard_when_text_focused :: proc(t: ^testing.T) {
	capture := input_capture_from_frame(Input{}, Capture_Frame_State{wants_text_input = true})

	testing.expect_value(t, capture.keyboard, true)
	testing.expect_value(t, capture.text, true)
}

@(test)
do_not_capture_empty_frame :: proc(t: ^testing.T) {
	capture := input_capture_from_frame(Input{}, Capture_Frame_State{})

	testing.expect_value(t, capture.mouse, false)
	testing.expect_value(t, capture.keyboard, false)
	testing.expect_value(t, capture.text, false)
	testing.expect_value(t, capture.wheel, false)
	testing.expect_value(t, capture.pointer_over_ui, false)
}

@(test)
outside_press_blurs_focused_button_before_capture :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	id := Widget_ID(1)
	ws.focused_id = id
	ws.states[id] = Widget_State {
		kind       = .Button,
		last_rect  = {x = 10, y = 10, w = 80, h = 24},
		last_frame = ws.frame,
	}

	input := Input{mouse_pos = {200, 200}}
	input.mouse_pressed[.Left] = true

	widget_store_frame_reset(&ws)
	widget_store_blur_on_outside_press(&ws, input)
	frame := capture_frame_from_widgets(&ws)
	capture := input_capture_from_frame(input, frame)

	testing.expect_value(t, ws.focused_id, Widget_ID(0))
	testing.expect_value(t, capture.keyboard, false)
}

@(test)
previous_frame_capture_survives_widget_store_reset :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	id := Widget_ID(1)
	ws.focused_id = id
	ws.wants_text_input = true
	ws.states[id] = Widget_State {
		kind       = .Text_Input,
		last_rect  = {x = 10, y = 10, w = 80, h = 24},
		last_frame = ws.frame,
	}
	append(&ws.scroll_rects, Scroll_Rect{id = id, rect = {x = 10, y = 10, w = 80, h = 24}})
	ws.modal_rect = {x = 4, y = 4, w = 120, h = 80}

	input := Input{mouse_pos = {12, 16}}
	prev_wants_text_input := ws.wants_text_input

	widget_store_frame_reset(&ws)
	widget_store_blur_on_outside_press(&ws, input)

	frame := capture_frame_from_previous_widgets(&ws, prev_wants_text_input)
	capture := input_capture_from_frame(input, frame)

	testing.expect_value(t, capture.pointer_over_ui, true)
	testing.expect_value(t, capture.mouse, true)
	testing.expect_value(t, capture.keyboard, true)
	testing.expect_value(t, capture.text, true)
	testing.expect_value(t, capture.wheel, true)
}

@(test)
previous_frame_capture_respects_outside_press_blur :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	id := Widget_ID(1)
	ws.focused_id = id
	ws.wants_text_input = true
	ws.states[id] = Widget_State {
		kind       = .Text_Input,
		last_rect  = {x = 10, y = 10, w = 80, h = 24},
		last_frame = ws.frame,
	}

	input := Input{mouse_pos = {200, 200}}
	input.mouse_pressed[.Left] = true
	prev_wants_text_input := ws.wants_text_input

	widget_store_frame_reset(&ws)
	widget_store_blur_on_outside_press(&ws, input)

	frame := capture_frame_from_previous_widgets(&ws, prev_wants_text_input)
	capture := input_capture_from_frame(input, frame)

	testing.expect_value(t, ws.focused_id, Widget_ID(0))
	testing.expect_value(t, capture.keyboard, false)
	testing.expect_value(t, capture.text, false)
}

@(test)
press_inside_overlay_keeps_focused_owner :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	id := Widget_ID(1)
	ws.focused_id = id
	ws.states[id] = Widget_State {
		kind       = .Select,
		last_rect  = {x = 10, y = 10, w = 120, h = 28},
		last_frame = ws.frame,
	}
	append(&ws.overlay_rects, Rect{x = 10, y = 42, w = 120, h = 90})

	input := Input{mouse_pos = {20, 60}}
	input.mouse_pressed[.Left] = true

	widget_store_frame_reset(&ws)
	widget_store_blur_on_outside_press(&ws, input)

	testing.expect_value(t, ws.focused_id, id)
}

@(test)
public_image_helpers_use_render_context :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {64, 48}}
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	testing.expect_value(t, image_load_bytes(&ctx, "app://frame", []byte{1, 2, 3}), true)
	size, ok := image_size(&ctx, "app://frame")
	testing.expect_value(t, ok, true)
	testing.expect_value(t, size, [2]f32{64, 48})
}

@(test)
image_background_intrinsic_size_matches_child :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	v := image_background(&ctx, "app://paper", rect({20, 10}, rgb(0xFFFFFF)))
	testing.expect_value(t, view_size(&rc, v), [2]f32{20, 10})
}

@(test)
nine_slice_intrinsic_size_adds_asymmetric_decoration_extents :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	slice := Nine_Slice{
		top_left     = {0, 0, 3, 5},
		top          = {3, 0, 4, 7},
		top_right    = {7, 0, 8, 4},
		left         = {0, 5, 6, 3},
		right        = {9, 4, 2, 9},
		bottom_left  = {0, 8, 4, 10},
		bottom       = {4, 9, 3, 2},
		bottom_right = {7, 9, 5, 6},
	}
	v := nine_slice_background(&ctx, "app://frame", slice, rect({20, 10}, rgb(0xFFFFFF)))
	testing.expect_value(t, view_size(&rc, v), [2]f32{34, 27})
}

@(test)
nine_slice_extents_ignore_regions_with_an_empty_axis :: proc(t: ^testing.T) {
	slice := Nine_Slice{
		top_left     = {0, 0, 0, 5},
		top          = {0, 0, 4, 0},
		top_right    = {0, 0, 8, 0},
		left         = {0, 0, 0, 6},
		right        = {0, 0, 0, 9},
		bottom_left  = {0, 0, 7, 0},
		bottom       = {0, 0, 0, 11},
		bottom_right = {0, 0, 12, 0},
	}

	testing.expect_value(t, nine_slice_extents(slice), Nine_Slice_Extents{})
}

@(test)
image_background_draws_before_child_inside_wrapper_clip :: proc(t: ^testing.T) {
	fake: Fake_Backend_State
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	v := image_background(
		&ctx,
		"app://paper",
		rect({0, 0}, rgb(0x00FF00)),
		fit = .Contain,
		tint = rgba(0x80FFFFFF),
	)
	render_view(&rc, v, {5, 6}, {30, 40})

	if !testing.expect_value(t, len(fake.ops), 4) {return}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Push_Clip)
	testing.expect_value(t, fake.ops[0].rect, Rect{5, 6, 30, 40})
	testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Image)
	testing.expect_value(t, fake.ops[1].fit, Image_Fit.Contain)
	testing.expect_value(t, fake.ops[1].color, rgba(0x80FFFFFF))
	testing.expect_value(t, fake.ops[2].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[2].rect, Rect{5, 6, 30, 40})
	testing.expect_value(t, fake.ops[3].kind, Fake_Draw_Kind.Pop_Clip)
}

@(test)
nine_slice_background_tiles_partial_top_edge_and_places_child_in_conservative_interior :: proc(
	t: ^testing.T,
) {
	fake := Fake_Backend_State{image_native_size = {32, 32}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	slice := Nine_Slice{
		top_left  = {0, 0, 3, 4},
		top       = {3, 0, 4, 2},
		top_right = {7, 0, 5, 6},
		left      = {0, 4, 2, 3},
	}
	v := nine_slice_background(&ctx, "app://frame", slice, rect({0, 0}, rgb(0x00FF00)))
	render_view(&rc, v, {10, 20}, {19, 16})

	testing.expect_value(t, fake.ops[1].src, Rect{0, 0, 3, 4})
	testing.expect_value(t, fake.ops[1].rect, Rect{10, 20, 3, 4})
	testing.expect_value(t, fake.ops[2].src, Rect{7, 0, 5, 6})
	testing.expect_value(t, fake.ops[2].rect, Rect{24, 20, 5, 6})

	// Available top span is 19 - 3 - 5 = 11, so tile widths are 4 + 4 + 3.
	testing.expect_value(t, fake.ops[3].src, Rect{3, 0, 4, 2})
	testing.expect_value(t, fake.ops[3].rect, Rect{13, 20, 4, 2})
	testing.expect_value(t, fake.ops[4].src, Rect{3, 0, 4, 2})
	testing.expect_value(t, fake.ops[4].rect, Rect{17, 20, 4, 2})
	testing.expect_value(t, fake.ops[5].src, Rect{3, 0, 3, 2})
	testing.expect_value(t, fake.ops[5].rect, Rect{21, 20, 3, 2})

	// Conservative extents: left=max(3,2,0), top=max(4,2,6).
	// Child receives x=13, y=26, w=11, h=10.
	testing.expect_value(t, fake.ops[len(fake.ops) - 2].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[len(fake.ops) - 2].rect, Rect{13, 26, 11, 10})
}

@(test)
nine_slice_background_tiles_center_with_partial_column_and_row :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {16, 16}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	slice := Nine_Slice{center = {4, 5, 3, 2}}
	v := nine_slice_background(&ctx, "app://center", slice, spacer(0))
	render_view(&rc, v, {0, 0}, {8, 5})

	// 3 + 3 + 2 columns crossed with 2 + 2 + 1 rows.
	testing.expect_value(t, len(fake.ops), 11)
	testing.expect_value(t, fake.ops[9].src, Rect{4, 5, 2, 1})
	testing.expect_value(t, fake.ops[9].rect, Rect{6, 4, 2, 1})
}

@(test)
nine_slice_background_draws_placeholder_when_region_service_is_missing :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {16, 16}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	backend.images.draw_region = nil
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	slice := Nine_Slice{top_left = {0, 0, 4, 4}}
	v := nine_slice_background(&ctx, "app://frame", slice, rect({0, 0}, rgb(0x00FF00)))
	render_view(&rc, v, {1, 2}, {20, 12})

	if !testing.expect_value(t, len(fake.ops), 4) {return}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Push_Clip)
	testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[1].rect, Rect{1, 2, 20, 12})
	testing.expect_value(t, fake.ops[1].color, Color{1, 0, 1, 1})
	testing.expect_value(t, fake.ops[2].rect, Rect{5, 6, 16, 8})
	testing.expect_value(t, fake.ops[3].kind, Fake_Draw_Kind.Pop_Clip)
}

@(test)
nine_slice_background_draws_placeholder_for_out_of_bounds_source :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {8, 8}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	slice := Nine_Slice{top_left = {7, 7, 2, 2}}
	v := nine_slice_background(&ctx, "app://invalid", slice, spacer(0))
	render_view(&rc, v, {0, 0}, {12, 12})

	testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[1].color, Color{1, 0, 1, 1})
}

@(test)
nine_slice_background_clamps_child_when_destination_is_too_small :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {16, 16}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	slice := Nine_Slice{
		top_left = {0, 0, 6, 7},
		top_right = {6, 0, 6, 7},
		bottom_left = {0, 7, 6, 7},
		bottom_right = {6, 7, 6, 7},
	}
	v := nine_slice_background(&ctx, "app://tight", slice, rect({0, 0}, rgb(0x00FF00)))
	render_view(&rc, v, {10, 20}, {8, 8})

	testing.expect_value(t, fake.ops[len(fake.ops) - 2].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[len(fake.ops) - 2].rect, Rect{16, 27, 0, 0})
}

@(test)
nine_slice_background_allows_corner_only_frames :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {16, 16}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	slice := Nine_Slice{
		top_left = {0, 0, 3, 4},
		bottom_right = {4, 5, 6, 7},
	}
	v := nine_slice_background(&ctx, "app://corners", slice, spacer(0))
	render_view(&rc, v, {10, 20}, {30, 40})

	if !testing.expect_value(t, len(fake.ops), 4) {return}
	testing.expect_value(t, fake.ops[1].src, Rect{0, 0, 3, 4})
	testing.expect_value(t, fake.ops[1].rect, Rect{10, 20, 3, 4})
	testing.expect_value(t, fake.ops[2].src, Rect{4, 5, 6, 7})
	testing.expect_value(t, fake.ops[2].rect, Rect{34, 53, 6, 7})
}

@(test)
nine_slice_background_empty_corner_does_not_consume_border_span :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {16, 16}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)
	ctx := Ctx(int){render = &rc}

	slice := Nine_Slice{
		top_left  = {0, 0, 5, 0},
		top       = {0, 0, 3, 2},
		top_right = {0, 0, 4, 0},
	}
	v := nine_slice_background(&ctx, "app://empty-corners", slice, spacer(0))
	render_view(&rc, v, {0, 0}, {8, 4})

	if !testing.expect_value(t, len(fake.ops), 5) {return}
	testing.expect_value(t, fake.ops[1].src, Rect{0, 0, 3, 2})
	testing.expect_value(t, fake.ops[1].rect, Rect{0, 0, 3, 2})
	testing.expect_value(t, fake.ops[3].src, Rect{0, 0, 2, 2})
	testing.expect_value(t, fake.ops[3].rect, Rect{6, 0, 2, 2})
}
