# Karl2D Gamepad Widget Navigation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Karl2D-backed gamepad navigation for Skald widgets using spatial focus movement, focused-widget internal handling, gamepad shortcuts, and gamepad capture.

**Architecture:** `skald_karl2d` translates Karl2D gamepad 0 into a backend-neutral `Input.gamepad_nav` snapshot. Skald core owns focus policy: previous-frame focusables support spatial movement before view construction, focused composite widgets can keep direction input for internal behavior, and registered gamepad shortcuts participate in capture without making static UI focusable. The SDL3/Vulkan backend remains unchanged except for compiling with the new zero-value input/capture fields.

**Tech Stack:** Odin, Skald core package, Karl2D embedded backend, existing `odin test`, `odin check`, and `build.sh` verification.

---

## Execution Progress

Updated: 2026-05-29 after the first implementation attempt was paused by the
user.

- Design committed:
  - `6811647` — `docs: design karl2d gamepad widget navigation`
- Plan committed:
  - `2e24787` — `docs: plan karl2d gamepad widget navigation`
- Baseline before implementation passed:
  - `odin test ./skald -collection:gui=. -define:SKALD_RUNA=false`
    passed with 22 tests.
  - `odin check ./skald_karl2d -collection:gui=. -no-entry-point`
    passed.
- Task 1 was dispatched to a worker, then the user paused the run before the
  worker returned. The worker was shut down while still running.
- No implementation task has been completed, reviewed, or committed.
- Current uncommitted implementation state:
  - `skald/backend_fake_test.odin` has Task 1 Step 1's three failing gamepad
    capture tests inserted after `do_not_capture_empty_frame`.
  - `skald/input.odin`, `skald/backend.odin`, and `skald/input_capture.odin`
    have not been updated yet.

Resume from here:

1. Continue Task 1 at Step 2 by running
   `odin test ./skald -collection:gui=. -define:SKALD_RUNA=false`.
2. Expected result: failure from undefined gamepad input/capture fields.
3. Complete Task 1 Steps 3-6.
4. Run the required spec-compliance and code-quality reviews for Task 1 before
   moving to Task 2.

---

## File Structure

- Modify `skald/input.odin`: add `Gamepad_Nav_*` types and reset edge fields.
- Modify `skald/backend.odin`: add `gamepad` to `Input_Capture`.
- Modify `skald/input_capture.odin`: compute gamepad capture from focus/modal state, consumed nav, and shortcut registrations.
- Modify `skald/widget.odin`: add gamepad shortcut storage, spatial focus helper, pre-view gamepad navigation preprocessor, and gamepad nav helper procs.
- Modify `skald/shortcut.odin`: add `Gamepad_Chord`, `gamepad_shortcut`, and helper formatting/matching procs.
- Modify `skald/backend_fake_test.odin`: add backend-neutral tests for gamepad nav, capture, and shortcuts.
- Modify `skald_karl2d/backend.odin`: add gamepad navigation state to `Backend_State` and advertise `Gamepad_Navigation`.
- Modify `skald_karl2d/input.odin`: translate Karl2D gamepad 0 into `Input.gamepad_nav`.
- Modify `skald_karl2d/embedded.odin`: run the pre-view gamepad navigation pass in `begin_frame`.
- Modify `examples/50_karl2d_overlay/main.odin`: demonstrate spatial gamepad UI navigation and gate gameplay gamepad input with `capture.gamepad`.
- Modify `docs/examples.md`: mention gamepad navigation in the overlay example description.

---

### Task 1: Core Gamepad Input And Capture Shape

**Files:**
- Modify: `skald/input.odin`
- Modify: `skald/backend.odin`
- Modify: `skald/input_capture.odin`
- Modify: `skald/backend_fake_test.odin`

- [ ] **Step 1: Write failing capture tests**

Append these tests to `skald/backend_fake_test.odin` after `do_not_capture_empty_frame`:

```odin
@(test)
capture_gamepad_when_focused_widget_receives_nav :: proc(t: ^testing.T) {
	input := Input{}
	input.gamepad_nav.active = true
	input.gamepad_nav.dir_pressed = {.Down}

	capture := input_capture_from_frame(
		input,
		Capture_Frame_State{wants_keyboard = true},
	)

	testing.expect_value(t, capture.gamepad, true)
}

@(test)
do_not_capture_gamepad_for_static_ui_without_focus_or_shortcut :: proc(t: ^testing.T) {
	input := Input{}
	input.gamepad_nav.active = true
	input.gamepad_nav.dir_pressed = {.Down}

	capture := input_capture_from_frame(
		input,
		Capture_Frame_State{
			pointer_regions = []Rect{{x = 10, y = 10, w = 80, h = 24}},
		},
	)

	testing.expect_value(t, capture.mouse, false)
	testing.expect_value(t, capture.gamepad, false)
}

@(test)
capture_gamepad_when_modal_open_and_nav_active :: proc(t: ^testing.T) {
	input := Input{}
	input.gamepad_nav.active = true
	input.gamepad_nav.buttons_pressed = {.Cancel}

	capture := input_capture_from_frame(input, Capture_Frame_State{modal_open = true})

	testing.expect_value(t, capture.gamepad, true)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL with undefined identifiers for `gamepad_nav` or `capture.gamepad`.

- [ ] **Step 3: Add gamepad nav types to `skald/input.odin`**

Add these definitions after `Modifiers`:

```odin
Gamepad_Nav_Direction :: enum u8 {
	Up,
	Down,
	Left,
	Right,
}

