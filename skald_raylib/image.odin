package skald_raylib

import "core:c"
import rl "vendor:raylib"
import skald "../skald"
import "core:strings"

Image_Entry :: struct {
	key:     string,
	texture: rl.Texture2D,
	alive:   bool,
}

rl_image_load_path :: proc(state: rawptr, path: string) -> skald.Backend_Image {
	if len(path) == 0 {return skald.Backend_Image(nil)}
	s := (^Backend_State)(state)
	if s.images == nil {
		s.images = make(map[string]^Image_Entry)
	}
	if entry, ok := s.images[path]; ok && entry != nil {
		if entry.alive {return skald.Backend_Image(entry)}
		c_path := strings.clone_to_cstring(path, context.temp_allocator)
		texture := rl.LoadTexture(c_path)
		if !rl.IsTextureValid(texture) {return skald.Backend_Image(nil)}
		entry.texture = texture
		entry.alive = true
		return skald.Backend_Image(entry)
	}

	c_path := strings.clone_to_cstring(path, context.temp_allocator)
	texture := rl.LoadTexture(c_path)
	if !rl.IsTextureValid(texture) {return skald.Backend_Image(nil)}
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

rl_image_load_bytes :: proc(state: rawptr, name: string, bytes: []byte) -> skald.Backend_Image {
	if len(name) == 0 || len(bytes) == 0 {return skald.Backend_Image(nil)}
	s := (^Backend_State)(state)
	if s.images == nil {
		s.images = make(map[string]^Image_Entry)
	}
	if entry, ok := s.images[name]; ok && entry != nil {
		if entry.alive {return skald.Backend_Image(entry)}
		texture := rl_texture_from_png_bytes(bytes)
		if !rl.IsTextureValid(texture) {return skald.Backend_Image(nil)}
		entry.texture = texture
		entry.alive = true
		return skald.Backend_Image(entry)
	}

	texture := rl_texture_from_png_bytes(bytes)
	if !rl.IsTextureValid(texture) {return skald.Backend_Image(nil)}
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

rl_image_load_pixels :: proc(
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
		if entry.alive && rl_image_update_pixels(state, skald.Backend_Image(entry), w, h, rgba) {
			return skald.Backend_Image(entry)
		}
		if !entry.alive {
			texture := rl_texture_from_rgba(w, h, rgba)
			if !rl.IsTextureValid(texture) {return skald.Backend_Image(nil)}
			entry.texture = texture
			entry.alive = true
			return skald.Backend_Image(entry)
		}
		return skald.Backend_Image(nil)
	}

	texture := rl_texture_from_rgba(w, h, rgba)
	if !rl.IsTextureValid(texture) {return skald.Backend_Image(nil)}
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

rl_image_update_pixels :: proc(
	state: rawptr,
	image: skald.Backend_Image,
	w, h: u32,
	rgba: []u8,
) -> bool {
	entry := (^Image_Entry)(rawptr(image))
	if entry == nil || !entry.alive || w == 0 || h == 0 || len(rgba) == 0 {
		return false
	}
	if entry.texture.width != c.int(w) || entry.texture.height != c.int(h) {
		texture := rl_texture_from_rgba(w, h, rgba)
		if !rl.IsTextureValid(texture) {return false}
		rl.UnloadTexture(entry.texture)
		entry.texture = texture
		return true
	}
	rl.UpdateTexture(entry.texture, raw_data(rgba))
	return true
}

rl_image_unload :: proc(state: rawptr, image: skald.Backend_Image) {
	entry := (^Image_Entry)(rawptr(image))
	if entry == nil || !entry.alive {return}
	entry.alive = false
	if rl.IsTextureValid(entry.texture) {
		rl.UnloadTexture(entry.texture)
		entry.texture = {}
	}
}

rl_image_draw :: proc(
	state: rawptr,
	image: skald.Backend_Image,
	rect: skald.Rect,
	tint: skald.Color,
) {
	_ = rl_image_draw_fit(state, image, rect, .Cover, tint)
}

rl_image_draw_fit :: proc(
	state: rawptr,
	image: skald.Backend_Image,
	rect: skald.Rect,
	fit: skald.Image_Fit,
	tint: skald.Color,
) -> bool {
	entry := (^Image_Entry)(rawptr(image))
	if entry == nil || !entry.alive || !rl.IsTextureValid(entry.texture) {
		return false
	}

	dest, src := rl_image_fit_rects(rect, f32(entry.texture.width), f32(entry.texture.height), fit)
	push_clip(state, rect)
	rl.DrawTexturePro(entry.texture, src, dest, {}, 0, to_rl_color(tint))
	pop_clip(state)
	return true
}

rl_image_size :: proc(state: rawptr, image: skald.Backend_Image) -> (size: [2]f32, ok: bool) {
	entry := (^Image_Entry)(rawptr(image))
	if entry == nil || !entry.alive || !rl.IsTextureValid(entry.texture) {
		return {}, false
	}
	return {f32(entry.texture.width), f32(entry.texture.height)}, true
}

rl_image_draw_region :: proc(
	state: rawptr,
	image: skald.Backend_Image,
	src, dst: skald.Rect,
	tint: skald.Color,
) -> bool {
	entry := (^Image_Entry)(rawptr(image))
	if entry == nil || !entry.alive || !rl.IsTextureValid(entry.texture) {
		return false
	}
	s := (^Backend_State)(state)
	rl.DrawTexturePro(entry.texture, to_rl_rect(src), to_rl_rect(dst), {}, 0, to_rl_color(tint, s.alpha))
	return true
}

rl_image_cache_destroy :: proc(s: ^Backend_State) {
	if s.images == nil {return}
	for _, entry in s.images {
		if entry == nil {continue}
		if entry.alive && rl.IsTextureValid(entry.texture) {
			rl.UnloadTexture(entry.texture)
		}
		if len(entry.key) > 0 {delete(entry.key)}
		free(entry)
	}
	delete(s.images)
	s.images = nil
}

rl_image_fit_rects :: proc(
	box: skald.Rect,
	iw, ih: f32,
	fit: skald.Image_Fit,
) -> (
	dest: rl.Rectangle,
	src: rl.Rectangle,
) {
	src = {0, 0, iw, ih}
	dest = to_rl_rect(box)
	if iw <= 0 || ih <= 0 || box.w <= 0 || box.h <= 0 {
		return
	}

	switch fit {
	case .Fill:
		dest = to_rl_rect(box)
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
		dest = to_rl_rect(box)
		if img_aspect > box_aspect {
			visible_w := iw * (box_aspect / img_aspect)
			src.x = (iw - visible_w) * 0.5
			src.width = visible_w
		} else {
			visible_h := ih * (img_aspect / box_aspect)
			src.y = (ih - visible_h) * 0.5
			src.height = visible_h
		}
	}
	return
}

rl_texture_from_png_bytes :: proc(bytes: []byte) -> rl.Texture2D {
	image := rl.LoadImageFromMemory(".png", raw_data(bytes), c.int(len(bytes)))
	if !rl.IsImageValid(image) {return {}}
	defer rl.UnloadImage(image)
	return rl.LoadTextureFromImage(image)
}

rl_texture_from_rgba :: proc(w, h: u32, rgba: []u8) -> rl.Texture2D {
	if w == 0 || h == 0 || len(rgba) == 0 {return {}}
	image := rl.Image {
		data    = raw_data(rgba),
		width   = c.int(w),
		height  = c.int(h),
		mipmaps = 1,
		format  = .UNCOMPRESSED_R8G8B8A8,
	}
	return rl.LoadTextureFromImage(image)
}
