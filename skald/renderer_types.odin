package skald

// Overlay_Entry is one deferred popover/tooltip/menu to be rendered
// after the main tree. `origin` is already in framebuffer pixel space;
// `size` is the child's intrinsic size. The child itself is a plain
// View so overlays can contain any sub-tree.
Overlay_Entry :: struct {
	origin: [2]f32,
	size:   [2]f32,
	child:  View,
	// shadow_radius controls the drop shadow drawn beneath this overlay.
	// 0 suppresses the shadow entirely (used for dialog scrims + other
	// full-screen entries that shouldn't cast one); a non-zero value
	// should match the overlay card's visible corner radius so the
	// shadow hugs its silhouette.
	shadow_radius: f32,
	// opacity fades the entire overlay subtree by multiplying the
	// renderer's `alpha_multiplier` while rendering this child. 1
	// is fully visible (default); 0 is invisible.
	opacity: f32,
}
