# Skald Karl2D Embedded Backend Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a backend service interface and a Karl2D embedded runtime so Skald UI can render over a Karl2D game scene while reporting UI input capture back to game systems.

**Architecture:** Introduce backend-neutral services in `skald/` and migrate layout/render call sites from direct `Renderer` use to a `Render_Context` facade. Keep the existing SDL/Vulkan backend alive through thin compatibility wrappers that forward to current functions; do not redesign it. Implement `skald_karl2d/` as the first new backend, with Karl2D owning the window, game loop, game rendering, and `present`.

**Tech Stack:** Odin, Skald, Karl2D, `core:testing`, `core:nbio`, existing Skald runa text backend, Karl2D texture/draw/scissor APIs.

---

## Resume Snapshot

Last updated: 2026-05-23.

Current implementation state:

- Complete: Task 1, committed as `c191ebc feat: add skald backend service contracts`.
- Complete: Task 2, committed as `6c8ec06 feat: add backend-neutral input capture helpers`.
- Complete: Task 3, committed as `92a2982 refactor: add renderer backend compatibility facade` plus `61ccfe7 test: cover renderer backend compatibility`.
- Complete: Task 4, committed as `6455f7e refactor: render layout through backend context`, with follow-up fixes `b2f906f`, `200b2d6`, and `36309e9`.
- Complete: Task 5, committed as `f8afa6f refactor: route layout text through backend service`, with follow-up fixes `03ab056`, `53a2579`, `3e65bc9`, and `52bcb82`.
- Complete: Task 6, committed as `acf07df refactor: route view images through backend service`, with follow-up fixes `bf4e59a` and `3c266ce`.
- Complete: Task 7, committed as `1820b3c feat: add karl2d backend package skeleton`.
- Next task: Task 8, "Karl2D Input Translation".
- Last verified commands after Task 6: `odin test ./skald -collection:gui=. -define:SKALD_RUNA=false` passed with 16 tests, `./build.sh 20_image` passed, and `./build.sh 07_counter` passed.
- Current branch: `main`, with `HEAD` at `1820b3c`.
- Dirty worktree items to preserve: `.gitmodules` and `karl2d` are staged additions that predate this plan execution, and `.superpowers/` is untracked. Do not stage, unstage, modify, remove, or include them in commits unless the user explicitly asks.
- Commit discipline for remaining tasks: always use explicit pathspecs, for example `git commit -m "..." -- skald/file.odin ...`, so unrelated staged files are not committed.

Implemented details that differ from the original task skeleton:

- `Backend_Font` was intentionally not added. `Backend_Text` uses the existing Skald `Font` type.
- Fake backend helpers live in `skald/backend_fake_test.odin` only, not production code.
- Backend wrapper procs in `skald/backend.odin` assert that context, backend, and callbacks are configured before dispatch.
- `Backend_Text.wrap` and `Backend_Clipboard.get_text` document returned data lifetime.
- `Fake_Draw_Kind` currently contains only the operations the tests support: `Rect`, `Push_Clip`, and `Pop_Clip`.
- Renderer backend capabilities intentionally remain `{}` until the matching optional service groups are wired; draw/text service callbacks are available through `Backend.draw` and `Backend.text`.
- `Render_Context` now owns backend-neutral per-frame layout state: frame size, scale, widget store, overlay queue, and alpha multiplier.
- Plain text layout/render calls are routed through `Backend_Text`. Rich text wrapping also has a render-context path. Text input geometry and rich-text hit testing still use guarded renderer-only helpers and remain future backend service work.
- `View_Image` is routed through `Backend_Images`. Renderer image backend handles are stable key-based handles owned by the renderer image cache; path handles may reload after LRU eviction, while pixel-backed handles fail cleanly after eviction until reloaded.
- `skald_karl2d` now exists as a library package with backend draw/window/input skeletons and a public `Context` for embedded use. It intentionally does not own the Karl2D game frame or present path; `frame_begin`/`frame_end` are no-ops because Karl2D remains responsible for the window and game rendering loop.
- Task 7 check command should use library mode: `odin check ./skald_karl2d -collection:gui=. -no-entry-point`. Plain `odin check ./skald_karl2d -collection:gui=.` fails with "Undefined entry point procedure 'main'" because `skald_karl2d` is not an executable package.
- Task 7 currently stubs key and modifier translation helpers with empty sets so the package type-checks. Task 8 must replace those helpers with real Karl2D-to-Skald key/modifier mapping.
- Gamepad-to-UI navigation remains a future desired enhancement. `Gamepad_Navigation` is only a capability flag for now; no navigation mapping is implemented yet.

## File Structure

- Create `skald/backend.odin`: backend service structs, handle types, capture type, capability flags, and `Render_Context`.
- Create `skald/backend_fake_test.odin`: fake backend tests that prove draw/clip recording and input capture helpers do not depend on Vulkan.
- Create `skald/input_capture.odin`: pure capture helper logic shared by current and embedded runtimes.
- Modify `skald/input.odin`: keep `Input` unchanged, but move new capture declarations to `backend.odin`.
- Modify `skald/draw.odin`: split draw entrypoints into facade procs that call `Render_Context.draw` and existing Vulkan implementation procs.
- Modify `skald/clip.odin`: route clip push/pop through `Render_Context`.
- Modify `skald/layout.odin`: change layout walkers from `^Renderer` to `^Render_Context`.
- Modify `skald/text.odin` and `skald/text_runa.odin`: route public text calls through `Render_Context.text`; keep current Vulkan/runa implementation behind forwarding services.
- Modify `skald/image.odin`: route image API through backend image handles; keep current Vulkan image cache as one service implementation.
- Modify `skald/app.odin`: construct a `Render_Context` for the existing renderer inside `run`.
- Create `skald/embedded_runtime.odin`: exported embedded command runtime wrapper that can access private command/io/thread internals from inside the `skald` package.
- Create `skald_karl2d/embedded.odin`: public embedded runtime API.
- Create `skald_karl2d/backend.odin`: Karl2D implementations for frame, draw, text, images, input, clipboard, window, and time services.
- Create `skald_karl2d/input.odin`: Karl2D-to-Skald input translation and capture update.
- Create `skald_karl2d/text.odin`: initial Karl2D text service. Start with Karl2D/fontstash fallback, mark it as compatibility mode, then keep a clear upgrade point for runa atlas upload.
- Create `skald_karl2d/image.odin`: Karl2D texture-backed image service.
- Create `examples/50_karl2d_overlay/main.odin`: game scene plus Skald controls overlay showing pass-through input.
- Modify `build.sh`: allow building `50_karl2d_overlay` with the same `-collection:gui=.` convention.

## Task 1: Backend Contract Types

Status: complete in commit `c191ebc`.

**Files:**
- Create: `skald/backend.odin`
- Create: `skald/backend_fake_test.odin`

- [x] **Step 1: Write the failing backend contract test**

Create `skald/backend_fake_test.odin`:

```odin
package skald

import "core:testing"

@(test)
backend_context_records_draws :: proc(t: ^testing.T) {
    fake: Fake_Backend_State
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)

    backend_draw_rect(&rc, {x = 10, y = 20, w = 30, h = 40}, rgb(0xFF0000), 4)
    backend_push_clip(&rc, {x = 0, y = 0, w = 100, h = 80})
    backend_pop_clip(&rc)

    testing.expect_value(t, len(fake.ops), 3)
    testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Rect)
    testing.expect_value(t, fake.ops[0].rect, Rect{10, 20, 30, 40})
    testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Push_Clip)
    testing.expect_value(t, fake.ops[2].kind, Fake_Draw_Kind.Pop_Clip)
}
```

- [x] **Step 2: Run the test and verify it fails**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL because `Fake_Backend_State`, `fake_backend`, `render_context_from_backend`, `backend_draw_rect`, `backend_push_clip`, and `backend_pop_clip` do not exist.

- [x] **Step 3: Add backend contracts and fake backend**

Create `skald/backend.odin`:

```odin
package skald

Backend_Image :: distinct rawptr
Backend_Font  :: distinct int

Backend_Capability :: enum {
    Clipboard,
    Native_File_Dialogs,
    Text_Input_Mode,
    Multi_Window,
    Gamepad_Navigation,
}

Backend_Capabilities :: bit_set[Backend_Capability]

Input_Capture :: struct {
    mouse:           bool,
    keyboard:        bool,
    text:            bool,
    wheel:           bool,
    pointer_over_ui: bool,
}

Backend :: struct {
    state:        rawptr,
    capabilities: Backend_Capabilities,

    frame:     Backend_Frame,
    draw:      Backend_Draw,
    text:      Backend_Text,
    images:    Backend_Images,
    input:     Backend_Input,
    clipboard: Backend_Clipboard,
    window:    Backend_Window,
    time:      Backend_Time,
}

Render_Context :: struct {
    backend: ^Backend,
}

render_context_from_backend :: proc(backend: ^Backend) -> Render_Context {
    return Render_Context{backend = backend}
}

Backend_Frame :: struct {
    begin: proc(state: rawptr, clear: Color) -> bool,
    end:   proc(state: rawptr),
}

Backend_Draw :: struct {
    rect:          proc(state: rawptr, rect: Rect, color: Color, radius: f32),
    gradient_rect: proc(state: rawptr, rect: Rect, c_tl, c_tr, c_br, c_bl: Color, radius: f32),
    shadow:        proc(state: rawptr, rect: Rect, radius, blur: f32, color: Color, offset: [2]f32),
    push_clip:     proc(state: rawptr, rect: Rect),
    pop_clip:      proc(state: rawptr),
    set_alpha:     proc(state: rawptr, alpha: f32),
}

Backend_Text :: struct {
    load_font: proc(state: rawptr, name: string, data: []byte) -> Font,
    measure:   proc(state: rawptr, text: string, size: f32, font: Font) -> (f32, f32),
    wrap:      proc(state: rawptr, text: string, max_width, size: f32, font: Font) -> []string,
    ascent:    proc(state: rawptr, size: f32, font: Font) -> f32,
    draw:      proc(state: rawptr, text: string, x, y: f32, color: Color, size: f32, font: Font),
}

Backend_Images :: struct {
    load_path:     proc(state: rawptr, path: string) -> Backend_Image,
    load_pixels:   proc(state: rawptr, name: string, w, h: u32, rgba: []u8) -> Backend_Image,
    update_pixels: proc(state: rawptr, image: Backend_Image, w, h: u32, rgba: []u8) -> bool,
    unload:        proc(state: rawptr, image: Backend_Image),
    draw:          proc(state: rawptr, image: Backend_Image, rect: Rect, tint: Color),
}

Backend_Input :: struct {
    snapshot: proc(state: rawptr) -> Input,
    capture:  proc(state: rawptr) -> Input_Capture,
}

Backend_Clipboard :: struct {
    set_text: proc(state: rawptr, text: string) -> bool,
    get_text: proc(state: rawptr) -> string,
}

Backend_Window :: struct {
    size:            proc(state: rawptr) -> Size,
    scale:           proc(state: rawptr) -> f32,
    set_text_input:  proc(state: rawptr, on: bool),
}

Backend_Time :: struct {
    now_ns: proc(state: rawptr) -> i64,
}

backend_draw_rect :: proc(rc: ^Render_Context, rect: Rect, color: Color, radius: f32 = 0) {
    rc.backend.draw.rect(rc.backend.state, rect, color, radius)
}

backend_push_clip :: proc(rc: ^Render_Context, rect: Rect) {
    rc.backend.draw.push_clip(rc.backend.state, rect)
}

backend_pop_clip :: proc(rc: ^Render_Context) {
    rc.backend.draw.pop_clip(rc.backend.state)
}

Fake_Draw_Kind :: enum { Rect, Gradient_Rect, Shadow, Push_Clip, Pop_Clip, Alpha }

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
    return Backend{
        state = state,
        draw = Backend_Draw{
            rect      = fake_draw_rect,
            push_clip = fake_push_clip,
            pop_clip  = fake_pop_clip,
        },
    }
}
```

- [x] **Step 4: Run the test and verify it passes**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS for `backend_context_records_draws`.

- [x] **Step 5: Commit**

```bash
git add skald/backend.odin skald/backend_fake_test.odin
git commit -m "feat: add skald backend service contracts"
```

## Task 2: Input Capture Helpers

Status: complete in commit `6c8ec06`.

**Files:**
- Create: `skald/input_capture.odin`
- Modify: `skald/backend_fake_test.odin`

- [x] **Step 1: Add failing capture tests**

Append to `skald/backend_fake_test.odin`:

```odin
@(test)
capture_mouse_when_pointer_over_widget :: proc(t: ^testing.T) {
    input := Input{mouse_pos = {12, 16}}
    capture := input_capture_from_frame(
        input,
        Capture_Frame_State{
            pointer_regions = []Rect{{x = 10, y = 10, w = 80, h = 20}},
        },
    )

    testing.expect_value(t, capture.pointer_over_ui, true)
    testing.expect_value(t, capture.mouse, true)
    testing.expect_value(t, capture.keyboard, false)
}

@(test)
capture_keyboard_when_text_focused :: proc(t: ^testing.T) {
    capture := input_capture_from_frame(
        Input{},
        Capture_Frame_State{wants_text_input = true},
    )

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
```

- [x] **Step 2: Run tests and verify they fail**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL because `Capture_Frame_State` and `input_capture_from_frame` do not exist.

- [x] **Step 3: Implement capture helpers**

Create `skald/input_capture.odin`:

```odin
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

    return Input_Capture{
        mouse           = mouse,
        keyboard        = keyboard,
        text            = text,
        wheel           = wheel,
        pointer_over_ui = over_ui,
    }
}
```

- [x] **Step 4: Run tests and verify they pass**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS for all backend and capture tests.

- [x] **Step 5: Commit**

