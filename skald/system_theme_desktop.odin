#+build !js
package skald

import "vendor:sdl3"

// system_theme queries the OS's current appearance preference via SDL3.
// Safe to call after `run` has opened the window; returns `.Unknown`
// before SDL is initialized or when the platform can't report it.
system_theme :: proc() -> System_Theme {
	switch sdl3.GetSystemTheme() {
	case .LIGHT: return .Light
	case .DARK: return .Dark
	case .UNKNOWN: return .Unknown
	}
	return .Unknown
}
