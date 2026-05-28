# Karl2D Gamepad Widget Navigation Design

## Summary

Skald should support built-in gamepad navigation for Skald widgets when used
through the Karl2D embedded backend. The first version is Karl2D-only and
focuses on UI navigation, not raw gamepad input for applications.

Karl2D already provides cross-platform gamepad state: active controller
queries, button pressed/released/held state, axes, and vibration. Skald's
Karl2D adapter should translate that device state into backend-neutral UI
navigation intents. Skald core should own the focus and widget-routing policy,
because it already owns widget IDs, focus state, focusable registration, modal
state, and widget geometry.

## Goals

- Let users navigate Skald widgets with a gamepad in Karl2D embedded apps.
- Use spatial navigation for focus movement instead of linear Tab order.
- Let focused composite widgets handle directions internally before global
  spatial focus movement.
- Keep Karl2D-specific device handling in `skald_karl2d`.
- Keep widget focus/navigation policy in Skald core.
- Report gamepad capture so games can avoid using the same controller input
  for gameplay and UI in the same frame.
- Support controller shortcuts for non-focusable UI actions.

## Non-Goals

- SDL3 backend gamepad support.
- Raw gamepad input exposed to Skald applications.
- Multiple active gamepads or controller assignment.
- User-remappable controls.
- Gamepad vibration or haptics.
- A separate "gamepad focus" independent of existing keyboard/widget focus.

## Current Code Context

Skald's core `Input` currently contains mouse, keyboard, drag-and-drop, and pen
state. It does not contain gamepad input. Skald's backend capability enum has a
`Gamepad_Navigation` placeholder, but no implementation.

`skald_karl2d.translate_input` currently translates Karl2D mouse, wheel, and
keyboard state into `skald.Input`. It does not translate Karl2D gamepad state.

Karl2D already exposes:

- `is_gamepad_active(gamepad)`
- `gamepad_button_went_down(gamepad, button)`
- `gamepad_button_went_up(gamepad, button)`
- `gamepad_button_is_held(gamepad, button)`
- `get_gamepad_axis(gamepad, axis)`
- `set_gamepad_vibration(gamepad, left, right)`

Karl2D supports up to `MAX_GAMEPADS`, with face buttons, D-pad buttons,
shoulders, triggers, stick press buttons, start/select-style middle buttons,
and left/right stick axes.

## Research Notes

The design follows the same broad shape as common gamepad APIs:

- SDL3's gamepad API maps different controller hardware into a standard
  gamepad model with button, axis, hotplug, and rumble APIs:
  <https://wiki.libsdl.org/SDL3/CategoryGamepad>
- SDL3's example event loop opens devices on gamepad-added events and handles
  button/axis events through the normalized gamepad API:
  <https://examples.libsdl.org/SDL3/input/04-gamepad-events/>
- The Web Gamepad API is polling-oriented and exposes buttons, axes,
  connected state, and optional haptics:
  <https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API>
- Apple's Game Controller framework also normalizes device input through
  logical profiles such as extended gamepad controls:
  <https://developer.apple.com/library/archive/documentation/ServicesDiscovery/Conceptual/GameControllerPG/ReadingControllerInputs/ReadingControllerInputs.html>

For Skald's Karl2D integration, Karl2D is the only backend target for v1, so
Skald does not need to import SDL3 gamepad concepts. The useful shared lesson
from these APIs is to normalize physical device input into a small logical UI
navigation surface before widgets see it.

## Input Model

Add backend-neutral gamepad navigation types to `skald/input.odin`:

```odin
Gamepad_Nav_Direction :: enum {
	Up,
	Down,
	Left,
	Right,
}

Gamepad_Nav_Directions :: bit_set[Gamepad_Nav_Direction]

Gamepad_Nav_Button :: enum {
	Accept,
	Cancel,
	Menu,
}

Gamepad_Nav_Buttons :: bit_set[Gamepad_Nav_Button]

Gamepad_Nav :: struct {
	active: bool,

	dir_pressed:  Gamepad_Nav_Directions,
	dir_down:     Gamepad_Nav_Directions,
	buttons_pressed: Gamepad_Nav_Buttons,
	buttons_down:    Gamepad_Nav_Buttons,
}
```

Add this field to `Input`:

```odin
gamepad_nav: Gamepad_Nav,
```