```bash
git add skald/input_capture.odin skald/backend_fake_test.odin
git commit -m "feat: add backend-neutral input capture helpers"
```

## Task 3: Existing Renderer Compatibility Facade

Status: complete in commits `92a2982` and `61ccfe7`.

**Files:**
- Modify: `skald/backend.odin`
- Modify: `skald/draw.odin`
- Modify: `skald/clip.odin`
- Modify: `skald/renderer.odin`

Important resume notes:

- Preserve the assertion-backed wrappers already present in `skald/backend.odin`.
- Prefer implementing the new public facades through the existing helpers where possible:

```odin
draw_rect :: proc(r: ^Render_Context, rect: Rect, color: Color, radius: f32 = 0) {
    backend_draw_rect(r, rect, color, radius)
}

push_clip :: proc(r: ^Render_Context, rect: Rect) {
    backend_push_clip(r, rect)
}

pop_clip :: proc(r: ^Render_Context) {
    backend_pop_clip(r)
}
```

- Add equivalent assertion-backed helpers or local assertions before dispatching `shadow`, `gradient_rect`, and `set_alpha`; do not introduce unchecked callback dispatch where the existing wrappers already established a defensive pattern.
- The original Task 3 commit command below is intentionally too broad for the current dirty worktree. Use the updated explicit pathspec command in Step 6.

- [x] **Step 1: Add failing compatibility test**

Append to `skald/backend_fake_test.odin`:

```odin
@(test)
render_context_can_hold_existing_renderer_pointer :: proc(t: ^testing.T) {
    r: Renderer
    backend := renderer_backend(&r)
    rc := render_context_from_backend(&backend)
    testing.expect(t, rc.backend.state == &r)
}
```

- [x] **Step 2: Run tests and verify failure**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL because `renderer_backend` does not exist.

- [x] **Step 3: Rename existing Vulkan draw procs internally**

In `skald/draw.odin`, rename current concrete draw procs:

```odin
draw_rect          -> renderer_draw_rect
draw_shadow        -> renderer_draw_shadow
draw_gradient_rect -> renderer_draw_gradient_rect
```

Then add facade procs with the old names that take `^Render_Context`:

```odin
draw_rect :: proc(r: ^Render_Context, rect: Rect, color: Color, radius: f32 = 0) {
    r.backend.draw.rect(r.backend.state, rect, color, radius)
}

draw_shadow :: proc(
    r: ^Render_Context,
    rect: Rect,
    radius: f32,
    blur: f32,
    color: Color,
    offset: [2]f32 = {0, 4},
) {
    r.backend.draw.shadow(r.backend.state, rect, radius, blur, color, offset)
}

draw_gradient_rect :: proc(
    r: ^Render_Context,
    rect: Rect,
    c_tl, c_tr, c_br, c_bl: Color,
    radius: f32 = 0,
) {
    r.backend.draw.gradient_rect(r.backend.state, rect, c_tl, c_tr, c_br, c_bl, radius)
}
```

- [x] **Step 4: Add renderer backend wrappers**

Append to `skald/backend.odin`:

```odin
renderer_backend :: proc(r: ^Renderer) -> Backend {
    return Backend{
        state = r,
        capabilities = {.Clipboard, .Native_File_Dialogs, .Text_Input_Mode, .Multi_Window},
        draw = Backend_Draw{
            rect          = renderer_backend_rect,
            gradient_rect = renderer_backend_gradient_rect,
            shadow        = renderer_backend_shadow,
            push_clip     = renderer_backend_push_clip,
            pop_clip      = renderer_backend_pop_clip,
            set_alpha     = renderer_backend_set_alpha,
        },
    }
}

renderer_backend_rect :: proc(state: rawptr, rect: Rect, color: Color, radius: f32) {
    renderer_draw_rect((^Renderer)(state), rect, color, radius)
}

renderer_backend_gradient_rect :: proc(state: rawptr, rect: Rect, c_tl, c_tr, c_br, c_bl: Color, radius: f32) {
    renderer_draw_gradient_rect((^Renderer)(state), rect, c_tl, c_tr, c_br, c_bl, radius)
}

renderer_backend_shadow :: proc(state: rawptr, rect: Rect, radius, blur: f32, color: Color, offset: [2]f32) {
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
```

In `skald/clip.odin`, rename current concrete clip procs:

```odin
push_clip -> renderer_push_clip
pop_clip  -> renderer_pop_clip
```

Then add facade procs:

```odin
push_clip :: proc(r: ^Render_Context, rect: Rect) {
    r.backend.draw.push_clip(r.backend.state, rect)
}

pop_clip :: proc(r: ^Render_Context) {
    r.backend.draw.pop_clip(r.backend.state)
}
```

- [x] **Step 5: Run tests and build one existing example**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
./build.sh 07_counter
```

Expected: tests PASS. `./build.sh 07_counter` may fail at this point because layout still passes `^Renderer` to draw procs; record the first compile error for Task 4.

- [x] **Step 6: Commit**

```bash
git add skald/backend.odin skald/draw.odin skald/clip.odin skald/backend_fake_test.odin
git commit -m "refactor: add renderer backend compatibility facade" -- skald/backend.odin skald/draw.odin skald/clip.odin skald/backend_fake_test.odin
```

## Task 4: Migrate Layout to Render_Context

Status: complete in commits `6455f7e`, `b2f906f`, `200b2d6`, and `36309e9`.

**Files:**
- Modify: `skald/layout.odin`
- Modify: `skald/app.odin`
- Modify: `skald/inspector.odin`

- [x] **Step 1: Replace layout signatures**

In `skald/layout.odin`, replace these signatures:

```odin
view_height_for_width :: proc(r: ^Renderer, v: View, width: f32) -> f32
view_size             :: proc(r: ^Renderer, v: View) -> [2]f32
render_view           :: proc(r: ^Renderer, v: View, origin: [2]f32, assigned: [2]f32)
render_overlays       :: proc(r: ^Renderer)
```

with:

```odin
view_height_for_width :: proc(r: ^Render_Context, v: View, width: f32) -> f32
view_size             :: proc(r: ^Render_Context, v: View) -> [2]f32
render_view           :: proc(r: ^Render_Context, v: View, origin: [2]f32, assigned: [2]f32)
render_overlays       :: proc(r: ^Render_Context)
```

Apply the same replacement to every private layout helper in `layout.odin` that only needs measuring, drawing, overlays, clips, or alpha.

- [x] **Step 2: Add Render_Context construction in app loop**

In `skald/app.odin`, inside the per-target render block before `app.view`, add:

```odin
backend := renderer_backend(&r)
rc := render_context_from_backend(&backend)
```

Then change:

```odin
renderer   = &r,
render_view(&r, v, {0, 0}, win_size)
render_overlays(&r)
```

to:

```odin
renderer   = &r,
render_view(&rc, v, {0, 0}, win_size)
render_overlays(&rc)
```

Keep `Ctx.renderer: ^Renderer` unchanged in this task so widgets that measure text through the old field still compile. Text migration happens in Task 5.

- [x] **Step 3: Update inspector draw calls**

In `skald/inspector.odin`, keep `inspector_render` on `^Renderer` for now and add a local context:

```odin
backend := renderer_backend(r)
rc := render_context_from_backend(&backend)
```

Change inspector draw calls from `draw_rect(r, ...)` and `draw_text(r, ...)` to use `&rc` once Task 5 provides text facade support. In this task, only migrate rect calls that already compile.

- [x] **Step 4: Build existing examples**

Run:

```bash
./build.sh 07_counter
./build.sh 10_scroll
```

Expected: both build successfully or fail only on text facade signatures that Task 5 addresses. If there are non-text failures, fix this task before continuing.

- [x] **Step 5: Commit**

```bash
git add skald/layout.odin skald/app.odin skald/inspector.odin
git commit -m "refactor: render layout through backend context"
```

## Task 5: Text Service Facade

Status: complete in commits `f8afa6f`, `03ab056`, `53a2579`, `3e65bc9`, and `52bcb82`.

**Files:**
- Modify: `skald/backend.odin`
- Modify: `skald/text.odin`
- Modify: `skald/text_runa.odin`
- Modify: `skald/app.odin`
- Modify: `skald/view.odin`

- [x] **Step 1: Add fake text test**

Append to `skald/backend_fake_test.odin`:

```odin
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

