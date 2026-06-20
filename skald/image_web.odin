#+build js
package skald

Image_Entry :: struct {
	width:  u32,
	height: u32,
}

image_cache_get :: proc(r: ^Renderer, path: string) -> ^Image_Entry {
	_, _ = r, path
	return nil
}

image_load_pixels :: proc(r: ^Renderer, name: string, w, h: u32, rgba: []u8) -> bool {
	_, _, _, _, _ = r, name, w, h, rgba
	return false
}

image_is_resident :: proc(r: ^Renderer, name: string) -> bool {
	_, _ = r, name
	return false
}

image_update_pixels :: proc(r: ^Renderer, name: string, w, h: u32, rgba: []u8) -> bool {
	_, _, _, _, _ = r, name, w, h, rgba
	return false
}

draw_image :: proc(r: ^Renderer, name: string, rect: Rect, fit: Image_Fit = .Cover, tint: Color = {1, 1, 1, 1}) -> bool {
	_, _, _, _, _ = r, name, rect, fit, tint
	return false
}

image_unload :: proc(r: ^Renderer, name: string) {
	_, _ = r, name
}

image_fit_rects :: proc(box: Rect, iw, ih: f32, fit: Image_Fit) -> (dest, src: Rect) {
	src = {0, 0, iw, ih}
	dest = box
	if iw <= 0 || ih <= 0 || box.w <= 0 || box.h <= 0 {return}
	switch fit {
	case .Fill:
		dest = box
	case .None:
		dest = {box.x + (box.w - iw) * 0.5, box.y + (box.h - ih) * 0.5, iw, ih}
	case .Contain:
		scale := min(box.w / iw, box.h / ih)
		w := iw * scale
		h := ih * scale
		dest = {box.x + (box.w - w) * 0.5, box.y + (box.h - h) * 0.5, w, h}
	case .Cover:
		box_aspect := box.w / box.h
		img_aspect := iw / ih
		if img_aspect > box_aspect {
			visible_w := iw * (box_aspect / img_aspect)
			src.x = (iw - visible_w) * 0.5
			src.w = visible_w
		} else {
			visible_h := ih * (img_aspect / box_aspect)
			src.y = (ih - visible_h) * 0.5
			src.h = visible_h
		}
	}
	return
}
