# Karl2D Game Loop Frame Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `skald_karl2d.begin_frame(&ui)` and `skald_karl2d.end_frame(&ui)` so games can read Skald input capture before simulation while still drawing Skald as a post-game overlay.

**Architecture:** Keep `skald_karl2d.frame(&ui)` as the existing all-in-one convenience API. Add a previous-frame capture helper in core Skald, then split the embedded Karl2D frame into pre-game preparation and post-game render/finish phases. Update the overlay example and docs to make the split loop the recommended game-loop pattern.

**Tech Stack:** Odin, Skald core package, Karl2D embedded backend, existing `odin test`, `odin check`, and `build.sh` verification.

---

## Execution Progress

Updated: 2026-05-27 after Task 2 spec-compliance review.

- Baseline before implementation passed:
  - `odin test ./skald -collection:gui=. -define:SKALD_RUNA=false`
  - `odin check ./skald_karl2d -collection:gui=. -no-entry-point`
  - `./build.sh 50_karl2d_overlay`
- Task 1 complete and committed:
  - Commit `489e709` — `feat: add previous-frame input capture helper`
  - Spec review: passed.
  - Code-quality review: passed with only minor, non-blocking test-isolation suggestions.
- Task 2 implementation complete and committed:
  - Commit `acbfacd` — `feat: split karl2d embedded frame lifecycle`
  - Spec review: passed.
  - Code-quality review: not yet run. This is the next required step before Task 3.
- Current worktree at the time of this note was clean before editing this progress section.

Resume from here:

1. Run Task 2 code-quality review for `489e709..acbfacd`.
2. If no Critical or Important issues, mark Task 2 quality review complete.
3. Start Task 3 documentation updates.
4. Continue with Task 3 reviews and Task 4 final verification.

---

## File Structure

- Modify `skald/input_capture.odin`: add a helper for capture derived from previous-frame widget geometry after `widget_store_frame_reset`.
- Modify `skald/backend_fake_test.odin`: add focused tests for previous-frame capture and focus blur.
- Modify `skald_karl2d/backend.odin`: remove stale capture staging fields from `Backend_State`.
- Modify `skald_karl2d/embedded.odin`: add `begin_frame`, `end_frame`, `frame_active`, and turn `frame` into a wrapper.
- Modify `examples/50_karl2d_overlay/main.odin`: use split frame calls so game input and movement happen before draw.
- Modify `README.md`: document the split embedded game loop.
- Modify `docs/architecture.md`: describe the split Karl2D embedded lifecycle.
- Modify `docs/examples.md`: update the example description.

---

### Task 1: Previous-Frame Capture Helper

**Files:**
- Modify: `skald/input_capture.odin`
- Modify: `skald/backend_fake_test.odin`

- [x] **Step 1: Write failing tests for previous-frame capture**

Append these tests to `skald/backend_fake_test.odin` after `outside_press_blurs_focused_button_before_capture`:

```odin
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
```

- [x] **Step 2: Run tests to verify failure**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL with an undefined identifier error for `capture_frame_from_previous_widgets`.

- [x] **Step 3: Implement previous-frame capture helper**

Add this proc to `skald/input_capture.odin` after `capture_frame_from_widgets`:

```odin
capture_frame_from_previous_widgets :: proc(
	widgets: ^Widget_Store,
	prev_wants_text_input: bool,
) -> Capture_Frame_State {
	if widgets == nil {return {}}

	pointer_regions := make([dynamic]Rect, 0, len(widgets.states), context.temp_allocator)
	press_owned := false
	for _, st in widgets.states {
		if st.last_frame + 1 != widgets.frame {continue}
		if st.last_rect.w <= 0 || st.last_rect.h <= 0 {continue}
		append(&pointer_regions, st.last_rect)
		press_owned = press_owned || st.pressed || st.mouse_selecting
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
```

- [x] **Step 4: Run tests to verify pass**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add skald/input_capture.odin skald/backend_fake_test.odin
git commit -m "feat: add previous-frame input capture helper"
```

---

### Task 2: Split Karl2D Embedded Frame Lifecycle

**Files:**
- Modify: `skald_karl2d/backend.odin`
- Modify: `skald_karl2d/embedded.odin`

- [x] **Step 1: Write failing split-API usage in the overlay example**

Temporarily update `examples/50_karl2d_overlay/main.odin` loop to call the new API. Replace lines 82-102 with:

```odin
	for k2.update() {
		skald_k2.begin_frame(&ui)
		capture := skald_k2.capture(&ui)

		if !capture.keyboard {
			if k2.key_is_held(.A) {player.x -= 4}
			if k2.key_is_held(.D) {player.x += 4}
			if k2.key_is_held(.W) {player.y -= 4}
			if k2.key_is_held(.S) {player.y += 4}
		}

		k2.clear(k2.DARK_BLUE)
		k2.draw_circle(player, 24, k2.LIGHT_GREEN)
		k2.draw_text(
			"WASD moves the circle when Skald does not capture keyboard",
			{24, 680},
			24,
			k2.WHITE,
		)

		skald_k2.end_frame(&ui)
		k2.present()
	}
