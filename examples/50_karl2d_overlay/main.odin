package karl2d_overlay

import k2 "../../karl2d"
import "../../skald"
import skald_k2 "../../skald_karl2d"
import "core:fmt"
import "core:strings"

State :: struct {
	clicks: int,
	text:   string,
}

Msg :: union {
	Button_Clicked,
	Text_Changed,
}

Button_Clicked :: struct {}
Text_Changed :: distinct string

init :: proc() -> State {
	return {text = strings.clone("Skald over Karl2D")}
}

update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) {
	out := s
	switch v in m {
	case Button_Clicked:
		out.clicks += 1
	case Text_Changed:
		delete(out.text)
		out.text = strings.clone(string(v))
	}
	return out, {}
}

on_button :: proc() -> Msg {
	return Button_Clicked{}
}

on_text :: proc(v: string) -> Msg {
	return Text_Changed(v)
}

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	th := ctx.theme
	return skald.col(
		skald.text("Skald overlay", th.color.fg, th.font.size_xl),
		skald.text(fmt.tprintf("UI clicks: %d", s.clicks), th.color.fg_muted, th.font.size_md),
		skald.button(ctx, "UI button", on_button(), width = 180),
		skald.text_input(ctx, s.text, on_text, placeholder = "Type here", width = 320),
		padding = th.spacing.lg,
		spacing = th.spacing.md,
	)
}

main :: proc() {
	k2.init(1280, 720, "Skald Karl2D Overlay", options = {window_mode = .Windowed_Resizable})
	defer k2.shutdown()

	app := skald.App(State, Msg) {
		title  = "Skald Karl2D Overlay",
		size   = {1280, 720},
		theme  = skald.theme_dark(),
		init   = init,
		update = update,
		view   = view,
	}

	ui: skald_k2.Context(State, Msg)
	if !skald_k2.init(&ui, app) {
		return
	}
	defer {
		delete(ui.state.text)
		skald_k2.shutdown(&ui)
	}

	player := k2.Vec2{640, 360}

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
}