Gamepad_Nav_Directions :: bit_set[Gamepad_Nav_Direction]

Gamepad_Nav_Button :: enum u8 {
	Accept,
	Cancel,
	Menu,
}

Gamepad_Nav_Buttons :: bit_set[Gamepad_Nav_Button]

Gamepad_Nav :: struct {
	active: bool,

	dir_pressed:     Gamepad_Nav_Directions,
	dir_down:        Gamepad_Nav_Directions,
	buttons_pressed: Gamepad_Nav_Buttons,
	buttons_down:    Gamepad_Nav_Buttons,
}
```

Add this field to `Input` after `modifiers`:

```odin
	gamepad_nav:     Gamepad_Nav,
```

Update `input_reset_edges` with:

```odin
	in_.gamepad_nav.dir_pressed = {}
	in_.gamepad_nav.buttons_pressed = {}
```

- [ ] **Step 4: Add gamepad capture fields**

In `skald/backend.odin`, add `gamepad` before `pointer_over_ui`:

```odin
Input_Capture :: struct {
	mouse:           bool,
	keyboard:        bool,
	text:            bool,
	wheel:           bool,
	gamepad:         bool,
	pointer_over_ui: bool,
}
```

In `skald/input_capture.odin`, add fields to `Capture_Frame_State`:

```odin
	gamepad_nav_consumed: bool,
	gamepad_shortcut_matched: bool,
```

Update `input_capture_from_frame`:

```odin
	gamepad_nav_active := input.gamepad_nav.active &&
		(input.gamepad_nav.dir_pressed != {} || input.gamepad_nav.buttons_pressed != {})
	gamepad := frame.gamepad_nav_consumed ||
		frame.gamepad_shortcut_matched ||
		((frame.wants_keyboard || frame.modal_open) && gamepad_nav_active)

	return Input_Capture {
		mouse           = mouse,
		keyboard        = keyboard,
		text            = text,
		wheel           = wheel,
		gamepad         = gamepad,
		pointer_over_ui = over_ui,
	}
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add skald/input.odin skald/backend.odin skald/input_capture.odin skald/backend_fake_test.odin
git commit -m "feat: add gamepad nav input capture shape"
```

---

### Task 2: Spatial Focus Resolver

**Files:**
- Modify: `skald/widget.odin`
- Modify: `skald/backend_fake_test.odin`

- [ ] **Step 1: Write failing spatial focus tests**

Append these tests to `skald/backend_fake_test.odin`:

```odin
make_focus_state_for_test :: proc(
	ws: ^Widget_Store,
	id: Widget_ID,
	rect: Rect,
	kind: Widget_Kind = .Button,
) {
	ws.states[id] = Widget_State{
		kind = kind,
		last_rect = rect,
		last_frame = ws.frame,
	}
	append(&ws.focusables, Focusable_Entry{id = id})
}

@(test)
spatial_focus_moves_to_nearest_widget_in_direction :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	center := Widget_ID(1)
	right_near := Widget_ID(2)
	right_far := Widget_ID(3)
	down := Widget_ID(4)

	make_focus_state_for_test(&ws, center, {x = 50, y = 50, w = 20, h = 20})
	make_focus_state_for_test(&ws, right_near, {x = 90, y = 50, w = 20, h = 20})
	make_focus_state_for_test(&ws, right_far, {x = 160, y = 45, w = 20, h = 20})
	make_focus_state_for_test(&ws, down, {x = 50, y = 100, w = 20, h = 20})
	ws.focused_id = center

	widget_spatial_focus(&ws, .Right)

	testing.expect_value(t, ws.focused_id, right_near)
}

@(test)
spatial_focus_does_not_wrap_when_no_candidate_exists :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	id := Widget_ID(1)
	make_focus_state_for_test(&ws, id, {x = 50, y = 50, w = 20, h = 20})
	ws.focused_id = id

	widget_spatial_focus(&ws, .Left)

	testing.expect_value(t, ws.focused_id, id)
}

