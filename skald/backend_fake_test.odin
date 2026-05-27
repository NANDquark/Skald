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
	color:  Color,
	radius: f32,
	alpha:  f32,
	image:  Backend_Image,
	fit:    Image_Fit,
}

Fake_Backend_State :: struct {
	ops:             [dynamic]Fake_Draw_Op,
	image_load_path: string,
	image_load_name: string,
	image_w:         u32,
	image_h:         u32,
	image_rgba_len:  int,
	image_updated:   bool,
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
			load_pixels = fake_image_load_pixels,
			update_pixels = fake_image_update_pixels,
			unload = fake_image_unload,
			draw = fake_image_draw,
			draw_fit = fake_image_draw_fit,
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
