package skald

Capture_Frame_State :: struct {
	pointer_regions:  []Rect,
	scroll_regions:   []Rect,
	modal_open:       bool,
	drag_active:      bool,
	press_owned:      bool,
	wants_keyboard:   bool,
	wants_text_input: bool,
	shortcut_matched: bool,
}

input_capture_from_frame :: proc(input: Input, frame: Capture_Frame_State) -> Input_Capture {
	over_ui := false
	for r in frame.pointer_regions {
		if rect_contains_point(r, input.mouse_pos) {
			over_ui = true
			break
		}
	}

	over_scroll := false
	for r in frame.scroll_regions {
		if rect_contains_point(r, input.mouse_pos) {
			over_scroll = true
			break
		}
	}

	mouse := over_ui || frame.modal_open || frame.drag_active || frame.press_owned
	keyboard := frame.wants_keyboard || frame.wants_text_input || frame.modal_open || frame.shortcut_matched
	text := frame.wants_text_input
	wheel := over_scroll || frame.modal_open

	return Input_Capture {
		mouse           = mouse,
		keyboard        = keyboard,
		text            = text,
		wheel           = wheel,
		pointer_over_ui = over_ui,
	}
}

capture_frame_from_widgets :: proc(widgets: ^Widget_Store) -> Capture_Frame_State {
	if widgets == nil {return {}}

	pointer_regions := make(
		[dynamic]Rect,
		0,
		len(widgets.states) + len(widgets.overlay_rects),
		context.temp_allocator,
	)
	press_owned := false
	for _, st in widgets.states {
		if st.last_frame != widgets.frame {continue}
		if st.last_rect.w <= 0 || st.last_rect.h <= 0 {continue}
		append(&pointer_regions, st.last_rect)
		press_owned = press_owned || st.pressed || st.mouse_selecting
	}
	for r in widgets.overlay_rects {
		if r.w <= 0 || r.h <= 0 {continue}
		append(&pointer_regions, r)
	}

	scroll_regions := make([dynamic]Rect, 0, len(widgets.scroll_rects), context.temp_allocator)
	for sr in widgets.scroll_rects {
		if sr.rect.w <= 0 || sr.rect.h <= 0 {continue}
		append(&scroll_regions, sr.rect)
	}

	modal_open := widgets.modal_rect.w > 0 && widgets.modal_rect.h > 0

	return Capture_Frame_State {
		pointer_regions = pointer_regions[:],
		scroll_regions = scroll_regions[:],
		modal_open = modal_open,
		drag_active = press_owned,
		press_owned = press_owned,
		wants_keyboard = widgets.focused_id != 0,
		wants_text_input = widgets.wants_text_input,
	}
}

capture_frame_from_previous_widgets :: proc(
	widgets: ^Widget_Store,
	prev_wants_text_input: bool,
) -> Capture_Frame_State {
	if widgets == nil {return {}}

	pointer_regions := make(
		[dynamic]Rect,
		0,
		len(widgets.states) + len(widgets.overlay_rects_prev),
		context.temp_allocator,
	)
	press_owned := false
	for _, st in widgets.states {
		if st.last_frame + 1 != widgets.frame {continue}
		if st.last_rect.w <= 0 || st.last_rect.h <= 0 {continue}
		append(&pointer_regions, st.last_rect)
		press_owned = press_owned || st.pressed || st.mouse_selecting
	}
	for r in widgets.overlay_rects_prev {
		if r.w <= 0 || r.h <= 0 {continue}
		append(&pointer_regions, r)
	}

	scroll_regions := make([dynamic]Rect, 0, len(widgets.scroll_rects_prev), context.temp_allocator)
	for sr in widgets.scroll_rects_prev {
		if sr.rect.w <= 0 || sr.rect.h <= 0 {continue}
		append(&scroll_regions, sr.rect)
	}

	modal_open := widgets.modal_rect_prev.w > 0 && widgets.modal_rect_prev.h > 0
	wants_keyboard := widgets.focused_id != 0
	wants_text_input := prev_wants_text_input && wants_keyboard

	return Capture_Frame_State {
		pointer_regions = pointer_regions[:],
		scroll_regions = scroll_regions[:],
		modal_open = modal_open,
		drag_active = press_owned,
		press_owned = press_owned,
		wants_keyboard = wants_keyboard,
		wants_text_input = wants_text_input,
	}
}