@(test)
spatial_focus_respects_modal_rect :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	center := Widget_ID(1)
	inside := Widget_ID(2)
	outside := Widget_ID(3)
	make_focus_state_for_test(&ws, center, {x = 20, y = 20, w = 20, h = 20})
	make_focus_state_for_test(&ws, inside, {x = 70, y = 20, w = 20, h = 20})
	make_focus_state_for_test(&ws, outside, {x = 130, y = 20, w = 20, h = 20})
	ws.focused_id = center
	ws.modal_rect = {x = 0, y = 0, w = 110, h = 80}

	widget_spatial_focus(&ws, .Right)

	testing.expect_value(t, ws.focused_id, inside)
}

@(test)
spatial_focus_without_current_focus_picks_first_visible_target :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	top_left := Widget_ID(1)
	bottom_right := Widget_ID(2)
	make_focus_state_for_test(&ws, bottom_right, {x = 200, y = 200, w = 20, h = 20})
	make_focus_state_for_test(&ws, top_left, {x = 10, y = 10, w = 20, h = 20})

	widget_spatial_focus(&ws, .Down)

	testing.expect_value(t, ws.focused_id, top_left)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL with undefined identifier `widget_spatial_focus`.

- [ ] **Step 3: Implement spatial focus in `skald/widget.odin`**

Add these helpers after `widget_advance_focus`:

```odin
widget_spatial_focus :: proc(ws: ^Widget_Store, dir: Gamepad_Nav_Direction) -> bool {
	if ws == nil || len(ws.focusables) == 0 { return false }

	cur_rect: Rect
	have_current := false
	if ws.focused_id != 0 {
		if st, ok := ws.states[ws.focused_id]; ok {
			if widget_spatial_rect_valid(ws, st.last_rect, st.last_frame) {
				cur_rect = st.last_rect
				have_current = true
			}
		}
	}

	if !have_current {
		return widget_spatial_focus_first(ws, dir)
	}

	cx := cur_rect.x + cur_rect.w / 2
	cy := cur_rect.y + cur_rect.h / 2

	best_id := Widget_ID(0)
	best_score := f32(3.4e38)
	for entry in ws.focusables {
		if entry.id == ws.focused_id { continue }
		st, ok := ws.states[entry.id]
		if !ok || !widget_spatial_rect_valid(ws, st.last_rect, st.last_frame) { continue }
		if !widget_spatial_inside_modal(ws, st.last_rect) { continue }

		r := st.last_rect
		tx := r.x + r.w / 2
		ty := r.y + r.h / 2
		dx := tx - cx
		dy := ty - cy

		primary, cross: f32
		switch dir {
		case .Up:
			if dy >= 0 { continue }
			primary = -dy
			cross = abs(dx)
		case .Down:
			if dy <= 0 { continue }
			primary = dy
			cross = abs(dx)
		case .Left:
			if dx >= 0 { continue }
			primary = -dx
			cross = abs(dy)
		case .Right:
			if dx <= 0 { continue }
			primary = dx
			cross = abs(dy)
		}

		score := primary * 1000 + cross
		if score < best_score {
			best_score = score
			best_id = entry.id
		}
	}

	if best_id == 0 { return false }
	ws.focused_id = best_id
	return true
}

widget_spatial_rect_valid :: proc(ws: ^Widget_Store, rect: Rect, last_frame: u64) -> bool {
	return rect.w > 0 && rect.h > 0 && (last_frame == ws.frame || last_frame + 1 == ws.frame)
}

widget_spatial_inside_modal :: proc(ws: ^Widget_Store, rect: Rect) -> bool {
	mr := ws.modal_rect
	if mr.w <= 0 || mr.h <= 0 { mr = ws.modal_rect_prev }
	if mr.w <= 0 || mr.h <= 0 { return true }
	c := [2]f32{rect.x + rect.w / 2, rect.y + rect.h / 2}
	return rect_contains_point(mr, c)
}

widget_spatial_focus_first :: proc(ws: ^Widget_Store, dir: Gamepad_Nav_Direction) -> bool {
	best_id := Widget_ID(0)
	best_score := f32(3.4e38)
	for entry in ws.focusables {
		st, ok := ws.states[entry.id]
		if !ok || !widget_spatial_rect_valid(ws, st.last_rect, st.last_frame) { continue }
		if !widget_spatial_inside_modal(ws, st.last_rect) { continue }
		r := st.last_rect
		cx := r.x + r.w / 2
		cy := r.y + r.h / 2
		score: f32
		switch dir {
		case .Up, .Left:
			score = -cy * 1000 - cx
		case .Down, .Right:
			score = cy * 1000 + cx
		}
		if score < best_score {
			best_score = score
			best_id = entry.id
		}
	}
	if best_id == 0 { return false }
	ws.focused_id = best_id
	return true
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skald/widget.odin skald/backend_fake_test.odin
git commit -m "feat: add spatial widget focus"
```

