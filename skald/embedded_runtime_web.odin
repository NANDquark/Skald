#+build js
package skald

Embedded_Runtime :: struct($Msg: typeid) {
	pending: [dynamic]Pending_Delay(Msg),
}

embedded_runtime_init :: proc(rt: ^Embedded_Runtime($Msg)) -> bool {
	_ = rt
	return true
}

embedded_runtime_destroy :: proc(rt: ^Embedded_Runtime($Msg)) {
	delete(rt.pending)
}

embedded_runtime_begin_frame :: proc(rt: ^Embedded_Runtime($Msg), msgs: ^[dynamic]Msg) {
	drain_due_delays(&rt.pending, msgs)
}

embedded_runtime_drain_messages :: proc(
	rt: ^Embedded_Runtime($Msg),
	state: $State,
	app: App(State, Msg),
	msgs: ^[dynamic]Msg,
	theme: ^Theme,
) -> State {
	out := state
	for len(msgs^) > 0 {
		frame_msgs := make([dynamic]Msg, context.temp_allocator)
		for msg in msgs^ {append(&frame_msgs, msg)}
		clear(msgs)
		for msg in frame_msgs {
			new_state, cmd := app.update(out, msg)
			out = new_state
			process_command(cmd, msgs, &rt.pending, theme)
		}
	}
	return out
}