fake_measure_text :: proc(state: rawptr, text: string, size: f32, font: Font) -> (f32, f32) {
    return f32(len(text)) * size, size
}
```

- [x] **Step 2: Add Render_Context text APIs**

In `skald/text.odin`, keep existing `measure_text`, `draw_text`, `wrap_text`, and `text_ascent` as `^Renderer` compatibility procs. Add context variants:

```odin
measure_text_ctx :: proc(r: ^Render_Context, text: string, size: f32, font: Font = 0) -> (f32, f32) {
    return r.backend.text.measure(r.backend.state, text, size, font)
}

draw_text_ctx :: proc(r: ^Render_Context, text: string, x, y: f32, color: Color, size: f32, font: Font = 0) {
    r.backend.text.draw(r.backend.state, text, x, y, color, size, font)
}

wrap_text_ctx :: proc(r: ^Render_Context, text: string, max_width, size: f32, font: Font = 0) -> []string {
    return r.backend.text.wrap(r.backend.state, text, max_width, size, font)
}

text_ascent_ctx :: proc(r: ^Render_Context, size: f32, font: Font = 0) -> f32 {
    return r.backend.text.ascent(r.backend.state, size, font)
}
```

- [x] **Step 3: Wire existing renderer text service**

Append to `renderer_backend` in `skald/backend.odin`:

```odin
text = Backend_Text{
    load_font = renderer_backend_font_load,
    measure   = renderer_backend_measure_text,
    wrap      = renderer_backend_wrap_text,
    ascent    = renderer_backend_text_ascent,
    draw      = renderer_backend_draw_text,
},
```

Add wrappers:

```odin
renderer_backend_font_load :: proc(state: rawptr, name: string, data: []byte) -> Font {
    return font_load((^Renderer)(state), name, data)
}

renderer_backend_measure_text :: proc(state: rawptr, text: string, size: f32, font: Font) -> (f32, f32) {
    return measure_text((^Renderer)(state), text, size, font)
}

renderer_backend_wrap_text :: proc(state: rawptr, text: string, max_width, size: f32, font: Font) -> []string {
    return wrap_text((^Renderer)(state), text, max_width, size, font)
}

renderer_backend_text_ascent :: proc(state: rawptr, size: f32, font: Font) -> f32 {
    return text_ascent((^Renderer)(state), size, font)
}

renderer_backend_draw_text :: proc(state: rawptr, text: string, x, y: f32, color: Color, size: f32, font: Font) {
    draw_text((^Renderer)(state), text, x, y, color, size, font)
}
```

- [x] **Step 4: Migrate layout text calls**

In `skald/layout.odin`, replace:

```odin
measure_text(r, ...)
wrap_text(r, ...)
text_ascent(r, ...)
draw_text(r, ...)
```

with:

```odin
measure_text_ctx(r, ...)
wrap_text_ctx(r, ...)
text_ascent_ctx(r, ...)
draw_text_ctx(r, ...)
```

Only change call sites where `r` is now `^Render_Context`.

- [x] **Step 5: Keep widget builder measurement temporarily on old renderer**

In `skald/app.odin`, add a backend-aware render context field to `Ctx`:

```odin
Ctx :: struct($Msg: typeid) {
    theme:   ^Theme,
    labels:  ^Labels,
    input:   ^Input,
    msgs:    ^[dynamic]Msg,
    widgets: ^Widget_Store,
    renderer: ^Renderer,
    render:   ^Render_Context,
    window:   Window_Id,
    breakpoint: Breakpoint,
}
```

In `map_msg` and `map_msg_for`, copy `render = parent_ctx.render`.

In `skald/app.odin`, when constructing `Ctx` in `run`, set both fields:

```odin
renderer = &r,
render   = &rc,
```

In `skald/view.odin`, replace builder-time text measurement calls:

```odin
measure_text(ctx.renderer, text, size, font)
wrap_text(ctx.renderer, text, max_width, size, font)
text_ascent(ctx.renderer, size, font)
```

with helper calls:

```odin
ctx_measure_text :: proc(ctx: ^Ctx($Msg), text: string, size: f32, font: Font = 0) -> (f32, f32) {
    if ctx.render != nil { return measure_text_ctx(ctx.render, text, size, font) }
    return measure_text(ctx.renderer, text, size, font)
}

ctx_wrap_text :: proc(ctx: ^Ctx($Msg), text: string, max_width, size: f32, font: Font = 0) -> []string {
    if ctx.render != nil { return wrap_text_ctx(ctx.render, text, max_width, size, font) }
    return wrap_text(ctx.renderer, text, max_width, size, font)
}

ctx_text_ascent :: proc(ctx: ^Ctx($Msg), size: f32, font: Font = 0) -> f32 {
    if ctx.render != nil { return text_ascent_ctx(ctx.render, size, font) }
    return text_ascent(ctx.renderer, size, font)
}
```

Then use `ctx_measure_text`, `ctx_wrap_text`, and `ctx_text_ascent` at widget builder sites.

- [x] **Step 6: Run tests and examples**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
./build.sh 07_counter
./build.sh 08_text_input
```

Expected: tests PASS and both examples build.

- [x] **Step 7: Commit**

```bash
git add skald/backend.odin skald/text.odin skald/text_runa.odin skald/layout.odin skald/backend_fake_test.odin
git commit -m "refactor: route layout text through backend service"
```

## Task 6: Image Service Facade

Status: complete in commits `acf07df`, `bf4e59a`, and `3c266ce`.

**Files:**
- Modify: `skald/backend.odin`
- Modify: `skald/image.odin`
- Modify: `skald/layout.odin`
- Modify: `skald/view.odin`