---

### Task 3: Gamepad Nav Helpers, Shortcuts, And Capture Registration

**Files:**
- Modify: `skald/widget.odin`
- Modify: `skald/shortcut.odin`
- Modify: `skald/input_capture.odin`
- Modify: `skald/backend_fake_test.odin`

- [ ] **Step 1: Write failing shortcut and helper tests**

Append these tests to `skald/backend_fake_test.odin`:

```odin
Test_Gamepad_Msg :: enum {
	Open,
}

@(test)
gamepad_shortcut_sends_message_and_consumes_button :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	msgs := make([dynamic]Test_Gamepad_Msg)
	defer delete(msgs)

	input := Input{}
	input.gamepad_nav.active = true
	input.gamepad_nav.buttons_pressed = {.Menu}
	ctx := Ctx(Test_Gamepad_Msg){input = &input, msgs = &msgs, widgets = &ws}

	gamepad_shortcut(&ctx, Gamepad_Chord{button = .Menu}, .Open)

	testing.expect_value(t, len(msgs), 1)
	testing.expect_value(t, msgs[0], Test_Gamepad_Msg.Open)
	testing.expect(t, .Menu not_in input.gamepad_nav.buttons_pressed)
	testing.expect_value(t, ws.gamepad_shortcut_matched, true)
}

@(test)
capture_gamepad_when_registered_shortcut_matches :: proc(t: ^testing.T) {
	input := Input{}
	input.gamepad_nav.active = true
	input.gamepad_nav.buttons_pressed = {.Menu}

	capture := input_capture_from_frame(
		input,
		Capture_Frame_State{
			gamepad_shortcuts = []Gamepad_Chord{{button = .Menu}},
		},
	)

	testing.expect_value(t, capture.gamepad, true)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL with undefined identifiers for `Gamepad_Chord`, `gamepad_shortcut`, or `gamepad_shortcuts`.

- [ ] **Step 3: Add gamepad shortcut storage to `Widget_Store`**

In `skald/widget.odin`, add fields to `Widget_Store`:

```odin
	gamepad_nav_consumed:      bool,
	gamepad_shortcut_matched:  bool,
	gamepad_shortcuts:         [dynamic]Gamepad_Chord,
	gamepad_shortcuts_prev:    [dynamic]Gamepad_Chord,
```

In `widget_store_init`, initialize both dynamic arrays:

```odin
	ws.gamepad_shortcuts      = make([dynamic]Gamepad_Chord)
	ws.gamepad_shortcuts_prev = make([dynamic]Gamepad_Chord)
```

In `widget_store_destroy`, delete both arrays:

```odin
	delete(ws.gamepad_shortcuts)
	delete(ws.gamepad_shortcuts_prev)
```

In `widget_store_frame_reset`, reset frame flags and rotate shortcut buffers:

```odin
	ws.gamepad_nav_consumed = false
	ws.gamepad_shortcut_matched = false
	ws.gamepad_shortcuts, ws.gamepad_shortcuts_prev = ws.gamepad_shortcuts_prev, ws.gamepad_shortcuts
	clear(&ws.gamepad_shortcuts)
```

- [ ] **Step 4: Add helper and shortcut procs**

Append this to `skald/shortcut.odin` after `shortcut`:

```odin
Gamepad_Chord :: struct {
	button: Gamepad_Nav_Button,
}

gamepad_chord_matches :: proc(nav: Gamepad_Nav, chord: Gamepad_Chord) -> bool {
	return nav.active && chord.button in nav.buttons_pressed
}

gamepad_shortcut :: proc(ctx: ^Ctx($Msg), chord: Gamepad_Chord, msg: Msg) {
	if ctx == nil || ctx.input == nil || ctx.msgs == nil || ctx.widgets == nil { return }
	append(&ctx.widgets.gamepad_shortcuts, chord)
	if !gamepad_chord_matches(ctx.input.gamepad_nav, chord) { return }

	send(ctx, msg)
	ctx.input.gamepad_nav.buttons_pressed -= {chord.button}
	ctx.widgets.gamepad_shortcut_matched = true
	ctx.widgets.gamepad_nav_consumed = true
}
```

Append this to `skald/widget.odin` near the focus helpers:

```odin
gamepad_nav_dir_pressed :: proc(ctx: ^Ctx($Msg), dir: Gamepad_Nav_Direction) -> bool {
	return ctx != nil && ctx.input != nil && dir in ctx.input.gamepad_nav.dir_pressed
}

