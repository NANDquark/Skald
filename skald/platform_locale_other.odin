#+build !windows
#+build !js
package skald

import "core:os"

// win32_user_locale_name is a Windows-only sniff. On every other
// platform, LC_TIME / LANG are the canonical source (set by the shell
// or login profile), so we return "" here and let date_locale_style
// fall through to its ISO default if both env vars are empty.
@(private)
win32_user_locale_name :: proc() -> string {
	return ""
}

@(private)
platform_locale_env :: proc(name: string) -> string {
	val, _ := os.lookup_env(name, context.temp_allocator)
	return val
}
