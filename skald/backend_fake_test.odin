package skald

import "core:testing"

Fake_Draw_Kind :: enum {
	Rect,
	Push_Clip,
	Pop_Clip,
}

Fake_Draw_Op :: struct {
	kind:   Fake_Draw_Kind,
	rect:   Rect,
	color:  Color,
	radius: f32,
}

Fake_Backend_State :: struct {
	ops: [dynamic]Fake_Draw_Op,
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

fake_backend :: proc(state: ^Fake_Backend_State) -> Backend {
	return Backend {
		state = state,
		draw = Backend_Draw {
			rect = fake_draw_rect,
			push_clip = fake_push_clip,
			pop_clip = fake_pop_clip,
		},
	}
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
render_context_can_hold_existing_renderer_pointer :: proc(t: ^testing.T) {
	r: Renderer
	backend := renderer_backend(&r)
	rc := render_context_from_backend(&backend)
	testing.expect(t, rc.backend.state == &r)
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
