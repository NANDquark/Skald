package skald_karl2d_web_overlay

import k2 "../../karl2d"
import "../../skald"
import skald_k2 "../../skald_karl2d"
import "core:fmt"

State :: struct {
	clicks:  int,
	frames:  int,
	animate: bool,
}

Msg :: union {
	Button_Clicked,
	Reset_Clicked,
	Animate_Toggled,
	Tick,
}

Button_Clicked :: struct {}
Reset_Clicked :: struct {}
Animate_Toggled :: distinct bool
Tick :: struct {}

ui: skald_k2.Context(State, Msg)
player: k2.Vec2

init_state :: proc() -> State {
	return {animate = true}
}

update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) {
	out := s
	switch v in m {
	case Button_Clicked:
		out.clicks += 1
	case Reset_Clicked:
		out.clicks = 0
		out.frames = 0
	case Animate_Toggled:
		out.animate = bool(v)
	case Tick:
		if out.animate {
			out.frames += 1
		}
	}
	return out, {}
}

on_animate :: proc(v: bool) -> Msg {
	return Animate_Toggled(v)
}

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	th := ctx.theme

	skald.send(ctx, Tick{})
	meter := f32(s.frames % 180) / 179

	return skald.col(
		skald.text("Skald on Karl2D Web", th.color.fg, th.font.size_xl),
		skald.text(
			fmt.tprintf("Clicks: %d  Frames: %d", s.clicks, s.frames),
			th.color.fg_muted,
			th.font.size_md,
		),
		skald.row(
			skald.button(ctx, "Click", Button_Clicked{},
				bg = th.color.primary, fg = th.color.on_primary, width = 96),
			skald.button(ctx, "Reset", Reset_Clicked{},
				bg = th.color.surface, fg = th.color.fg, width = 96),
			spacing = th.spacing.md,
			cross_align = .Center,
		),
		skald.toggle(ctx, s.animate, "Animate meter", on_animate),
		skald.progress(ctx, meter, width = 320, height = 8),
		skald.text(
			"WASD moves the circle when Skald does not capture keyboard.",
			th.color.fg_muted,
			th.font.size_sm,
		),
		width = 380,
		padding = th.spacing.lg,
		spacing = th.spacing.md,
	)
}

init :: proc() {
	k2.init(1280, 720, "Skald Karl2D Web Overlay", options = {window_mode = .Windowed_Resizable})

	app := skald.App(State, Msg) {
		title  = "Skald Karl2D Web Overlay",
		size   = {1280, 720},
		theme  = skald.theme_dark(),
		init   = init_state,
		update = update,
		view   = view,
	}

	skald_k2.init(&ui, app)
	player = {640, 360}
}

step :: proc() -> bool {
	if !k2.update() {
		return false
	}

	skald_k2.begin_frame(&ui)
	capture := skald_k2.capture(&ui)

	if !capture.keyboard {
		speed := f32(320) * k2.get_frame_time()
		if k2.key_is_held(.A) {player.x -= speed}
		if k2.key_is_held(.D) {player.x += speed}
		if k2.key_is_held(.W) {player.y -= speed}
		if k2.key_is_held(.S) {player.y += speed}
	}

	k2.clear(k2.DARK_BLUE)
	k2.draw_circle(player, 28, k2.LIGHT_GREEN)
	k2.draw_circle(player, 12, k2.GREEN)
	k2.draw_text("Karl2D scene behind a Skald overlay", {24, 668}, 24, k2.WHITE)

	skald_k2.end_frame(&ui)
	k2.present()

	return true
}

shutdown :: proc() {
	skald_k2.shutdown(&ui)
	k2.shutdown()
}

main :: proc() {
	init()
	for step() {}
	shutdown()
}