- [x] **Step 1: Add backend image wrappers**

In `skald/image.odin`, add context variants while keeping existing `^Renderer` APIs:

```odin
image_load_pixels_ctx :: proc(r: ^Render_Context, name: string, w, h: u32, rgba: []u8) -> Backend_Image {
    return r.backend.images.load_pixels(r.backend.state, name, w, h, rgba)
}

image_update_pixels_ctx :: proc(r: ^Render_Context, image: Backend_Image, w, h: u32, rgba: []u8) -> bool {
    return r.backend.images.update_pixels(r.backend.state, image, w, h, rgba)
}

draw_image_ctx :: proc(r: ^Render_Context, image: Backend_Image, rect: Rect, tint: Color = Color{1, 1, 1, 1}) {
    r.backend.images.draw(r.backend.state, image, rect, tint)
}
```

- [x] **Step 2: Add existing renderer image service**

In `skald/backend.odin`, add to `renderer_backend`:

```odin
images = Backend_Images{
    load_path     = renderer_backend_image_load_path,
    load_pixels   = renderer_backend_image_load_pixels,
    update_pixels = renderer_backend_image_update_pixels,
    unload        = renderer_backend_image_unload,
    draw          = renderer_backend_image_draw,
},
```

Add wrappers:

```odin
renderer_backend_image_load_path :: proc(state: rawptr, path: string) -> Backend_Image {
    entry := image_cache_get((^Renderer)(state), path)
    return Backend_Image(entry)
}

renderer_backend_image_load_pixels :: proc(state: rawptr, name: string, w, h: u32, rgba: []u8) -> Backend_Image {
    r := (^Renderer)(state)
    if !image_load_pixels(r, name, w, h, rgba) { return nil }
    return Backend_Image(image_cache_get(r, name))
}

renderer_backend_image_update_pixels :: proc(state: rawptr, image: Backend_Image, w, h: u32, rgba: []u8) -> bool {
    return false
}

renderer_backend_image_unload :: proc(state: rawptr, image: Backend_Image) {}

renderer_backend_image_draw :: proc(state: rawptr, image: Backend_Image, rect: Rect, tint: Color) {
    // The current View_Image path still uses path lookup. Keep this wrapper for custom image handles.
}
```

The two no-op wrappers are temporary compatibility shims for handle-based APIs. Path-based image rendering still works through existing `View_Image` until the Karl2D adapter uses the handle API.

- [x] **Step 3: Migrate View_Image render path**

In `skald/layout.odin`, when rendering `View_Image`, replace direct Vulkan image cache access with:

```odin
img := r.backend.images.load_path(r.backend.state, vv.path)
if img != nil {
    r.backend.images.draw(r.backend.state, img, target_rect, Color{1, 1, 1, 1})
} else {
    draw_rect(r, target_rect, rgb(0xFF00FF), 0)
}
```

Use the existing target rect and fit calculation already present in the file.

- [x] **Step 4: Run image example**

Run:

```bash
./build.sh 20_image
```

Expected: build succeeds and the example opens with the image visible when run manually.

- [x] **Step 5: Commit**

```bash
git add skald/backend.odin skald/image.odin skald/layout.odin skald/view.odin
git commit -m "refactor: route view images through backend service"
```

## Task 7: Karl2D Backend Package Skeleton

Status: complete in commit `1820b3c`.

**Files:**
- Create: `skald_karl2d/backend.odin`
- Create: `skald_karl2d/input.odin`
- Create: `skald_karl2d/embedded.odin`

- [x] **Step 1: Create package skeleton**

Create `skald_karl2d/backend.odin`:

```odin
package skald_karl2d

import skald "gui:skald"
import k2 "gui:karl2d"
import "core:time"

Backend_State :: struct {
    input:        skald.Input,
    capture:      skald.Input_Capture,
    capture_next: skald.Input_Capture,
    frame_state:  skald.Capture_Frame_State,
}

backend :: proc(state: ^Backend_State) -> skald.Backend {
    return skald.Backend{
        state = state,
        capabilities = {},
        draw = skald.Backend_Draw{
            rect          = draw_rect,
            gradient_rect = draw_gradient_rect,
            shadow        = draw_shadow,
            push_clip     = push_clip,
            pop_clip      = pop_clip,
            set_alpha     = set_alpha,
        },
        input = skald.Backend_Input{
            snapshot = input_snapshot,
            capture  = input_capture,
        },
        window = skald.Backend_Window{
            size           = window_size,
            scale          = window_scale,
            set_text_input = set_text_input,
        },
        time = skald.Backend_Time{now_ns = now_ns},
    }
}

to_k2_color :: proc(c: skald.Color) -> k2.Color {
    r := u8(clamp01(c[0]) * 255 + 0.5)
    g := u8(clamp01(c[1]) * 255 + 0.5)
    b := u8(clamp01(c[2]) * 255 + 0.5)
    a := u8(clamp01(c[3]) * 255 + 0.5)
    return {r, g, b, a}
}

clamp01 :: proc(v: f32) -> f32 {
    if v < 0 { return 0 }
    if v > 1 { return 1 }
    return v
}

draw_rect :: proc(state: rawptr, rect: skald.Rect, color: skald.Color, radius: f32) {
    k2.draw_rect({rect.x, rect.y, rect.w, rect.h}, to_k2_color(color))
}

draw_gradient_rect :: proc(state: rawptr, rect: skald.Rect, c_tl, c_tr, c_br, c_bl: skald.Color, radius: f32) {
    k2.draw_rect({rect.x, rect.y, rect.w, rect.h}, to_k2_color(c_tl))
}

draw_shadow :: proc(state: rawptr, rect: skald.Rect, radius, blur: f32, color: skald.Color, offset: [2]f32) {
    if color[3] <= 0 { return }
    k2.draw_rect({rect.x + offset.x, rect.y + offset.y, rect.w, rect.h}, to_k2_color(color))
}

push_clip :: proc(state: rawptr, rect: skald.Rect) {
    k2.set_scissor_rect(k2.Rect{rect.x, rect.y, rect.w, rect.h})
}

pop_clip :: proc(state: rawptr) {
    k2.set_scissor_rect(nil)
}

set_alpha :: proc(state: rawptr, alpha: f32) {}

window_size :: proc(state: rawptr) -> skald.Size {
    return {i32(k2.get_screen_width()), i32(k2.get_screen_height())}
}

window_scale :: proc(state: rawptr) -> f32 {
    return k2.get_window_scale()
}

set_text_input :: proc(state: rawptr, on: bool) {}

now_ns :: proc(state: rawptr) -> i64 {
    return time.now()._nsec
}
```

Create `skald_karl2d/input.odin`:

```odin
package skald_karl2d

import skald "gui:skald"
import k2 "gui:karl2d"

input_snapshot :: proc(state: rawptr) -> skald.Input {
    s := (^Backend_State)(state)
    return s.input
}

input_capture :: proc(state: rawptr) -> skald.Input_Capture {
    s := (^Backend_State)(state)
    return s.capture
}

translate_input :: proc(s: ^Backend_State) {
    mouse := k2.get_mouse_position()
    delta := k2.get_mouse_delta()
    s.input = skald.Input{
        mouse_pos   = {mouse.x, mouse.y},
        mouse_delta = {delta.x, delta.y},
        scroll      = {0, k2.get_mouse_wheel_delta()},
    }

    s.input.mouse_buttons[.Left]  = k2.mouse_button_is_held(.Left)
    s.input.mouse_pressed[.Left]  = k2.mouse_button_went_down(.Left)
    s.input.mouse_released[.Left] = k2.mouse_button_went_up(.Left)

    s.input.keys_down = keys_down_from_karl2d()
    s.input.keys_pressed = keys_pressed_from_karl2d()
    s.input.modifiers = modifiers_from_karl2d()
}
```

Create `skald_karl2d/embedded.odin`:

```odin
package skald_karl2d

import skald "gui:skald"
import k2 "gui:karl2d"

Context :: struct($State, $Msg: typeid) {
    app:     skald.App(State, Msg),
    backend_state: Backend_State,
    backend: skald.Backend,
    rc:      skald.Render_Context,
    msgs:    [dynamic]Msg,
    widgets: skald.Widget_Store,
}

init :: proc(ctx: ^Context($State, $Msg), app: skald.App(State, Msg)) {
    ctx.app = app
    ctx.theme = app.theme
    ctx.labels = app.labels
    if len(ctx.labels.month_names[0]) == 0 { ctx.labels = skald.labels_en() }
    ctx.backend = backend(&ctx.backend_state)
    ctx.rc = skald.render_context_from_backend(&ctx.backend)
    skald.widget_store_init(&ctx.widgets)
    _ = skald.embedded_runtime_init(&ctx.runtime)
}

shutdown :: proc(ctx: ^Context($State, $Msg)) {
    skald.embedded_runtime_destroy(&ctx.runtime)
    skald.widget_store_destroy(&ctx.widgets)
    delete(ctx.msgs)
}

capture :: proc(ctx: ^Context($State, $Msg)) -> skald.Input_Capture {
    return ctx.backend_state.capture
}
```

- [x] **Step 2: Run package build and fix import-level errors**

Run:

```bash
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Result: passes. The package is a library, so `-no-entry-point` is required. The initial key/modifier helpers intentionally return empty sets and are completed in Task 8.

- [x] **Step 3: Commit skeleton**

```bash
git add skald_karl2d
git commit -m "feat: add karl2d backend package skeleton"
```

## Task 8: Karl2D Input Translation

**Files:**
- Modify: `skald_karl2d/input.odin`

- [ ] **Step 1: Implement key translation helpers**

Add to `skald_karl2d/input.odin`:

```odin
key_pairs :: [?]struct{k2_key: k2.Keyboard_Key, skald_key: skald.Key}{
    {.Backspace, .Backspace}, {.Delete, .Delete},
    {.Left, .Left}, {.Right, .Right}, {.Up, .Up}, {.Down, .Down},
    {.Home, .Home}, {.End, .End}, {.Page_Up, .Page_Up}, {.Page_Down, .Page_Down},
    {.Enter, .Enter}, {.Tab, .Tab}, {.Escape, .Escape}, {.Space, .Space},
    {.A, .A}, {.B, .B}, {.C, .C}, {.D, .D}, {.E, .E}, {.F, .F}, {.G, .G},
    {.H, .H}, {.I, .I}, {.J, .J}, {.K, .K}, {.L, .L}, {.M, .M}, {.N, .N},
    {.O, .O}, {.P, .P}, {.Q, .Q}, {.R, .R}, {.S, .S}, {.T, .T}, {.U, .U},
    {.V, .V}, {.W, .W}, {.X, .X}, {.Y, .Y}, {.Z, .Z},
    {.N0, .N0}, {.N1, .N1}, {.N2, .N2}, {.N3, .N3}, {.N4, .N4},
    {.N5, .N5}, {.N6, .N6}, {.N7, .N7}, {.N8, .N8}, {.N9, .N9},
    {.F1, .F1}, {.F2, .F2}, {.F3, .F3}, {.F4, .F4}, {.F5, .F5}, {.F6, .F6},
    {.F7, .F7}, {.F8, .F8}, {.F9, .F9}, {.F10, .F10}, {.F11, .F11}, {.F12, .F12},
    {.Minus, .Minus}, {.Equal, .Equals}, {.Left_Bracket, .Left_Bracket},
    {.Right_Bracket, .Right_Bracket}, {.Semicolon, .Semicolon},
    {.Apostrophe, .Apostrophe}, {.Comma, .Comma}, {.Period, .Period},
    {.Slash, .Slash}, {.Backslash, .Backslash}, {.Backtick, .Grave},
}

keys_down_from_karl2d :: proc() -> skald.Keys {
    out: skald.Keys
    for p in key_pairs {
        if k2.key_is_held(p.k2_key) { out += {p.skald_key} }
    }
    return out
}

keys_pressed_from_karl2d :: proc() -> skald.Keys {
    out: skald.Keys
    for p in key_pairs {
        if k2.key_went_down(p.k2_key) { out += {p.skald_key} }
    }
    return out
}

modifiers_from_karl2d :: proc() -> skald.Modifiers {
    out: skald.Modifiers
    mods := k2.get_held_modifiers()
    if .Shift in mods   { out += {.Shift} }
    if .Control in mods { out += {.Ctrl} }
    if .Alt in mods     { out += {.Alt} }
    if .Super in mods   { out += {.Super} }
    return out
}
```

- [ ] **Step 2: Check package**

Run:

```bash
odin check ./skald_karl2d -collection:gui=.
```

Expected: package check succeeds or reports missing text/image services that Task 10 adds. Fix only input translation errors in this task.

- [ ] **Step 3: Commit**

```bash
git add skald_karl2d/input.odin
git commit -m "feat: translate karl2d input to skald input"
```

## Task 9: Embedded Frame and Message Processing

**Files:**
- Modify: `skald_karl2d/embedded.odin`
- Create: `skald/embedded_runtime.odin`
- Modify: `skald/backend.odin`
- Modify: `skald/app.odin`

- [ ] **Step 1: Add Skald-owned embedded command runtime**

Create `skald/embedded_runtime.odin`:

```odin
package skald

import "core:nbio"

Embedded_Runtime :: struct($Msg: typeid) {
    pending: [dynamic]Pending_Delay(Msg),
    io:      Io_State(Msg),
    tpool:   Thread_Pool(Msg),
}

embedded_runtime_init :: proc(rt: ^Embedded_Runtime($Msg)) -> bool {
    if err := nbio.acquire_thread_event_loop(); err != nil {
        return false
    }
    io_state_init(&rt.io, nil)
    thread_pool_init(&rt.tpool)
    return true
}

