# Skald Karl2D Embedded Backend Design

## Summary

Skald should support an embedded UI mode for Karl2D applications. In this
mode Karl2D owns the OS window, event pump, game loop, game rendering, and
final present call. Skald runs as a backend-neutral UI layer that can be
called from inside that loop, draws an overlay after game rendering, and
reports which inputs are captured by UI so all other input can continue to
flow to game systems.

The design intentionally focuses on defining backend service interfaces and
implementing the Karl2D adapter. Re-implementing or migrating the current
SDL3/Vulkan backend is out of scope for this effort.

## Goals

- Let a Karl2D app render normal game content and Skald UI in the same
  window.
- Keep the Skald app model familiar: `State`, `Msg`, `init`, `update`, and
  `view`.
- Move direct SDL3/Vulkan dependencies out of the embedded path behind
  backend service interfaces.
- Preserve Skald's widget, layout, theme, command, and text behavior where
  practical.
- Make input ownership explicit: UI-captured input is reported to the game;
  uncaptured input remains available to game systems.
- Leave room for future backends without requiring the current SDL3/Vulkan
  backend to be ported immediately.

## Non-Goals

- Implementing multi-window support for the first Karl2D backend.
- Implementing native open/save/folder dialogs for the first Karl2D backend.
- Rebuilding the current SDL3/Vulkan backend on top of the new interfaces.
- Preserving every debug inspector feature in the first embedded backend.
- Adding gamepad-to-UI navigation in the first implementation.

Gamepad-to-UI focus navigation is a future desired enhancement. The input
interfaces should leave room for it and must not hard-code assumptions that
Skald UI is keyboard-and-mouse only.

## Architecture

Skald should be split into a backend-neutral UI core plus backend services.
The core remains responsible for:

- `App`, `Ctx`, `View`, and public widget APIs.
- Layout, overlay ordering, clipping decisions, and widget state.
- Themes, labels, commands, focus, shortcuts, and input capture decisions.
- Text API semantics used by widgets, including measurement and wrapping.
- Image API semantics, using backend image handles instead of Vulkan handles.

A backend contract supplies concrete services through opaque state and proc
tables:

```odin
Backend :: struct {
    state: rawptr,

    frame:     Backend_Frame,
    draw:      Backend_Draw,
    text:      Backend_Text,
    images:    Backend_Images,
    input:     Backend_Input,
    clipboard: Backend_Clipboard,
    window:    Backend_Window,
    time:      Backend_Time,
}
```

`skald_karl2d` implements these services using Karl2D. The adapter imports
Karl2D; Skald core should not import Karl2D, SDL3, or Vulkan for the
embedded path.

## Embedded API

The embedded runtime should not use `skald.run`, because `run` owns window
creation, event polling, idle waiting, rendering, command processing, and
shutdown. Karl2D applications need explicit calls instead.

Representative shape:

```odin
ui: skald_karl2d.Context(State, Msg)
skald_karl2d.init(&ui, app, allocator)
defer skald_karl2d.shutdown(&ui)

for k2.update() {
    capture := skald_karl2d.capture(&ui)

    if !capture.mouse {
        game_mouse_update()
    }
    if !capture.keyboard {
        game_keyboard_update()
    }

    game_update()
    game_draw()

    skald_karl2d.frame(&ui, state)
    state = skald_karl2d.drain_messages(&ui, state)

    k2.present()
}
```

The adapter owns Skald widget stores, message queues, pending commands,
frame temporary state, image/text caches, and the Skald input snapshot.
Karl2D owns the window, platform event pump, GPU backend, game rendering,
and final present call.

Existing Skald app code should keep the same `init`, `update`, and `view`
shape. The main migration is replacing `skald.run(app)` with an embedded
host loop.

## Backend Services

`Backend_Frame` begins and ends a Skald overlay frame. For Karl2D, frame
begin/end must not create a window, clear the game scene, or present. The
service provides logical size, framebuffer scale, and per-frame scratch
setup.

`Backend_Draw` emits Skald drawing operations: rectangles, rounded
rectangles, gradients, shadows, image quads, clip/scissor pushes, clip
pops, and alpha modulation. Layout should call these services rather than
calling Vulkan-specific draw functions.

`Backend_Text` provides font loading, fallback chains, measurement, wrap,
ascent, and drawing. The preferred Karl2D implementation keeps Skald's
runa behavior and uploads glyph atlas pages through Karl2D textures. A
temporary Karl2D/fontstash mapping is acceptable only as a clearly marked
prototype because it changes shaping, emoji, wrapping, and text-input caret
behavior.

