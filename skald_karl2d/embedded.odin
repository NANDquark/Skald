package skald_karl2d

import skald "gui:skald"

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
}

init :: proc(ctx: ^Context($State, $Msg), app: skald.App(State, Msg)) {
	ctx.app = app
	ctx.state = app.init()
	ctx.theme = app.theme
	ctx.labels = app.labels
	if len(ctx.labels.month_names[0]) == 0 {ctx.labels = skald.labels_en()}

	backend_state_init(&ctx.backend_state)
	ctx.backend = backend(&ctx.backend_state)
	ctx.rc = skald.render_context_from_backend(&ctx.backend)
	ctx.rc.widgets = &ctx.widgets
	ctx.rc.overlays = &ctx.overlays
	ctx.rc.alpha_multiplier = 1
	ctx.rc.scale = window_scale(ctx.backend.state)
	sz := window_size(ctx.backend.state)
	ctx.rc.frame_size = {u32(max(sz.x, 0)), u32(max(sz.y, 0))}

	skald.widget_store_init(&ctx.widgets)
}

shutdown :: proc(ctx: ^Context($State, $Msg)) {
	skald.widget_store_destroy(&ctx.widgets)
	backend_state_destroy(&ctx.backend_state)
	delete(ctx.overlays)
	delete(ctx.msgs)
}

capture :: proc(ctx: ^Context($State, $Msg)) -> skald.Input_Capture {
	return ctx.backend_state.capture
}

input :: proc(ctx: ^Context($State, $Msg)) -> skald.Input {
	return ctx.backend_state.input
}