gamepad_nav_consume_dir :: proc(ctx: ^Ctx($Msg), dir: Gamepad_Nav_Direction) {
	if ctx == nil || ctx.input == nil { return }
	ctx.input.gamepad_nav.dir_pressed -= {dir}
	if ctx.widgets != nil {
		ctx.widgets.gamepad_nav_consumed = true
	}
}

gamepad_nav_button_pressed :: proc(ctx: ^Ctx($Msg), button: Gamepad_Nav_Button) -> bool {
	return ctx != nil && ctx.input != nil && button in ctx.input.gamepad_nav.buttons_pressed
}

gamepad_nav_consume_button :: proc(ctx: ^Ctx($Msg), button: Gamepad_Nav_Button) {
	if ctx == nil || ctx.input == nil { return }
	ctx.input.gamepad_nav.buttons_pressed -= {button}
	if ctx.widgets != nil {
		ctx.widgets.gamepad_nav_consumed = true
	}
}
```

- [ ] **Step 5: Extend capture frame with shortcuts**

In `skald/input_capture.odin`, add to `Capture_Frame_State`:

```odin
	gamepad_shortcuts: []Gamepad_Chord,
```

Update `input_capture_from_frame` before calculating `gamepad`:

```odin
	gamepad_shortcut_matched := frame.gamepad_shortcut_matched
	if !gamepad_shortcut_matched {
		for chord in frame.gamepad_shortcuts {
			if gamepad_chord_matches(input.gamepad_nav, chord) {
				gamepad_shortcut_matched = true
				break
			}
		}
	}
```

Then use `gamepad_shortcut_matched` in the `gamepad` expression:

```odin
	gamepad := frame.gamepad_nav_consumed ||
		gamepad_shortcut_matched ||
		((frame.wants_keyboard || frame.modal_open) && gamepad_nav_active)
```

In `capture_frame_from_widgets`, set:

```odin
		gamepad_nav_consumed = widgets.gamepad_nav_consumed,
		gamepad_shortcut_matched = widgets.gamepad_shortcut_matched,
		gamepad_shortcuts = widgets.gamepad_shortcuts[:],
```

In `capture_frame_from_previous_widgets`, set:

```odin
		gamepad_shortcuts = widgets.gamepad_shortcuts_prev[:],
```

- [ ] **Step 6: Run tests**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add skald/widget.odin skald/shortcut.odin skald/input_capture.odin skald/backend_fake_test.odin
git commit -m "feat: add gamepad shortcuts"
```

---

### Task 4: Pre-View Gamepad Navigation Routing

**Files:**
- Modify: `skald/widget.odin`
- Modify: `skald/backend_fake_test.odin`

- [ ] **Step 1: Write failing preprocessor tests**

Append these tests to `skald/backend_fake_test.odin`:

```odin
@(test)
gamepad_preprocess_spatial_moves_button_focus_before_view :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	left := Widget_ID(1)
	right := Widget_ID(2)
	make_focus_state_for_test(&ws, left, {x = 10, y = 10, w = 40, h = 24})
	make_focus_state_for_test(&ws, right, {x = 80, y = 10, w = 40, h = 24})
	ws.focused_id = left

	input := Input{}
	input.gamepad_nav.active = true
	input.gamepad_nav.dir_pressed = {.Right}

	widget_preprocess_gamepad_navigation(&ws, &input)

	testing.expect_value(t, ws.focused_id, right)
	testing.expect(t, .Right not_in input.gamepad_nav.dir_pressed)
	testing.expect_value(t, ws.gamepad_nav_consumed, true)
}

@(test)
gamepad_preprocess_keeps_direction_for_tree_internal_nav :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	tree := Widget_ID(1)
	other := Widget_ID(2)
	make_focus_state_for_test(&ws, tree, {x = 10, y = 10, w = 80, h = 80}, .Tree)
	make_focus_state_for_test(&ws, other, {x = 10, y = 120, w = 80, h = 24})
	ws.focused_id = tree

	input := Input{}
	input.gamepad_nav.active = true
	input.gamepad_nav.dir_pressed = {.Down}

	widget_preprocess_gamepad_navigation(&ws, &input)

	testing.expect_value(t, ws.focused_id, tree)
	testing.expect(t, .Down in input.gamepad_nav.dir_pressed)
	testing.expect(t, .Down in input.keys_pressed)
	testing.expect_value(t, ws.gamepad_nav_consumed, true)
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL with undefined identifier `widget_preprocess_gamepad_navigation`.

- [ ] **Step 3: Implement preprocessor in `skald/widget.odin`**

Add this near the spatial focus helpers:

```odin
widget_preprocess_gamepad_navigation :: proc(ws: ^Widget_Store, input: ^Input) {
	if ws == nil || input == nil || !input.gamepad_nav.active { return }

	for dir in Gamepad_Nav_Direction {
		if dir not_in input.gamepad_nav.dir_pressed { continue }
		if widget_focused_kind_consumes_gamepad_dir(ws, dir) {
			input.keys_pressed += widget_key_for_gamepad_dir(dir)
			input.keys_down += widget_key_for_gamepad_dir(dir)
			ws.gamepad_nav_consumed = true
			continue
		}
		if widget_spatial_focus(ws, dir) {
			input.gamepad_nav.dir_pressed -= {dir}
			ws.gamepad_nav_consumed = true
		}
	}
}

