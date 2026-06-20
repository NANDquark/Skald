package skald

import "core:time"

// Command_Kind discriminates a `Command`. `.None` is the zero value so
// `return state, {}` from an update branch means "no effect".
Command_Kind :: enum u8 {
	None,
	Now,
	Delay,
	Batch,
	Async,
	Open_Window,
	Close_Window,
	Thread,
	Set_Theme,
}

cmd_now :: proc(msg: $Msg) -> Command(Msg) {
	return Command(Msg){kind = .Now, msg = msg}
}

cmd_set_theme :: proc($Msg: typeid, t: Theme) -> Command(Msg) {
	p := new(Theme, context.temp_allocator)
	p^ = t
	return Command(Msg){kind = .Set_Theme, theme_op = p}
}

cmd_delay :: proc(seconds: f32, msg: $Msg) -> Command(Msg) {
	return Command(Msg){kind = .Delay, seconds = seconds, msg = msg}
}

cmd_batch :: proc(first: Command($Msg), rest: ..Command(Msg)) -> Command(Msg) {
	n := len(rest) + 1
	slice := make([]Command(Msg), n, context.temp_allocator)
	slice[0] = first
	for cmd, i in rest {
		slice[i + 1] = cmd
	}
	return Command(Msg){kind = .Batch, children = slice}
}

@(private)
Pending_Delay :: struct($Msg: typeid) {
	fire_at_ns: i64,
	msg:        Msg,
}

@(private)
drain_due_delays :: proc(
	pending: ^[dynamic]Pending_Delay($Msg),
	msgs:    ^[dynamic]Msg,
) {
	now_ns := time.now()._nsec
	i := 0
	for i < len(pending) {
		if pending[i].fire_at_ns <= now_ns {
			append(msgs, pending[i].msg)
			ordered_remove(pending, i)
		} else {
			i += 1
		}
	}
}
