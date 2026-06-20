#+build js
package skald

App :: struct($State, $Msg: typeid) {
	title:  string,
	size:   Size,
	theme:  Theme,
	labels: Labels,

	init:   proc() -> State,
	update: proc(state: State, msg: Msg) -> (State, Command(Msg)),
	view:   proc(state: State, ctx: ^Ctx(Msg)) -> View,

	always_redraw: bool,
}