embedded_runtime_destroy :: proc(rt: ^Embedded_Runtime($Msg)) {
    thread_pool_destroy(&rt.tpool)
    io_state_destroy(&rt.io)
    delete(rt.pending)
    nbio.release_thread_event_loop()
}

embedded_runtime_begin_frame :: proc(rt: ^Embedded_Runtime($Msg), msgs: ^[dynamic]Msg) {
    drain_due_delays(&rt.pending, msgs)
    nbio.tick(0)
    drain_io(&rt.io, msgs)
    _ = thread_pool_drain(&rt.tpool, msgs)
}

embedded_runtime_drain_messages :: proc(
    rt: ^Embedded_Runtime($Msg),
    state: State,
    app: App(State, Msg),
    msgs: ^[dynamic]Msg,
    th: ^Theme,
) -> State {
    out := state
    for len(msgs^) > 0 {
        frame_msgs := make([dynamic]Msg, context.temp_allocator)
        for msg in msgs^ { append(&frame_msgs, msg) }
        clear(msgs)
        for msg in frame_msgs {
            new_state, cmd := app.update(out, msg)
            out = new_state
            process_command(cmd, msgs, &rt.pending, &rt.io, nil, &rt.tpool, th)
        }
    }
    return out
}
```

In `skald/command.odin`, update the window-op branch in `process_command` so embedded runtimes can pass nil:

```odin
case .Open_Window, .Close_Window:
    if cmd.window_op != nil && windows_pending != nil {
        append(windows_pending, cmd.window_op^)
    }
}
```

- [ ] **Step 2: Implement embedded frame**

In `skald_karl2d/embedded.odin`, add fields to `Context`:

```odin
state_initialized: bool,
runtime: skald.Embedded_Runtime(Msg),
theme:   skald.Theme,
labels:  skald.Labels,
```

Add:

```odin
frame :: proc(ctx: ^Context($State, $Msg), state: State) {
    skald.embedded_runtime_begin_frame(&ctx.runtime, &ctx.msgs)
    translate_input(&ctx.backend_state)
    skald.widget_store_frame_reset(&ctx.widgets)

    input := ctx.backend_state.input
    c := skald.Ctx(Msg){
        theme      = &ctx.theme,
        labels     = &ctx.labels,
        input      = &input,
        msgs       = &ctx.msgs,
        widgets    = &ctx.widgets,
        renderer   = nil,
        render     = &ctx.rc,
        window     = nil,
        breakpoint = skald.breakpoint(f32(k2.get_screen_width())),
    }

    v := ctx.app.view(state, &c)
    size := [2]f32{f32(k2.get_screen_width()), f32(k2.get_screen_height())}
    skald.render_view(&ctx.rc, v, {0, 0}, size)
    skald.render_overlays(&ctx.rc)

    ctx.backend_state.capture_next = skald.input_capture_from_frame(input, ctx.backend_state.frame_state)
    ctx.backend_state.capture = ctx.backend_state.capture_next
}

drain_messages :: proc(ctx: ^Context($State, $Msg), state: State) -> State {
    return skald.embedded_runtime_drain_messages(&ctx.runtime, state, ctx.app, &ctx.msgs, &ctx.theme)
}
```

If `breakpoint_for_width` is private, add a public wrapper in `skald/app.odin`:

```odin
breakpoint :: proc(width: f32) -> Breakpoint {
    return breakpoint_for_width(width)
}
```

and call `skald.breakpoint(...)`.

- [ ] **Step 3: Check embedded package**

Run:

```bash
odin check ./skald_karl2d -collection:gui=.
```

Expected: check succeeds after adjusting access to exported Skald helpers. If private Skald types block this task, export the smallest required helper instead of making whole subsystems public.

- [ ] **Step 4: Commit**

```bash
git add skald/app.odin skald_karl2d/embedded.odin
git commit -m "feat: add embedded skald frame loop"
```

## Task 10: Karl2D Text and Image Services

**Files:**
- Modify: `skald_karl2d/backend.odin`
- Create: `skald_karl2d/text.odin`
- Create: `skald_karl2d/image.odin`

- [ ] **Step 1: Implement Karl2D text compatibility service**

Create `skald_karl2d/text.odin`:

```odin
package skald_karl2d

import skald "gui:skald"
import k2 "gui:karl2d"
import "core:strings"

k2_measure_text :: proc(state: rawptr, text: string, size: f32, font: skald.Font) -> (f32, f32) {
    v := k2.measure_text(text, size)
    return v.x, v.y
}

k2_draw_text :: proc(state: rawptr, text: string, x, y: f32, color: skald.Color, size: f32, font: skald.Font) {
    k2.draw_text(text, {x, y}, size, to_k2_color(color))
}

k2_text_ascent :: proc(state: rawptr, size: f32, font: skald.Font) -> f32 {
    return size
}

k2_wrap_text :: proc(state: rawptr, text: string, max_width, size: f32, font: skald.Font) -> []string {
    words := strings.fields(text, context.temp_allocator)
    lines := make([dynamic]string, context.temp_allocator)
    line := ""
    for word in words {
        candidate := word if len(line) == 0 else strings.concatenate({line, " ", word}, context.temp_allocator)
        w, _ := k2_measure_text(state, candidate, size, font)
        if w > max_width && len(line) > 0 {
            append(&lines, line)
            line = word
        } else {
            line = candidate
        }
    }
    if len(line) > 0 { append(&lines, line) }
    return lines[:]
}
```

In `skald_karl2d/backend.odin`, add:

```odin
text = skald.Backend_Text{
    measure = k2_measure_text,
    wrap    = k2_wrap_text,
    ascent  = k2_text_ascent,
    draw    = k2_draw_text,
},
```

- [ ] **Step 2: Implement Karl2D image service**

Create `skald_karl2d/image.odin`:

```odin
package skald_karl2d

import skald "gui:skald"
import k2 "gui:karl2d"

Image_Entry :: struct {
    texture: k2.Texture,
}

k2_image_load_path :: proc(state: rawptr, path: string) -> skald.Backend_Image {
    entry := new(Image_Entry)
    entry.texture = k2.load_texture_from_file(path)
    return skald.Backend_Image(entry)
}

k2_image_load_pixels :: proc(state: rawptr, name: string, w, h: u32, rgba: []u8) -> skald.Backend_Image {
    entry := new(Image_Entry)
    entry.texture = k2.load_texture_from_bytes_raw(rgba, int(w), int(h), .RGBA_8_Norm)
    return skald.Backend_Image(entry)
}

k2_image_update_pixels :: proc(state: rawptr, image: skald.Backend_Image, w, h: u32, rgba: []u8) -> bool {
    entry := (^Image_Entry)(rawptr(image))
    return k2.update_texture(entry.texture, rgba, {0, 0, f32(w), f32(h)})
}

k2_image_unload :: proc(state: rawptr, image: skald.Backend_Image) {
    if image == nil { return }
    entry := (^Image_Entry)(rawptr(image))
    k2.destroy_texture(entry.texture)
    free(entry)
}

