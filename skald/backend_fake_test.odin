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