`active` means the chosen controller is connected. `dir_pressed` and
`buttons_pressed` are edge-triggered, matching Skald's existing `keys_pressed`
and `mouse_pressed` model. `dir_down` and `buttons_down` are level-triggered.

`input_reset_edges` should clear only the pressed fields if a backend updates
gamepad state incrementally. The Karl2D adapter currently rebuilds the full
`Input` snapshot each frame, so that path can set every gamepad field directly.

## Karl2D Translation

For v1, `skald_karl2d` reads gamepad index `0` only.

Mappings:

- D-pad up/down/left/right map directly to `dir_*`.
- Left stick maps to `dir_*` after a deadzone.
- `Right_Face_Down` maps to `Accept`.
- `Right_Face_Right` maps to `Cancel`.
- `Middle_Face_Right` maps to `Menu`.

The Karl2D adapter owns axis thresholding and analog direction edge detection.
Karl2D exposes axis levels, not "stick direction pressed" events, so
`Backend_State` should retain previous per-direction stick state to produce
one-frame `dir_pressed` edges when the stick crosses the threshold.

Recommended initial constants:

```odin
GAMEPAD_NAV_DEADZONE :: f32(0.45)
```

Axis directions remain active while the axis value is beyond the deadzone.
There is no repeat timer in v1. Holding the stick or D-pad moves focus once,
and repeated movement requires release and press again. Widget-specific code
that already repeats keyboard arrows can add repeat later as a separate
feature.

## Spatial Focus

Add a core helper beside the existing Tab focus code in `skald/widget.odin`:

```odin
widget_spatial_focus :: proc(ws: ^Widget_Store, dir: Gamepad_Nav_Direction)
```

It uses the current frame's `focusables` list and each widget state's
`last_rect`.

Rules:

- If no focusable widgets exist, do nothing.
- If nothing is focused, choose a first visible target:
  - Down or Right starts near the top-left.
  - Up or Left starts near the bottom-right.
- If a modal is active, restrict candidates to widgets whose rect centers are
  inside the modal, matching the current Tab focus trap.
- Ignore widgets with empty or stale rectangles.
- Candidate centers must be directionally valid from the focused rect center:
  - Up: candidate center is above the current center.
  - Down: candidate center is below the current center.
  - Left: candidate center is left of the current center.
  - Right: candidate center is right of the current center.
- Score by primary-axis distance first and cross-axis distance second, with a
  penalty for weak overlap. This gives natural grid movement without explicit
  navigation graphs.
- Do not wrap around. If no candidate exists in the requested direction, keep
  focus where it is.
- Ignore `tab_index` for spatial focus. `tab_index` remains a Tab traversal
  feature.

The helper uses Skald's existing one-frame geometry model. It relies on the
last rendered rectangles, like mouse hit-testing and input capture already do.

## Widget Routing

Gamepad direction routing is "internal first":

1. `skald_karl2d` translates Karl2D controller state into `Input.gamepad_nav`.
2. Widgets see `gamepad_nav` during view building.
3. Focused widgets that have meaningful direction behavior consume matching
   directions.
4. After the view has been built, remaining direction presses perform global
   spatial focus movement.

Add small helper procedures so widgets do not hand-edit bitsets everywhere:

```odin
gamepad_nav_dir_pressed :: proc(ctx: ^Ctx($Msg), dir: Gamepad_Nav_Direction) -> bool
gamepad_nav_consume_dir :: proc(ctx: ^Ctx($Msg), dir: Gamepad_Nav_Direction)
gamepad_nav_button_pressed :: proc(ctx: ^Ctx($Msg), button: Gamepad_Nav_Button) -> bool
gamepad_nav_consume_button :: proc(ctx: ^Ctx($Msg), button: Gamepad_Nav_Button)
```

Widget behavior:

- Buttons, links, checkboxes, toggles, and radio controls treat `Accept` like
  Enter/Space while focused.
- Dialogs, popovers, command surfaces, and menus treat `Cancel` like Escape
  where Escape already dismisses.
- Tables and trees consume directions as keyboard arrows while focused.
- Scroll containers may consume directions as keyboard scrolling while focused.
- Text inputs do not consume D-pad or stick text editing in v1. They may keep
  existing Enter/Escape behavior only where that behavior is already safe.
- Sliders consume Left/Right while focused. Up/Down falls through to spatial
  movement unless vertical slider behavior is added later.
