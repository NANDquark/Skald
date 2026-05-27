package skald_karl2d

import k2 "../karl2d"
import skald "../skald"

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

init :: proc(ctx: ^Context($State, $Msg), app: skald.App(State, Msg)) -> bool {
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
	ctx.runtime_ready = skald.embedded_runtime_init(&ctx.runtime)
	return ctx.runtime_ready
}

shutdown :: proc(ctx: ^Context($State, $Msg)) {
	assert(!ctx.frame_active, "skald_karl2d.shutdown called while a frame is active")

	if ctx.runtime_ready {
		skald.embedded_runtime_destroy(&ctx.runtime)
		ctx.runtime_ready = false
	}
	skald.widget_store_destroy(&ctx.widgets)
	backend_state_destroy(&ctx.backend_state)
	delete(ctx.overlays)
	delete(ctx.msgs)
}

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
	defer {
		ctx.frame_active = false
		free_all(context.temp_allocator)
	}

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