widget_key_for_gamepad_dir :: proc(dir: Gamepad_Nav_Direction) -> Key {
	switch dir {
	case .Up:    return .Up
	case .Down:  return .Down
	case .Left:  return .Left
	case .Right: return .Right
	}
	return .Down
}

widget_focused_kind_consumes_gamepad_dir :: proc(ws: ^Widget_Store, dir: Gamepad_Nav_Direction) -> bool {
	if ws.focused_id == 0 { return false }
	st, ok := ws.states[ws.focused_id]
	if !ok { return false }
	switch st.kind {
	case .Tree, .Scroll, .Select, .Combobox, .Date_Picker, .Time_Picker, .Color_Picker, .Emoji_Picker, .Command_Palette:
		return true
	case .Slider:
		return dir == .Left || dir == .Right
	}
	return false
}
```

- [ ] **Step 4: Run tests**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add skald/widget.odin skald/backend_fake_test.odin
git commit -m "feat: preprocess gamepad widget navigation"
```

---

### Task 5: Widget Accept And Cancel Integration

**Files:**
- Modify: `skald/view.odin`
- Modify: `skald/backend_fake_test.odin`

- [ ] **Step 1: Add focused button-helper behavior test**

Append this direct helper test to `skald/backend_fake_test.odin`:

```odin
@(test)
gamepad_nav_consume_button_clears_pressed_button :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	input := Input{}
	input.gamepad_nav.active = true
	input.gamepad_nav.buttons_pressed = {.Accept}
	msgs := make([dynamic]Test_Gamepad_Msg)
	defer delete(msgs)
	ctx := Ctx(Test_Gamepad_Msg){input = &input, msgs = &msgs, widgets = &ws}

	testing.expect_value(t, gamepad_nav_button_pressed(&ctx, .Accept), true)
	gamepad_nav_consume_button(&ctx, .Accept)

	testing.expect(t, .Accept not_in input.gamepad_nav.buttons_pressed)
	testing.expect_value(t, ws.gamepad_nav_consumed, true)
}
```

- [ ] **Step 2: Run tests**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS if Task 3 helper code is present.

- [ ] **Step 3: Update focused activation checks in widgets**

In `skald/view.odin`, update button/link-like focused activation checks from:

```odin
if .Space in keys || .Enter in keys {
	send(ctx, on_click)
}
```

to:

```odin
if .Space in keys || .Enter in keys || gamepad_nav_button_pressed(ctx, .Accept) {
	send(ctx, on_click)
	if gamepad_nav_button_pressed(ctx, .Accept) {
		gamepad_nav_consume_button(ctx, .Accept)
	}
}
```

Use `rg -n "\\.Space in keys|\\.Enter in keys|\\.Space in ctx.input.keys_pressed|\\.Enter in ctx.input.keys_pressed" skald/view.odin` and update each focused activation site that sends an action message on Enter or Space. The required sites are button, link, checkbox, toggle, radio, collapsible header, table row activation, and tree row activation. Preserve each site's existing keyboard condition and add only the `gamepad_nav_button_pressed(ctx, .Accept)` branch plus the matching `gamepad_nav_consume_button(ctx, .Accept)` call.

- [ ] **Step 4: Update Escape-like cancel checks**

For widgets that currently close on Escape, update checks from:

```odin
if .Escape in ctx.input.keys_pressed {
	st.open = false
}
```

to:

```odin
if .Escape in ctx.input.keys_pressed || gamepad_nav_button_pressed(ctx, .Cancel) {
	st.open = false
	if gamepad_nav_button_pressed(ctx, .Cancel) {
		gamepad_nav_consume_button(ctx, .Cancel)
	}
}
```

Apply this to dialog, menu/popover, select/combobox, command palette, and other
open overlay widgets that already have Escape dismissal logic.

- [ ] **Step 5: Run checks**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add skald/view.odin skald/backend_fake_test.odin
git commit -m "feat: route gamepad accept and cancel to widgets"
```

---

### Task 6: Karl2D Gamepad Translation

**Files:**
- Modify: `skald_karl2d/backend.odin`
- Modify: `skald_karl2d/input.odin`

- [ ] **Step 1: Add adapter state and capability**

In `skald_karl2d/backend.odin`, add fields to `Backend_State`:

```odin
	gamepad_stick_dirs_prev: skald.Gamepad_Nav_Directions,
