package karl2d_backgrounds

import k2 "../../karl2d"
import "../../skald"
import skald_k2 "../../skald_karl2d"
import "core:fmt"

FRAME_NAME :: "app://karl2d-nine-slice-frame"
FRAME_JPG  :: #load("assets/9-slice.jpg", []byte)

FRAME :: skald.Nine_Slice {
	top_left     = {0, 0, 17, 17},
	top          = {17, 0, 59, 17},
	top_right    = {147, 0, 17, 17},
	left         = {0, 17, 17, 59},
	center       = {17, 17, 28, 28},
	right        = {147, 17, 17, 59},
	bottom_left  = {0, 147, 17, 17},
	bottom       = {17, 147, 59, 17},
	bottom_right = {147, 147, 17, 17},
}

ASYMMETRIC_FRAME :: skald.Nine_Slice {
	top_left     = {0, 0, 17, 17},
	top          = {17, 0, 41, 17},
	top_right    = {147, 0, 17, 17},
	left         = {0, 17, 17, 37},
	right        = {147, 17, 17, 59},
	bottom_left  = {0, 147, 17, 17},
	bottom       = {17, 147, 59, 17},
	bottom_right = {147, 147, 17, 17},
}

OPEN_FRAME :: skald.Nine_Slice {
	top_left  = {0, 0, 17, 17},
	top       = {17, 0, 59, 17},
	top_right = {147, 0, 17, 17},
	left      = {0, 17, 17, 59},
	right     = {147, 17, 17, 59},
}

State :: struct {}
Msg :: enum {Unused}

init :: proc() -> State {return {}}

update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) {
	_ = m
	return s, {}
}

panel_content :: proc(
	ctx: ^skald.Ctx(Msg),
	title, body: string,
	bg: skald.Color = {},
) -> skald.View {
	th := ctx.theme
	return skald.col(
		skald.text(title, th.color.fg, th.font.size_lg),
		skald.text(body, th.color.fg_muted, th.font.size_sm),
		spacing = th.spacing.xs,
		padding = th.spacing.md,
		width = 220,
		height = 96,
		bg = bg,
	)
}

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
	_ = s
	th := ctx.theme
	_ = skald.image_load_bytes(ctx, FRAME_NAME, FRAME_JPG)
	frame_size, _ := skald.image_size(ctx, FRAME_NAME)

	return skald.col(
		skald.text("Karl2D container image backgrounds", th.color.fg, th.font.size_xl),
		skald.text(
			"Embedded nine-slice spritesheet loaded through #load; corners stay native while borders and the optional center tile repeat.",
			th.color.fg_muted,
			th.font.size_md,
		),
		skald.text(
			fmt.tprintf("spritesheet size: %.0f x %.0f", frame_size.x, frame_size.y),
			th.color.fg_muted,
			th.font.size_sm,
		),
		skald.row(
			skald.image_background(ctx, FRAME_NAME, panel_content(ctx, ".None", "native pixels"), fit = .None),
			skald.image_background(ctx, FRAME_NAME, panel_content(ctx, ".Contain", "preserve aspect"), fit = .Contain),
			skald.image_background(ctx, FRAME_NAME, panel_content(ctx, ".Cover", "explicit crop"), fit = .Cover),
			skald.image_background(ctx, FRAME_NAME, panel_content(ctx, ".Fill", "explicit stretch"), fit = .Fill),
			spacing = th.spacing.md,
		),
		skald.row(
			skald.nine_slice_background(ctx, FRAME_NAME, FRAME, panel_content(ctx, "Full tiled frame", "corners, borders, brick center")),
			skald.nine_slice_background(ctx, FRAME_NAME, ASYMMETRIC_FRAME, panel_content(ctx, "Asymmetric frame", "independent source regions", bg = th.color.surface)),
			skald.nine_slice_background(ctx, FRAME_NAME, OPEN_FRAME, panel_content(ctx, "Open frame", "optional bottom and center", bg = th.color.surface)),
			spacing = th.spacing.lg,
		),
		spacing = th.spacing.lg,
		padding = th.spacing.xl,
	)
}

main :: proc() {
	k2.init(1280, 720, "Skald Karl2D Backgrounds", options = {window_mode = .Windowed_Resizable})
	defer k2.shutdown()

	app := skald.App(State, Msg) {
		title = "Skald Karl2D Backgrounds",
		size = {1280, 720},
		theme = skald.theme_dark(),
		init = init,
		update = update,
		view = view,
	}

	ui: skald_k2.Context(State, Msg)
	if !skald_k2.init(&ui, app) {return}
	defer skald_k2.shutdown(&ui)

	for k2.update() {
		k2.clear(k2.DARK_BLUE)
		skald_k2.frame(&ui)
		k2.present()
	}
}
