package karl2d_backgrounds

import k2 "../../karl2d"
import "../../skald"
import skald_k2 "../../skald_karl2d"
import "core:fmt"

ATLAS_NAME :: "app://karl2d-background-atlas"
ATLAS_PNG  :: #load("../../karl2d/examples/dual_grid_tilemap/tileset_path.png", []byte)

FRAME :: skald.Nine_Slice {
	top_left     = {0, 0, 16, 16},
	top          = {16, 0, 16, 16},
	top_right    = {32, 0, 16, 16},
	left         = {0, 16, 16, 16},
	center       = {16, 16, 16, 16},
	right        = {32, 16, 16, 16},
	bottom_left  = {0, 32, 16, 16},
	bottom       = {16, 32, 16, 16},
	bottom_right = {32, 32, 16, 16},
}

ASYMMETRIC_FRAME :: skald.Nine_Slice {
	top_left     = {0, 0, 16, 16},
	top          = {16, 0, 8, 16},
	top_right    = {32, 0, 16, 8},
	left         = {0, 16, 16, 8},
	right        = {32, 16, 8, 16},
	bottom_left  = {0, 32, 8, 16},
	bottom       = {16, 32, 16, 8},
	bottom_right = {32, 32, 16, 16},
}

OPEN_FRAME :: skald.Nine_Slice {
	top_left  = {0, 0, 16, 16},
	top       = {16, 0, 16, 16},
	top_right = {32, 0, 16, 16},
	left      = {0, 16, 16, 16},
	right     = {32, 16, 16, 16},
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
	_ = skald.image_load_bytes(ctx, ATLAS_NAME, ATLAS_PNG)
	atlas_size, _ := skald.image_size(ctx, ATLAS_NAME)

	return skald.col(
		skald.text("Karl2D container image backgrounds", th.color.fg, th.font.size_xl),
		skald.text(
			"Embedded atlas loaded through #load; single images fit normally and nine-slice frames tile without stretching.",
			th.color.fg_muted,
			th.font.size_md,
		),
		skald.text(
			fmt.tprintf("atlas size: %.0f x %.0f", atlas_size.x, atlas_size.y),
			th.color.fg_muted,
			th.font.size_sm,
		),
		skald.row(
			skald.image_background(ctx, ATLAS_NAME, panel_content(ctx, ".None", "native pixels"), fit = .None),
			skald.image_background(ctx, ATLAS_NAME, panel_content(ctx, ".Contain", "preserve aspect"), fit = .Contain),
			skald.image_background(ctx, ATLAS_NAME, panel_content(ctx, ".Cover", "explicit crop"), fit = .Cover),
			skald.image_background(ctx, ATLAS_NAME, panel_content(ctx, ".Fill", "explicit stretch"), fit = .Fill),
			spacing = th.spacing.md,
		),
		skald.row(
			skald.nine_slice_background(ctx, ATLAS_NAME, FRAME, panel_content(ctx, "Complete frame", "corners, borders, center", bg = th.color.surface)),
			skald.nine_slice_background(ctx, ATLAS_NAME, ASYMMETRIC_FRAME, panel_content(ctx, "Asymmetric frame", "independent source regions", bg = th.color.surface)),
			skald.nine_slice_background(ctx, ATLAS_NAME, OPEN_FRAME, panel_content(ctx, "Open frame", "optional bottom and center", bg = th.color.surface)),
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
