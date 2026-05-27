# Karl2D Game Loop Frame Split Design

## Summary

Skald's Karl2D embedded backend should keep the existing single-call
`skald_karl2d.frame(&ui)` API and add a split frame API for game loops:
`begin_frame(&ui)` before game update, and `end_frame(&ui)` after game draw.

The split API lets games ask Skald which inputs are captured before they
advance simulation, while still rendering Skald after the game scene so UI
appears as an overlay. The existing all-in-one API remains a convenience
wrapper for apps that do not need this ordering.

## Problem

The current embedded example draws the Karl2D scene, calls
`skald_karl2d.frame(&ui)`, then reads `skald_karl2d.capture(&ui)`. That works
for a simple overlay, but it is awkward for normal game loops:

- Game input gating happens after game drawing.
- Game movement applied after draw is visible one frame later.
- Callers cannot use Skald capture before simulation without rendering Skald
  too early or adding their own stale-state workaround.

Skald already uses previous-frame rectangles for hit testing and input capture.
The embedded API should expose that model directly instead of forcing callers
to discover it through call ordering.

## Goals

- Preserve `skald_karl2d.frame(&ui)` for existing code.
- Add a game-loop-friendly ordering that exposes capture before game update.
- Keep Skald UI rendering after game rendering.
- Avoid a second layout/render pass.
- Keep `capture(&ui)` valid after both `begin_frame(&ui)` and `frame(&ui)`.
- Keep the public lifecycle hard to misuse.

## Non-Goals

- Changing the core `skald.run` frame order.
- Removing Skald's one-frame hit-test/layout model.
- Adding a current-frame layout-only prepass.
- Adding public `draw` and `end` calls that must always be adjacent.
- Redesigning Karl2D input processing.

## Public API

The existing convenience API remains:

```odin
skald_karl2d.frame(&ui)
```

The new split API is:

```odin
skald_karl2d.begin_frame(&ui)
capture := skald_karl2d.capture(&ui)

game_update(capture)
game_draw()

skald_karl2d.end_frame(&ui)
k2.present()
```

`frame(&ui)` becomes the compatibility wrapper:

```odin
frame :: proc(ctx: ^Context($State, $Msg)) {
    begin_frame(ctx)
    end_frame(ctx)
}
```

## Semantics

### `begin_frame`

`begin_frame` prepares Skald's embedded UI state for the host frame. It:

- Ticks the embedded command runtime and drains due async work into the Skald
  message queue.
- Translates current Karl2D input into `skald.Input`.
- Resets per-frame widget state with `widget_store_frame_reset`.
- Applies outside-click focus preprocessing.
- Clears the overlay queue for the upcoming render.
- Updates render context size and scale.
- Computes `Input_Capture` from current input plus the latest known widget,
  overlay, scroll, modal, focus, and drag state.

It does not render, present, clear the game scene, or drain app messages.

### `capture`

`capture(&ui)` returns the most recently computed capture flags.

For split game loops, callers read it after `begin_frame(&ui)` and before
game update. The value is based on current input and previously known UI
geometry, matching Skald's existing previous-rect hit-testing contract.

For existing all-in-one callers, `capture(&ui)` remains meaningful after
`frame(&ui)`.

### `end_frame`

`end_frame` finishes the Skald part of the host frame. It:

- Builds the app view using the input snapshot prepared by `begin_frame`.
- Renders the view through the Karl2D backend over the already-drawn game
  scene.
- Renders overlays.
- Updates backend text-input mode intent from `widgets.wants_text_input`.
- Refreshes capture after rendering for compatibility with callers that read
  capture after `frame(&ui)`.
- Drains queued Skald messages through `app.update`.
- Resets the frame temp allocator.

It does not call `k2.present()`.

## State Model

The implementation should add a small lifecycle flag to the embedded context
so `end_frame` can detect being called without `begin_frame`. `end_frame`
must assert that a frame is active; it must not implicitly call
`begin_frame`, because doing so would hide an invalid host loop ordering.
The public examples should always call the lifecycle correctly.

`Backend_State.capture_next` is currently present but unused. Remove that
field and keep a single authoritative capture value returned by
`capture(&ui)`.

Capture data must not store slices allocated from `context.temp_allocator`
across frames. Store only the final `Input_Capture` booleans in backend state.

## Example Update

`examples/50_karl2d_overlay` should move to the split API:

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

    skald_k2.end_frame(&ui)
    k2.present()
}
```

This shows the intended game ordering directly: input gate, simulation, game
draw, UI overlay draw, present.

## Testing

Implementation should verify:

- `odin test ./skald -collection:gui=. -define:SKALD_RUNA=false`
- `odin check ./skald_karl2d -collection:gui=. -no-entry-point`
- `./build.sh 50_karl2d_overlay`

Focused tests should cover capture helpers in `skald` where they are already
unit-testable. The embedded lifecycle itself can be compile-checked through
`skald_karl2d`; interactive pass-through still needs a manual smoke test
because it depends on a live Karl2D window and input.

## Documentation

Update `README.md`, `docs/architecture.md`, and `docs/examples.md` so the
recommended game loop uses `begin_frame`, `capture`, `end_frame`, and
`present` in that order. Keep the single-call `frame(&ui)` documented as the
simple overlay path.