```

Set backend capabilities to include gamepad navigation:

```odin
		capabilities = {.Gamepad_Navigation},
```

- [ ] **Step 2: Add translation helpers**

Append this to `skald_karl2d/input.odin`:

```odin
GAMEPAD_NAV_DEADZONE :: f32(0.45)

translate_gamepad_nav :: proc(s: ^Backend_State) -> skald.Gamepad_Nav {
	nav: skald.Gamepad_Nav
	gamepad := k2.Gamepad_Index(0)
	if !k2.is_gamepad_active(gamepad) {
		s.gamepad_stick_dirs_prev = {}
		return nav
	}

	nav.active = true

	map_button_dir(&nav, gamepad, .Left_Face_Up, .Up)
	map_button_dir(&nav, gamepad, .Left_Face_Down, .Down)
	map_button_dir(&nav, gamepad, .Left_Face_Left, .Left)
	map_button_dir(&nav, gamepad, .Left_Face_Right, .Right)

	stick_dirs := stick_dirs_from_karl2d(gamepad)
	nav.dir_down += stick_dirs
	for dir in skald.Gamepad_Nav_Direction {
		if dir in stick_dirs && dir not_in s.gamepad_stick_dirs_prev {
			nav.dir_pressed += {dir}
		}
	}
	s.gamepad_stick_dirs_prev = stick_dirs

	map_button(&nav, gamepad, .Right_Face_Down, .Accept)
	map_button(&nav, gamepad, .Right_Face_Right, .Cancel)
	map_button(&nav, gamepad, .Middle_Face_Right, .Menu)

	return nav
}

map_button_dir :: proc(
	nav: ^skald.Gamepad_Nav,
	gamepad: k2.Gamepad_Index,
	button: k2.Gamepad_Button,
	dir: skald.Gamepad_Nav_Direction,
) {
	if k2.gamepad_button_is_held(gamepad, button) { nav.dir_down += {dir} }
	if k2.gamepad_button_went_down(gamepad, button) { nav.dir_pressed += {dir} }
}

map_button :: proc(
	nav: ^skald.Gamepad_Nav,
	gamepad: k2.Gamepad_Index,
	button: k2.Gamepad_Button,
	out: skald.Gamepad_Nav_Button,
) {
	if k2.gamepad_button_is_held(gamepad, button) { nav.buttons_down += {out} }
	if k2.gamepad_button_went_down(gamepad, button) { nav.buttons_pressed += {out} }
}

stick_dirs_from_karl2d :: proc(gamepad: k2.Gamepad_Index) -> skald.Gamepad_Nav_Directions {
	out: skald.Gamepad_Nav_Directions
	x := k2.get_gamepad_axis(gamepad, .Left_Stick_X)
	y := k2.get_gamepad_axis(gamepad, .Left_Stick_Y)
	if x <= -GAMEPAD_NAV_DEADZONE { out += {.Left} }
	if x >=  GAMEPAD_NAV_DEADZONE { out += {.Right} }
	if y <= -GAMEPAD_NAV_DEADZONE { out += {.Up} }
	if y >=  GAMEPAD_NAV_DEADZONE { out += {.Down} }
	return out
}
```

In `translate_input`, add after keyboard/modifier assignment:

```odin
	s.input.gamepad_nav = translate_gamepad_nav(s)
```

- [ ] **Step 3: Compile-check Karl2D adapter**

Run:

```bash
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add skald_karl2d/backend.odin skald_karl2d/input.odin
git commit -m "feat: translate karl2d gamepad navigation"
```

---

### Task 7: Embedded Frame Integration

**Files:**
- Modify: `skald_karl2d/embedded.odin`
- Modify: `skald/input_capture.odin`
- Modify: `skald/backend_fake_test.odin`

- [ ] **Step 1: Add previous-shortcut capture test**

Append this test to `skald/backend_fake_test.odin`:

```odin
@(test)
previous_frame_capture_uses_previous_gamepad_shortcuts :: proc(t: ^testing.T) {
	ws: Widget_Store
	widget_store_init(&ws)
	defer widget_store_destroy(&ws)

	append(&ws.gamepad_shortcuts, Gamepad_Chord{button = .Menu})
	widget_store_frame_reset(&ws)

	input := Input{}
	input.gamepad_nav.active = true
	input.gamepad_nav.buttons_pressed = {.Menu}

	frame := capture_frame_from_previous_widgets(&ws, false)
	capture := input_capture_from_frame(input, frame)

	testing.expect_value(t, capture.gamepad, true)
}
```

- [ ] **Step 2: Run tests**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS after Task 3, or FAIL if previous shortcut slices were not wired correctly.

- [ ] **Step 3: Run pre-view navigation in `begin_frame`**

In `skald_karl2d/embedded.odin`, update `begin_frame` so gamepad navigation is preprocessed after `translate_input` and before `widget_store_frame_reset`:

```odin
	translate_input(&ctx.backend_state)
	skald.widget_preprocess_gamepad_navigation(&ctx.widgets, &ctx.backend_state.input)
	prev_wants_text_input := ctx.widgets.wants_text_input
