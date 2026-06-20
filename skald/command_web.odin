#+build js
package skald

import "core:time"

Command :: struct($Msg: typeid) {
	kind:     Command_Kind,
	msg:      Msg,
	seconds:  f32,
	children: []Command(Msg),
	theme_op: ^Theme,
}

@(private)
process_command :: proc(
	cmd:     Command($Msg),
	msgs:    ^[dynamic]Msg,
	pending: ^[dynamic]Pending_Delay(Msg),
	theme:   ^Theme,
) {
	switch cmd.kind {
	case .None:
	case .Now:
		append(msgs, cmd.msg)
	case .Delay:
		fire := time.now()._nsec + i64(f64(cmd.seconds) * f64(time.Second))
		append(pending, Pending_Delay(Msg){fire_at_ns = fire, msg = cmd.msg})
	case .Batch:
		for child in cmd.children {
			process_command(child, msgs, pending, theme)
		}
	case .Set_Theme:
		if cmd.theme_op != nil && theme != nil {
			theme^ = cmd.theme_op^
		}
	case .Async, .Open_Window, .Close_Window, .Thread:
		// Desktop-only effects intentionally do nothing in the embedded web runtime.
	}
}
