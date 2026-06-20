package skald

// Window_State captures everything needed to restore a window's on-screen
// footprint between launches.
Window_State :: struct {
	pos:       [2]i32,
	size:      Size,
	maximized: bool,
}

// Ctx is the per-frame context handed to `view`.
Ctx :: struct($Msg: typeid) {
	theme:      ^Theme,
	labels:     ^Labels,
	input:      ^Input,
	msgs:       ^[dynamic]Msg,
	widgets:    ^Widget_Store,
	renderer:   ^Renderer,
	render:     ^Render_Context,
	window:     Window_Id,
	breakpoint: Breakpoint,
}

Breakpoint :: enum {
	Compact,
	Regular,
	Wide,
}

@(private)
breakpoint_for_width :: proc(w: f32) -> Breakpoint {
	switch {
	case w < 600:
		return .Compact
	case w < 1100:
		return .Regular
	}
	return .Wide
}

breakpoint :: proc(width: f32) -> Breakpoint {
	return breakpoint_for_width(width)
}

send :: proc(ctx: ^Ctx($Msg), m: Msg) {
	append(ctx.msgs, m)
}

map_msg :: proc(
	parent_ctx: ^Ctx($Parent_Msg),
	sub_state: $Sub_State,
	sub_view: proc(_: Sub_State, _: ^Ctx($Sub_Msg)) -> View,
	to_parent: proc(_: Sub_Msg) -> Parent_Msg,
) -> View {
	sub_msgs := new([dynamic]Sub_Msg, context.temp_allocator)
	sub_msgs^ = make([dynamic]Sub_Msg, context.temp_allocator)

	sub_ctx := Ctx(Sub_Msg) {
		theme      = parent_ctx.theme,
		labels     = parent_ctx.labels,
		input      = parent_ctx.input,
		msgs       = sub_msgs,
		widgets    = parent_ctx.widgets,
		renderer   = parent_ctx.renderer,
		render     = parent_ctx.render,
		window     = parent_ctx.window,
		breakpoint = parent_ctx.breakpoint,
	}

	v := sub_view(sub_state, &sub_ctx)
	for m in sub_msgs^ {send(parent_ctx, to_parent(m))}
	return v
}

map_msg_for :: proc(
	parent_ctx: ^Ctx($Parent_Msg),
	payload: $Payload,
	sub_state: $Sub_State,
	sub_view: proc(_: Sub_State, _: ^Ctx($Sub_Msg)) -> View,
	to_parent: proc(payload: Payload, sub_msg: Sub_Msg) -> Parent_Msg,
) -> View {
	sub_msgs := new([dynamic]Sub_Msg, context.temp_allocator)
	sub_msgs^ = make([dynamic]Sub_Msg, context.temp_allocator)

	sub_ctx := Ctx(Sub_Msg) {
		theme      = parent_ctx.theme,
		labels     = parent_ctx.labels,
		input      = parent_ctx.input,
		msgs       = sub_msgs,
		widgets    = parent_ctx.widgets,
		renderer   = parent_ctx.renderer,
		render     = parent_ctx.render,
		window     = parent_ctx.window,
		breakpoint = parent_ctx.breakpoint,
	}

	v := sub_view(sub_state, &sub_ctx)
	for m in sub_msgs^ {send(parent_ctx, to_parent(payload, m))}
	return v
}