```

- [x] **Step 2: Run build to verify failure**

Run:

```bash
./build.sh 50_karl2d_overlay
```

Expected: FAIL with undefined identifiers `begin_frame` and `end_frame`.

- [x] **Step 3: Remove stale backend capture fields**

In `skald_karl2d/backend.odin`, replace the `Backend_State` header with:

```odin
Backend_State :: struct {
	input:      skald.Input,
	capture:    skald.Input_Capture,
	alpha:      f32,
	clip_stack: [dynamic]skald.Rect,
	fonts:      [dynamic]k2.Font,
	images:     map[string]^Image_Entry,
}
```

- [x] **Step 4: Add lifecycle state and split frame procs**

In `skald_karl2d/embedded.odin`, add `frame_active` to `Context`:

```odin
	Context :: struct($State, $Msg: typeid) {
		app:           skald.App(State, Msg),
		state:         State,
		theme:         skald.Theme,
		labels:        skald.Labels,
		backend_state: Backend_State,
		backend:       skald.Backend,
		rc:            skald.Render_Context,
		msgs:          [dynamic]Msg,
		widgets:       skald.Widget_Store,
		overlays:      [dynamic]skald.Overlay_Entry,
		runtime:       skald.Embedded_Runtime(Msg),
		runtime_ready: bool,
		frame_active:  bool,
	}
```

Replace the existing `frame`, `drain_messages`, `capture`, and `input` procs in `skald_karl2d/embedded.odin` with:

```odin
frame :: proc(ctx: ^Context($State, $Msg)) {
	begin_frame(ctx)
	end_frame(ctx)
}

begin_frame :: proc(ctx: ^Context($State, $Msg)) {
	assert(!ctx.frame_active, "skald_karl2d.begin_frame called while a frame is already active")
	ctx.frame_active = true

	if ctx.runtime_ready {
		skald.embedded_runtime_begin_frame(&ctx.runtime, &ctx.msgs)
	}

	translate_input(&ctx.backend_state)
	prev_wants_text_input := ctx.widgets.wants_text_input

	skald.widget_store_frame_reset(&ctx.widgets)
	skald.widget_store_blur_on_outside_press(&ctx.widgets, ctx.backend_state.input)
	clear(&ctx.overlays)

	sz := window_size(ctx.backend.state)
	ctx.rc.frame_size = {u32(max(sz.x, 0)), u32(max(sz.y, 0))}
	ctx.rc.scale = window_scale(ctx.backend.state)
	ctx.rc.alpha_multiplier = 1

	frame_state := skald.capture_frame_from_previous_widgets(
		&ctx.widgets,
		prev_wants_text_input,
	)
	ctx.backend_state.capture = skald.input_capture_from_frame(
		ctx.backend_state.input,
		frame_state,
	)
}

end_frame :: proc(ctx: ^Context($State, $Msg)) {
	assert(ctx.frame_active, "skald_karl2d.end_frame called before begin_frame")

	sz := window_size(ctx.backend.state)
	size := [2]f32{f32(sz.x), f32(sz.y)}
	ctx.rc.frame_size = {u32(max(sz.x, 0)), u32(max(sz.y, 0))}
	ctx.rc.scale = window_scale(ctx.backend.state)
	ctx.rc.alpha_multiplier = 1

	ctx_ctx := skald.Ctx(Msg) {
		theme      = &ctx.theme,
		labels     = &ctx.labels,
		input      = &ctx.backend_state.input,
		msgs       = &ctx.msgs,
		widgets    = &ctx.widgets,
		renderer   = nil,
		render     = &ctx.rc,
		window     = skald.Window_Id(nil),
		breakpoint = skald.breakpoint(f32(k2.get_screen_width())),
	}

	view := ctx.app.view(ctx.state, &ctx_ctx)
	skald.render_view(&ctx.rc, view, {0, 0}, size)
	skald.render_overlays(&ctx.rc)

	ctx.backend.window.set_text_input(ctx.backend.state, ctx.widgets.wants_text_input)
	frame_state := skald.capture_frame_from_widgets(&ctx.widgets)
	ctx.backend_state.capture = skald.input_capture_from_frame(
		ctx.backend_state.input,
		frame_state,
	)

	ctx.state = drain_messages(ctx)
	ctx.frame_active = false
	free_all(context.temp_allocator)
}