- Select, date, time, color picker, and similar popovers may consume
  directions for highlight or adjustment behavior where they already use arrow
  keys.

After widget construction, the embedded frame code should run a global
gamepad-navigation pass:

- For each still-unconsumed `dir_pressed`, call `widget_spatial_focus`.
- If focus changes, consume that direction.
- A newly focused widget must not receive that same direction as activation in
  the same frame.

## Gamepad Shortcuts

Some UI actions are mouse-clickable but intentionally non-focusable. A common
gamepad pattern is to trigger them through shortcuts, such as "Y opens
inventory" or "Start opens pause".

Model those like keyboard shortcuts, not like focus.

Add a small shortcut API:

```odin
Gamepad_Chord :: struct {
	button: Gamepad_Nav_Button,
}

gamepad_shortcut :: proc(ctx: ^Ctx($Msg), chord: Gamepad_Chord, msg: Msg)
```

If the matching gamepad button is pressed, Skald sends `msg`, consumes the
button, and records that a gamepad shortcut matched for capture. The widget
does not need to be focusable.

For v1, the chord can be a single normalized button. Multi-button chords,
controller-specific physical buttons, and raw face-button shortcuts are future
extensions.

## Gamepad Capture

Extend capture state:

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

Extend `Capture_Frame_State` with:

```odin
gamepad_nav_active:       bool,
gamepad_nav_consumed:     bool,
gamepad_shortcut_matched: bool,
```

Capture rules:

- Static or display-only UI does not capture gamepad input.
- Focusable UI captures gamepad input when it is focused and gamepad
  navigation, accept, or cancel is active this frame.
- Modal dialogs and popovers capture gamepad navigation while open.
- A spatial focus move captures the direction press that moved focus.
- A gamepad shortcut captures only the matching shortcut press.
- If no focused widget, no modal/popover, and no shortcut match exists, gamepad
  input passes through to the host game.

This means non-focusable HUD overlays do not block gameplay controls. A
non-focusable UI command that should be triggered by controller input should
register a `gamepad_shortcut`.

## Backend Capability

Set `Gamepad_Navigation` in the Karl2D backend capabilities once
`skald_karl2d` translates `Input.gamepad_nav` and the core routing/capture
path is active.

Do not set it for the SDL3/Vulkan backend in this work.

## Example

Update `examples/50_karl2d_overlay` to demonstrate gamepad widget navigation.

The example should keep its split game loop:

```odin
skald_karl2d.begin_frame(&ui)
capture := skald_karl2d.capture(&ui)
game_update(capture)
game_draw()
skald_karl2d.end_frame(&ui)
k2.present()
```

Add an overlay with several controls arranged in two dimensions so spatial
movement is visible. The game scene should gate gamepad input with
`capture.gamepad`, so one controller press does not both drive gameplay and
move/activate Skald UI.

## Testing

Backend-neutral tests should cover:

- Spatial focus moves to the nearest widget in each direction.
- Diagonal candidates choose the strongest primary-direction match.
- Modal focus trap excludes widgets outside the modal rect.
- Empty or stale rectangles are ignored.
- No wraparound when no candidate exists.
- Nothing focused chooses a sensible first target.
- A focused composite widget can consume Down so global spatial focus does not
  move away.
- A gamepad shortcut sends its message and marks gamepad capture.
- Static/non-focusable UI does not mark gamepad capture.

Karl2D adapter tests should cover where feasible:

- D-pad button maps to `dir_pressed` and `dir_down`.
- Stick crossing the deadzone produces a one-frame press and a held direction.
- Stick remaining held does not repeat.
- `Right_Face_Down`, `Right_Face_Right`, and `Middle_Face_Right` map to
  `Accept`, `Cancel`, and `Menu`.

Verification commands:

```sh
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
odin check ./skald_karl2d -collection:gui=. -no-entry-point
./build.sh 50_karl2d_overlay
```

## Open Questions Deferred

- Whether stick/D-pad repeat should be added, and what repeat timings should
  be.
- Whether multiple gamepads should be routed to separate UI/game ownership.
- Whether gamepad shortcuts should grow raw physical button chords beyond the
  normalized `Accept`, `Cancel`, and `Menu` buttons.
- Whether focus movement should support explicit per-widget navigation
  overrides for unusual layouts.
