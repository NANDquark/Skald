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
