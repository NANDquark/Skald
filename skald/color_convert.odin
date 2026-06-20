package skald

linear_to_srgb_byte :: proc(l_in: f32) -> u8 {
	s := linear_to_srgb(clamp(l_in, 0, 1))
	return u8(clamp(s, 0, 1) * 255 + 0.5)
}