`Backend_Images` loads images from paths, bytes, or raw pixels; updates
pixels; unloads images; and draws backend image handles. Karl2D maps these
handles to `karl2d.Texture`.

`Backend_Input` translates Karl2D events and state into Skald `Input`.
It also feeds capture state back to the host.

`Backend_Clipboard` supports copy, cut, and paste for text widgets. If the
backend cannot provide clipboard support, text editing should degrade
explicitly rather than pretending paste succeeded.

`Backend_Window` reports logical size, scale, focus, and text input mode
intent. Multi-window operations are unsupported for the first Karl2D
backend.

`Backend_Time` provides current time and delay scheduling data needed by
commands, animation deadlines, and caret blinking.

## Input Routing

Skald must not destructively consume Karl2D events. The adapter translates
each frame's Karl2D input into Skald input and reports capture flags:

```odin
Input_Capture :: struct {
    mouse:           bool,
    keyboard:        bool,
    text:            bool,
    wheel:           bool,
    pointer_over_ui: bool,
}
```

Capture rules:

- Mouse is captured when the pointer is over a Skald widget or overlay, a
  Skald drag is active, a modal is open, or a press began inside Skald and
  has not released.
- Keyboard is captured when a Skald widget has focus, a modal/menu/command
  palette is active, or a Skald shortcut matches.
- Text is captured only when Skald wants text input.
- Wheel is captured when the pointer is over a scrollable Skald region or
  active overlay.
- When a capture flag is false, the host game should treat that input as
  available to game systems.

Skald currently uses previous-frame rectangles for hit testing. The
embedded API should therefore expose last-frame capture before game update,
then update capture for the next frame during Skald frame/render. This
matches Skald's existing one-frame input/layout model.

## Rendering, Text, and Images

The backend interface should preserve Skald's visual model where practical.
Karl2D's public drawing API is close enough for a prototype but does not
cover every Skald primitive at full fidelity.

The Karl2D adapter should:

- Map simple rects and image quads to Karl2D drawing.
- Support clips through Karl2D scissor support or a small adapter-level
  scissor wrapper.
- Implement rounded rectangles, gradients, and shadows either through
  helper geometry or a custom Karl2D shader path.
- Represent Skald images as backend handles that wrap Karl2D textures.
- Prefer runa-backed text over Karl2D/fontstash text so existing Skald
  widgets keep consistent measurement, wrapping, caret movement, and emoji
  behavior.
- Defer canvas/custom drawing unless it can be expressed through backend
  draw primitives without special Vulkan assumptions.

## Commands and Lifecycle

The embedded runtime processes Skald commands instead of `skald.run`.

Supported in the first Karl2D backend:

- `cmd_now`
- `cmd_delay`
- `cmd_batch`
- `cmd_thread`
- Async file read/write through `core:nbio`

Optional or degraded in the first Karl2D backend:

- Native file dialogs return cancelled or unsupported results if no backend
  service exists.
- Clipboard-dependent text editing features are disabled or no-op with
  explicit failure when clipboard services are unavailable.

Unsupported in the first Karl2D backend:

- `cmd_open_window`
- `cmd_close_window`
- System theme change callbacks unless Karl2D exposes the needed data.
- Window state persistence callbacks unless Karl2D exposes the needed data.

## Testing

Testing should start with backend-neutral behavior and one concrete Karl2D
example.

- Unit test Karl2D-to-Skald input translation.
- Unit test capture decisions for pointer-over-UI, modal open, active drag,
  focused text field, scroll region, and keyboard focus.
- Add fake-backend contract tests that record draw operations and verify
  layout emits expected operations and clip nesting.
- Add a Karl2D example that draws a moving or interactive game scene below
  Skald controls and demonstrates input pass-through.
- Port examples gradually in this order: counter, text input, scroll,
  select, image.

## Open Implementation Questions

- Whether backend services live directly in `skald/` or in a submodule-like
  internal package with a stable public surface.
- How much of `Renderer` should be renamed to a backend-neutral context
  versus replaced by a new type.
- Whether runa atlas upload through Karl2D needs public Karl2D APIs or a
  small extension to Karl2D texture update behavior.
- How to expose enough scissor control from Karl2D without coupling Skald
  to a specific Karl2D render backend.