```

Keep the existing `widget_store_frame_reset` and capture calculation after this block.

- [ ] **Step 4: Include gamepad fields in capture helpers**

Confirm `capture_frame_from_previous_widgets` returns `gamepad_shortcuts = widgets.gamepad_shortcuts_prev[:]` and `capture_frame_from_widgets` returns current shortcut and consumed fields from `widgets`.

- [ ] **Step 5: Run checks**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Expected: both PASS.

- [ ] **Step 6: Commit**

```bash
git add skald_karl2d/embedded.odin skald/input_capture.odin skald/backend_fake_test.odin
git commit -m "feat: integrate gamepad navigation into karl2d frames"
```

---

### Task 8: Example And Documentation

**Files:**
- Modify: `examples/50_karl2d_overlay/main.odin`
- Modify: `docs/examples.md`

- [ ] **Step 1: Update overlay example**

In `examples/50_karl2d_overlay/main.odin`, add a second row or grid of Skald controls to the overlay view so there are focusable targets above, below, left, and right. Register one gamepad shortcut near the top of the view:

```odin
skald.gamepad_shortcut(ctx, skald.Gamepad_Chord{button = .Menu}, Toggle_Menu{})
```

Gate gameplay gamepad movement using:

```odin
if !capture.gamepad {
	if k2.gamepad_button_is_held(0, .Left_Face_Left) { player.x -= 4 }
	if k2.gamepad_button_is_held(0, .Left_Face_Right) { player.x += 4 }
	if k2.gamepad_button_is_held(0, .Left_Face_Up) { player.y -= 4 }
	if k2.gamepad_button_is_held(0, .Left_Face_Down) { player.y += 4 }
}
```

Keep the existing keyboard capture gating intact.

- [ ] **Step 2: Update docs example description**

In `docs/examples.md`, update the `50_karl2d_overlay` row to mention split game loop, input pass-through, and gamepad UI navigation.

- [ ] **Step 3: Build example**

Run:

```bash
./build.sh 50_karl2d_overlay
```

Expected: PASS and produce/update `build/50_karl2d_overlay`.

- [ ] **Step 4: Commit**

```bash
git add examples/50_karl2d_overlay/main.odin docs/examples.md
git commit -m "docs: demonstrate karl2d gamepad navigation"
```

---

### Task 9: Final Verification

**Files:**
- No source changes expected.

- [ ] **Step 1: Run full automated verification**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
odin check ./skald_karl2d -collection:gui=. -no-entry-point
./build.sh 50_karl2d_overlay
git diff --check
```

Expected: all commands PASS.

- [ ] **Step 2: Run bounded example smoke test**

Run:

```bash
timeout 3s ./build/50_karl2d_overlay
```

Expected: the app starts and remains alive until `timeout` stops it. In headless environments this may fail because no display server or GPU context is available; record the exact error if it does.

- [ ] **Step 3: Manual gamepad smoke test**

In a desktop session with a connected controller:

```bash
./build/50_karl2d_overlay
```

Expected:

- D-pad or left stick moves focus spatially between overlay controls.
- A / south face activates focused buttons.
- B / east face cancels open popovers/dialogs when present.
- Start/Menu triggers the registered gamepad shortcut.
- While UI captures gamepad input, the game scene does not also move from that same controller press.
- Static overlay text does not block gameplay controller input.

- [ ] **Step 4: Commit any verification note if documentation changed**

If no files changed, do not commit. If a verification note is added to docs, run:

```bash
git add <changed-doc-file>
git commit -m "docs: record gamepad navigation verification"
```

---

## Self-Review Notes

- Spec coverage: The plan covers input model, Karl2D-only translation, spatial focus, internal-first routing, shortcuts for non-focusable UI commands, gamepad capture, backend capability, example, and verification.
- Deferred by design: SDL3 backend support, raw gamepad app input, multiple controllers, remapping, haptics, repeat timing, and explicit navigation graph overrides.
- Timing resolution: For split game loops, previous-frame gamepad shortcut registrations are used for pre-game capture. The current view still registers and fires shortcuts during `end_frame`, matching Skald's existing view-time shortcut style while giving games a conservative capture signal before simulation.
