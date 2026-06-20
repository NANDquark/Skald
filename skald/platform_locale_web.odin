#+build js
package skald

@(private)
win32_user_locale_name :: proc() -> string {
	return ""
}

@(private)
platform_locale_env :: proc(name: string) -> string {
	_ = name
	return ""
}
