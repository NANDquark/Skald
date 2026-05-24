package skald

import "core:nbio"

Embedded_Runtime :: struct($Msg: typeid) {
	pending: [dynamic]Pending_Delay(Msg),
	io:      Io_State(Msg),
	tpool:   Thread_Pool(Msg),
}

embedded_runtime_init :: proc(rt: ^Embedded_Runtime($Msg)) -> bool {
	if err := nbio.acquire_thread_event_loop(); err != nil {
		return false
	}
	io_state_init(&rt.io, nil)
	thread_pool_init(&rt.tpool)
	return true
}

embedded_runtime_destroy :: proc(rt: ^Embedded_Runtime($Msg)) {
	thread_pool_destroy(&rt.tpool)
	io_state_destroy(&rt.io)
	delete(rt.pending)
	nbio.release_thread_event_loop()
}

embedded_runtime_begin_frame :: proc(rt: ^Embedded_Runtime($Msg), msgs: ^[dynamic]Msg) {
	drain_due_delays(&rt.pending, msgs)
	nbio.tick(0)
	drain_io(&rt.io, msgs)
	_ = thread_pool_drain(&rt.tpool, msgs)
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
			process_command(cmd, msgs, &rt.pending, &rt.io, nil, &rt.tpool, theme)
		}
	}
	return out
}
