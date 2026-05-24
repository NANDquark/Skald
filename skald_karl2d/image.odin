package skald_karl2d

import "core:strings"
import k2 "gui:karl2d"
import skald "gui:skald"

Image_Entry :: struct {
	key:     string,
	texture: k2.Texture,
	alive:   bool,
}

k2_image_load_path :: proc(state: rawptr, path: string) -> skald.Backend_Image {
	if len(path) == 0 {return skald.Backend_Image(nil)}
	s := (^Backend_State)(state)
	if s.images == nil {
		s.images = make(map[string]^Image_Entry)
	}
	if entry, ok := s.images[path]; ok && entry != nil {
		if entry.alive {return skald.Backend_Image(entry)}
		texture := k2.load_texture_from_file(path)
		if texture.handle == k2.TEXTURE_NONE {return skald.Backend_Image(nil)}
		entry.texture = texture
		entry.alive = true
		return skald.Backend_Image(entry)
	}

	texture := k2.load_texture_from_file(path)
	if texture.handle == k2.TEXTURE_NONE {return skald.Backend_Image(nil)}
	key := strings.clone(path)
	entry := new(Image_Entry)
	entry^ = Image_Entry {
		key     = key,
		texture = texture,
		alive   = true,
	}
	s.images[key] = entry
	return skald.Backend_Image(entry)
}

k2_image_load_pixels :: proc(
	state: rawptr,
	name: string,
	w, h: u32,
	rgba: []u8,
) -> skald.Backend_Image {
	if len(name) == 0 || w == 0 || h == 0 || len(rgba) == 0 {
		return skald.Backend_Image(nil)
	}
	s := (^Backend_State)(state)
	if s.images == nil {
		s.images = make(map[string]^Image_Entry)
	}
	if entry, ok := s.images[name]; ok && entry != nil {
		if entry.alive && k2_image_update_pixels(state, skald.Backend_Image(entry), w, h, rgba) {
			return skald.Backend_Image(entry)
		}
		if !entry.alive {
			texture := k2.load_texture_from_bytes_raw(rgba, int(w), int(h), .RGBA_8_Norm)
			if texture.handle == k2.TEXTURE_NONE {return skald.Backend_Image(nil)}
			entry.texture = texture
			entry.alive = true
			return skald.Backend_Image(entry)
		}
		return skald.Backend_Image(nil)
	}

	texture := k2.load_texture_from_bytes_raw(rgba, int(w), int(h), .RGBA_8_Norm)
	if texture.handle == k2.TEXTURE_NONE {return skald.Backend_Image(nil)}
	key := strings.clone(name)
	entry := new(Image_Entry)
	entry^ = Image_Entry {
		key     = key,
		texture = texture,
		alive   = true,
	}
	s.images[key] = entry
	return skald.Backend_Image(entry)
}

k2_image_update_pixels :: proc(
	state: rawptr,
	image: skald.Backend_Image,
	w, h: u32,
	rgba: []u8,
) -> bool {
	entry := (^Image_Entry)(rawptr(image))
	if entry == nil || !entry.alive || w == 0 || h == 0 || len(rgba) == 0 {
		return false
	}
	if entry.texture.width != int(w) || entry.texture.height != int(h) {
		texture := k2.load_texture_from_bytes_raw(rgba, int(w), int(h), .RGBA_8_Norm)
		if texture.handle == k2.TEXTURE_NONE {return false}
		k2.destroy_texture(entry.texture)
		entry.texture = texture
		return true
	}
	return k2.update_texture(entry.texture, rgba, {0, 0, f32(w), f32(h)})
}

k2_image_unload :: proc(state: rawptr, image: skald.Backend_Image) {
	entry := (^Image_Entry)(rawptr(image))
	if entry == nil || !entry.alive {return}
	entry.alive = false
	if entry.texture.handle != k2.TEXTURE_NONE {
		k2.destroy_texture(entry.texture)
		entry.texture = {}
	}
}

k2_image_draw :: proc(
	state: rawptr,
	image: skald.Backend_Image,
	rect: skald.Rect,
	tint: skald.Color,
) {
	_ = k2_image_draw_fit(state, image, rect, .Cover, tint)
}

k2_image_draw_fit :: proc(
	state: rawptr,
	image: skald.Backend_Image,
	rect: skald.Rect,
	fit: skald.Image_Fit,
	tint: skald.Color,
) -> bool {
	entry := (^Image_Entry)(rawptr(image))
	if entry == nil || !entry.alive || entry.texture.handle == k2.TEXTURE_NONE {
		return false
	}

	dest, src := k2_image_fit_rects(rect, f32(entry.texture.width), f32(entry.texture.height), fit)
	push_clip(state, rect)
	k2.draw_texture_fit(entry.texture, src, dest, tint = to_k2_color(tint))
	pop_clip(state)
	return true
}

k2_image_cache_destroy :: proc(s: ^Backend_State) {
	if s.images == nil {return}
	for _, entry in s.images {
		if entry == nil {continue}
		if entry.alive && entry.texture.handle != k2.TEXTURE_NONE {
			k2.destroy_texture(entry.texture)
		}
		if len(entry.key) > 0 {delete(entry.key)}
		free(entry)
	}
	delete(s.images)
	s.images = nil
}

k2_image_fit_rects :: proc(
	box: skald.Rect,
	iw, ih: f32,
	fit: skald.Image_Fit,
) -> (
	dest: k2.Rect,
	src: k2.Rect,
) {
	src = {0, 0, iw, ih}
	dest = to_k2_rect(box)
	if iw <= 0 || ih <= 0 || box.w <= 0 || box.h <= 0 {
		return
	}

	switch fit {
	case .Fill:
		dest = to_k2_rect(box)
	case .None:
		dx := (box.w - iw) * 0.5
		dy := (box.h - ih) * 0.5
		dest = {box.x + dx, box.y + dy, iw, ih}
	case .Contain:
		scale := min(box.w / iw, box.h / ih)
		w := iw * scale
		h := ih * scale
		dest = {box.x + (box.w - w) * 0.5, box.y + (box.h - h) * 0.5, w, h}
	case .Cover:
		box_aspect := box.w / box.h
		img_aspect := iw / ih
		dest = to_k2_rect(box)
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