k2_image_draw :: proc(state: rawptr, image: skald.Backend_Image, rect: skald.Rect, tint: skald.Color) {
    if image == nil { return }
    entry := (^Image_Entry)(rawptr(image))
    k2.draw_texture_fit(entry.texture, k2.get_texture_rect(entry.texture), {rect.x, rect.y, rect.w, rect.h}, tint = to_k2_color(tint))
}
```

In `skald_karl2d/backend.odin`, add:

```odin
images = skald.Backend_Images{
    load_path     = k2_image_load_path,
    load_pixels   = k2_image_load_pixels,
    update_pixels = k2_image_update_pixels,
    unload        = k2_image_unload,
    draw          = k2_image_draw,
},
```

- [ ] **Step 3: Check package**

Run:

```bash
odin check ./skald_karl2d -collection:gui=.
```

Expected: check succeeds.

- [ ] **Step 4: Commit**

```bash
git add skald_karl2d/backend.odin skald_karl2d/text.odin skald_karl2d/image.odin
git commit -m "feat: add karl2d text and image backend services"
```

## Task 11: Karl2D Overlay Example

**Files:**
- Create: `examples/50_karl2d_overlay/main.odin`
- Modify: `build.sh`

- [ ] **Step 1: Create example**

Create `examples/50_karl2d_overlay/main.odin`:

```odin
package karl2d_overlay

import "core:fmt"
import skald "gui:skald"
import skald_k2 "gui:skald_karl2d"
import k2 "gui:karl2d"

State :: struct {
    clicks: int,
    text:   string,
}

Msg :: union {
    Button_Clicked,
    Text_Changed: string,
}

init :: proc() -> State {
    return {text = "Skald over Karl2D"}
}

update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) {
    out := s
    switch v in m {
    case Button_Clicked:
        out.clicks += 1
    case Text_Changed:
        out.text = v
    }
    return out, {}
}

on_button :: proc() -> Msg { return Button_Clicked{} }
on_text :: proc(v: string) -> Msg { return Text_Changed(v) }

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
    th := ctx.theme
    return skald.col(
        skald.text("Skald overlay", th.color.fg, th.font.size_lg),
        skald.text(fmt.tprintf("UI clicks: %d", s.clicks), th.color.muted, th.font.size_md),
        skald.button(ctx, "UI button", on_button(), width = 180),
        skald.text_input(ctx, s.text, on_text, width = 280),
        padding = th.spacing.lg,
        spacing = th.spacing.md,
    )
}

main :: proc() {
    k2.init(1280, 720, "Skald Karl2D Overlay", {window_mode = .Windowed_Resizable})
    defer k2.shutdown()

    app := skald.App(State, Msg){
        title  = "Skald Karl2D Overlay",
        size   = {1280, 720},
        theme  = skald.theme_dark(),
        init   = init,
        update = update,
        view   = view,
    }

    state := app.init()
    ui: skald_k2.Context(State, Msg)
    skald_k2.init(&ui, app)
    defer skald_k2.shutdown(&ui)

    player := k2.Vec2{640, 360}

    for k2.update() {
        capture := skald_k2.capture(&ui)
        if !capture.keyboard {
            if k2.key_is_held(.A) { player.x -= 4 }
            if k2.key_is_held(.D) { player.x += 4 }
            if k2.key_is_held(.W) { player.y -= 4 }
            if k2.key_is_held(.S) { player.y += 4 }
        }

        k2.clear(k2.DARK_BLUE)
        k2.draw_circle(player, 24, k2.LIGHT_GREEN)
        k2.draw_text("WASD moves only when Skald does not capture keyboard", {24, 680}, 24, k2.WHITE)

        skald_k2.frame(&ui, state)
        state = skald_k2.drain_messages(&ui, state)

        k2.present()
        free_all(context.temp_allocator)
    }
}
```

- [ ] **Step 2: Build example**

Run:

```bash
odin build examples/50_karl2d_overlay -collection:gui=. -debug -out:build/50_karl2d_overlay
```

Expected: build succeeds.

- [ ] **Step 3: Run manual smoke test**

Run:

```bash
./build/50_karl2d_overlay
```

Expected:

- WASD moves the green circle when no Skald text field is focused.
- Clicking the Skald button increments the UI counter.
- Focusing the text input captures keyboard input so WASD no longer moves the circle.
- Clicking outside the Skald UI returns keyboard/mouse control to the game.

- [ ] **Step 4: Commit**

```bash
git add examples/50_karl2d_overlay/main.odin build.sh
git commit -m "feat: add karl2d skald overlay example"
```

## Task 12: Verification and Documentation

**Files:**
- Modify: `docs/architecture.md`
- Modify: `README.md`
- Modify: `docs/examples.md`

- [ ] **Step 1: Document embedded backend**

Add a short section to `docs/architecture.md` after "Rendering pipeline":

```markdown
## Backend services

Skald's UI core can render through backend services instead of talking
directly to a windowing or graphics API. The current desktop runtime wraps
the existing SDL3/Vulkan renderer through a compatibility backend. The
Karl2D adapter implements the same service shape for embedded overlays:
Karl2D owns the window, event pump, game draw, and present call; Skald
builds and renders a UI tree inside that loop and reports input capture
flags so uncaptured input remains available to game systems.
```

- [ ] **Step 2: Add README note**

Add under README "Highlights":

```markdown
- **Embeddable backend path** — Skald can be hosted by Karl2D as an
  overlay UI layer. The host game owns the window and game rendering;
  Skald reports mouse/keyboard/text capture so game systems receive only
  uncaptured input.
```

- [ ] **Step 3: Add example index entry**

Add to `docs/examples.md`:

```markdown
- `50_karl2d_overlay` — Karl2D game loop with a Skald overlay. Shows
  keyboard pass-through, UI capture, a button, and text input.
```

- [ ] **Step 4: Full verification**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
odin check ./skald_karl2d -collection:gui=.
./build.sh 07_counter
./build.sh 08_text_input
odin build examples/50_karl2d_overlay -collection:gui=. -debug -out:build/50_karl2d_overlay
```

Expected: all commands exit 0.

- [ ] **Step 5: Commit docs**

```bash
git add docs/architecture.md README.md docs/examples.md
git commit -m "docs: document karl2d embedded backend"
```

## Risks and Checkpoints

- The refactor touches hot files (`layout.odin`, `text.odin`, `image.odin`). After each task, build at least one existing Skald example before continuing.
- `Ctx.renderer` is still typed as `^Renderer`. The embedded path sets it to nil until builder-time measurement is migrated to backend services. Widgets that require builder-time measurement may need follow-up changes before the overlay example works.
- Karl2D's text compatibility service is intentionally lower fidelity than Skald/runa. Treat it as a stepping stone; do not claim full Skald text fidelity until runa atlas upload is wired through Karl2D textures.
- If Karl2D lacks enough public scissor or texture update control, add the smallest public helper to Karl2D rather than reaching into backend globals from `skald_karl2d`.