drain_messages :: proc(ctx: ^Context($State, $Msg)) -> State {
	if !ctx.runtime_ready {return ctx.state}
	return skald.embedded_runtime_drain_messages(
		&ctx.runtime,
		ctx.state,
		ctx.app,
		&ctx.msgs,
		&ctx.theme,
	)
}

capture :: proc(ctx: ^Context($State, $Msg)) -> skald.Input_Capture {
	return ctx.backend_state.capture
}

input :: proc(ctx: ^Context($State, $Msg)) -> skald.Input {
	return ctx.backend_state.input
}
```

- [x] **Step 5: Run compile checks**

Run:

```bash
odin check ./skald_karl2d -collection:gui=. -no-entry-point
./build.sh 50_karl2d_overlay
```

Expected: both commands pass.

- [x] **Step 6: Verify all-in-one compatibility still compiles**

Temporarily change the example loop back to the old `skald_k2.frame(&ui)` style. The compatibility snippet must compile:

```odin
for k2.update() {
	k2.clear(k2.DARK_BLUE)
	skald_k2.frame(&ui)
	_ = skald_k2.capture(&ui)
	k2.present()
}
```

Run:

```bash
./build.sh 50_karl2d_overlay
```

Expected: PASS. Restore the split-loop example before committing.

- [x] **Step 7: Commit**

```bash
git add skald_karl2d/backend.odin skald_karl2d/embedded.odin examples/50_karl2d_overlay/main.odin
git commit -m "feat: split karl2d embedded frame lifecycle"
```

---

### Task 3: Document the Split Game Loop

**Files:**
- Modify: `README.md`
- Modify: `docs/architecture.md`
- Modify: `docs/examples.md`

- [ ] **Step 1: Update README embedded backend bullet**

In `README.md`, replace the embedded backend bullet at lines 63-66 with:

```markdown
- **Embeddable backend path** — Skald can be hosted by Karl2D as an
  overlay UI layer. The host game owns the window, simulation, game
  rendering, and present call; `begin_frame` exposes UI input capture
  before game update, and `end_frame` draws Skald over the game scene.
```

- [ ] **Step 2: Update architecture backend-services section**

In `docs/architecture.md`, replace lines 260-263 with:

```markdown
Karl2D adapter implements the same service shape for embedded overlays:
Karl2D owns the window, event pump, game update, game draw, and present call.
Game loops call `skald_karl2d.begin_frame` before simulation to snapshot
input and read capture, then call `skald_karl2d.end_frame` after game drawing
to render the UI overlay and drain Skald messages. `skald_karl2d.frame`
remains the all-in-one convenience wrapper for non-game overlay use.
```

- [ ] **Step 3: Update examples table**

In `docs/examples.md`, replace the `50_karl2d_overlay` row with:

```markdown
| `50_karl2d_overlay` | Karl2D game loop with a Skald overlay. Shows split `begin_frame`/`end_frame`, keyboard pass-through, UI capture, a button, and text input. |
```

- [ ] **Step 4: Run documentation-adjacent compile checks**

Run:

```bash
./build.sh 50_karl2d_overlay
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Expected: both commands pass.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/architecture.md docs/examples.md
git commit -m "docs: document karl2d split frame loop"
```

---

### Task 4: Final Verification

**Files:**
- No new files.

- [ ] **Step 1: Run Skald core tests**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

- [ ] **Step 2: Run Karl2D backend compile check**

Run:

```bash
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Expected: PASS.

- [ ] **Step 3: Build split-loop overlay example**

Run:

```bash
./build.sh 50_karl2d_overlay
```

Expected: PASS and output binary at `build/50_karl2d_overlay`.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git diff --stat HEAD~3..HEAD
git status --short
```

Expected: the diff includes only the planned files, and `git status --short` is empty.

- [ ] **Step 5: Manual smoke test in desktop session**

Run:

```bash
./build/50_karl2d_overlay
```

Expected:

- WASD moves the circle before the frame is drawn when the text input is not focused.
- Clicking into the text input captures keyboard input and WASD no longer moves the circle.
- Clicking outside the Skald UI releases keyboard capture on the following frame.
- The Skald UI still renders over the Karl2D scene.

Do not commit manual-test output.
