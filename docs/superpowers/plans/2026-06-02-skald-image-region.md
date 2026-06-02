# Skald Image Region Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a trailing optional `src: Rect = {}` argument to `skald.image` so Karl2D callers can draw an atlas sub-region through the ordinary layout widget while existing whole-image calls remain unchanged.

**Architecture:** Store the optional source rectangle on `View_Image`. Keep the existing `draw_image_fit_ctx` path for the zero-value whole-image sentinel. For an explicit source region, validate against the loaded image size, apply `Image_Fit` in core Skald as if the selected rectangle were a virtual image, clip to the widget slot, and dispatch through the existing optional `draw_image_region_ctx` backend service already implemented by Karl2D.

**Tech Stack:** Odin, Skald declarative views and layout renderer, existing backend-neutral image services, Karl2D texture region drawing, `core:testing`.

---

## File Structure

- Modify `skald/view.odin`: expose the public trailing `src` argument and retain it on `View_Image`.
- Modify `skald/layout.odin`: validate explicit image regions, calculate fitted source/destination rectangles, and route `View_Image` region draws through `draw_image_region_ctx`.
- Modify `skald/backend_fake_test.odin`: prove public builder storage, default-path compatibility, all four fit modes, clipping, invalid-region failure, and missing-backend-service failure.
- Modify `examples/51_karl2d_backgrounds/main.odin`: visually demonstrate ordinary `image(src = ...)` atlas rendering in the Karl2D example.
- Modify `docs/widgets.md`: document the public argument, fit semantics, and Karl2D-only explicit-region boundary.
- Modify `docs/examples.md`: mention atlas-backed image widgets in the Karl2D example summary.
- Modify `CHANGELOG.md`: record the new Karl2D image-widget capability.

The existing `Backend_Images.draw_region`, `draw_image_region_ctx`, and Karl2D `k2_image_draw_region` services already provide the required backend primitive. Do not add a new backend callback.

### Task 1: Store The Optional Source Region On The Image View

**Files:**
- Modify: `skald/backend_fake_test.odin:306`
- Modify: `skald/view.odin:699-713`
- Modify: `skald/view.odin:10008-10049`

- [ ] **Step 1: Write the failing public-builder test**

Add this test after `render_view_draws_image_through_backend_context` in `skald/backend_fake_test.odin`:

```odin
@(test)
image_builder_stores_optional_source_region :: proc(t: ^testing.T) {
	ctx: Ctx(int)
	src := Rect{32, 16, 64, 48}

	v := image(
		&ctx,
		"fake://atlas",
		width = 128,
		height = 96,
		fit = .Contain,
		tint = rgba(0x80FFFFFF),
		src = src,
	)

	switch vv in v {
	case View_Image:
		testing.expect_value(t, vv.path, "fake://atlas")
		testing.expect_value(t, vv.size, [2]f32{128, 96})
		testing.expect_value(t, vv.fit, Image_Fit.Contain)
		testing.expect_value(t, vv.tint, rgba(0x80FFFFFF))
		testing.expect_value(t, vv.src, src)
	case:
		testing.expect(t, false, "image must build View_Image")
	}
}
```

- [ ] **Step 2: Run the test suite to verify it fails**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL because `image` does not accept `src` and `View_Image` does not expose `src`.

- [ ] **Step 3: Add `src` to `View_Image` and the builder**

Update the `View_Image` comment and struct in `skald/view.odin`:

```odin
// View_Image is a textured quad backed by an on-disk image. `path` is
// the cache key — the renderer decodes the file via stb_image on first
// encounter and reuses the GPU texture thereafter. `size` is the layout
// slot; the renderer uses `fit` + the texture's natural dimensions to
// compute the actual quad rect and UV window.
//
// `src == {}` samples the whole image. A non-empty `src` is a source-image
// pixel rectangle supported by backends that implement region drawing.
// Fit modes treat that selected rectangle as a virtual image.
//
// `tint` modulates the sampled RGBA — pass `{1, 1, 1, 1}` (the default
// the builder supplies) for no tint. Handy for fade-in animations
// (scale the alpha) or theming monochrome assets.
View_Image :: struct {
	path: string,
	size: [2]f32,
	fit:  Image_Fit,
	tint: Color,
	src:  Rect,
}
```

Extend the builder comment immediately above `image`:

```odin
// `src == {}` samples the whole image. A non-empty source rectangle selects
// a pixel region and treats it as a virtual image for fit calculations.
// Explicit source regions currently require the Karl2D backend.
```

Extend the builder signature and returned view:

```odin
image :: proc(
	ctx:    ^Ctx($Msg),
	path:   string,
	width:  f32       = 0,
	height: f32       = 0,
	fit:    Image_Fit = .Cover,
	tint:   Color     = {1, 1, 1, 1},
	src:    Rect      = {},
) -> View {
	w := width
	h := height
	// Natural-size fallback needs the texture's real dimensions, so
	// decode eagerly. Cache hits after the first reference are free.
	if (w == 0 || h == 0) && ctx.renderer != nil {
		if entry := image_cache_get(ctx.renderer, path); entry != nil {
			if w == 0 {w = f32(entry.width)}
			if h == 0 {h = f32(entry.height)}
		}
	}
	return View_Image{
		path = path,
		size = {w, h},
		fit  = fit,
		tint = tint,
		src  = src,
	}
}
```

Do not change natural-size inference. `width` and `height` continue to behave exactly as before.

- [ ] **Step 4: Run the test suite to verify it passes**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS, including `image_builder_stores_optional_source_region`.

- [ ] **Step 5: Commit the public API storage change**

```bash
git add skald/view.odin skald/backend_fake_test.odin
git commit -m "feat: store optional image source region"
```

### Task 2: Render Explicit Regions With Existing Fit Semantics

**Files:**
- Modify: `skald/backend_fake_test.odin:306-335`
- Modify: `skald/layout.odin:1658-1673`
- Modify: `skald/layout.odin:1957-1967`

- [ ] **Step 1: Write failing fit-mode and failure-path tests**

Add this helper and these tests after `image_builder_stores_optional_source_region` in `skald/backend_fake_test.odin`:

```odin
@(private = "file")
expect_image_region_draw :: proc(
	t: ^testing.T,
	fit: Image_Fit,
	box: Rect,
	src: Rect,
	want_src: Rect,
	want_dst: Rect,
) {
	fake := Fake_Backend_State{image_native_size = {256, 128}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)

	render_view(
		&rc,
		View_Image{
			path = "fake://atlas",
			size = {box.w, box.h},
			fit = fit,
			tint = rgba(0x80FFFFFF),
			src = src,
		},
		{box.x, box.y},
		{box.w, box.h},
	)

	if !testing.expect_value(t, len(fake.ops), 3) {return}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Push_Clip)
	testing.expect_value(t, fake.ops[0].rect, box)
	testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Image)
	testing.expect_value(t, fake.ops[1].src, want_src)
	testing.expect_value(t, fake.ops[1].rect, want_dst)
	testing.expect_value(t, fake.ops[1].color, rgba(0x80FFFFFF))
	testing.expect_value(t, fake.ops[2].kind, Fake_Draw_Kind.Pop_Clip)
}

@(test)
render_view_draws_image_region_with_fill_fit :: proc(t: ^testing.T) {
	expect_image_region_draw(
		t,
		.Fill,
		Rect{5, 6, 100, 80},
		Rect{32, 16, 64, 48},
		Rect{32, 16, 64, 48},
		Rect{5, 6, 100, 80},
	)
}

@(test)
render_view_draws_image_region_with_none_fit :: proc(t: ^testing.T) {
	expect_image_region_draw(
		t,
		.None,
		Rect{5, 6, 100, 80},
		Rect{32, 16, 64, 48},
		Rect{32, 16, 64, 48},
		Rect{23, 22, 64, 48},
	)
}

@(test)
render_view_draws_image_region_with_contain_fit :: proc(t: ^testing.T) {
	expect_image_region_draw(
		t,
		.Contain,
		Rect{5, 6, 100, 100},
		Rect{32, 16, 64, 32},
		Rect{32, 16, 64, 32},
		Rect{5, 31, 100, 50},
	)
}

@(test)
render_view_draws_image_region_with_cover_fit :: proc(t: ^testing.T) {
	expect_image_region_draw(
		t,
		.Cover,
		Rect{5, 6, 100, 100},
		Rect{32, 16, 64, 32},
		Rect{48, 16, 32, 32},
		Rect{5, 6, 100, 100},
	)
}

@(test)
render_view_draws_placeholder_for_invalid_image_region :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {64, 64}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	rc := render_context_from_backend(&backend)

	render_view(
		&rc,
		View_Image{
			path = "fake://atlas",
			size = {20, 10},
			fit = .Fill,
			tint = {1, 1, 1, 1},
			src = {63, 0, 2, 2},
		},
		{5, 6},
		{20, 10},
	)

	if !testing.expect_value(t, len(fake.ops), 1) {return}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[0].rect, Rect{5, 6, 20, 10})
	testing.expect_value(t, fake.ops[0].color, Color{1, 0, 1, 1})
}

@(test)
render_view_draws_placeholder_when_image_region_service_is_missing :: proc(t: ^testing.T) {
	fake := Fake_Backend_State{image_native_size = {64, 64}}
	defer delete(fake.ops)
	backend := fake_backend(&fake)
	backend.images.draw_region = nil
	rc := render_context_from_backend(&backend)

	render_view(
		&rc,
		View_Image{
			path = "fake://atlas",
			size = {20, 10},
			fit = .Fill,
			tint = {1, 1, 1, 1},
			src = {0, 0, 2, 2},
		},
		{5, 6},
		{20, 10},
	)

	if !testing.expect_value(t, len(fake.ops), 1) {return}
	testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Rect)
	testing.expect_value(t, fake.ops[0].rect, Rect{5, 6, 20, 10})
	testing.expect_value(t, fake.ops[0].color, Color{1, 0, 1, 1})
}
```

The existing `render_view_draws_image_through_backend_context` test remains unchanged. It proves that `src == {}` continues to call the old whole-image `draw_fit` path with one image operation and no new source-region dispatch.

- [ ] **Step 2: Run the test suite to verify it fails**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL because explicit `src` values still render through `draw_image_fit_ctx`, so the fake backend records one whole-image operation instead of the clipped region operations.

- [ ] **Step 3: Add explicit-region validation and fit calculation**

Add these helpers after `rect_empty` in `skald/layout.odin`:

```odin
@(private)
image_region_valid :: proc(src: Rect, image_size: [2]f32) -> bool {
	if src.x < 0 || src.y < 0 || src.w <= 0 || src.h <= 0 {return false}
	return src.x + src.w <= image_size.x && src.y + src.h <= image_size.y
}

@(private)
image_region_fit_rects :: proc(
	box: Rect,
	src: Rect,
	fit: Image_Fit,
) -> (dst, fitted_src: Rect) {
	dst = box
	fitted_src = src
	if src.w <= 0 || src.h <= 0 || box.w <= 0 || box.h <= 0 {return}

	switch fit {
	case .Fill:
		dst = box
	case .None:
		dst = {
			box.x + (box.w - src.w) * 0.5,
			box.y + (box.h - src.h) * 0.5,
			src.w,
			src.h,
		}
	case .Contain:
		scale := min(box.w / src.w, box.h / src.h)
		w := src.w * scale
		h := src.h * scale
		dst = {box.x + (box.w - w) * 0.5, box.y + (box.h - h) * 0.5, w, h}
	case .Cover:
		box_aspect := box.w / box.h
		src_aspect := src.w / src.h
		dst = box
		if src_aspect > box_aspect {
			visible_w := src.w * (box_aspect / src_aspect)
			fitted_src.x += (src.w - visible_w) * 0.5
			fitted_src.w = visible_w
		} else {
			visible_h := src.h * (src_aspect / box_aspect)
			fitted_src.y += (src.h - visible_h) * 0.5
			fitted_src.h = visible_h
		}
	}
	return
}

@(private)
draw_image_region_fit_ctx :: proc(
	r: ^Render_Context,
	image: Backend_Image,
	src, box: Rect,
	fit: Image_Fit,
	tint: Color,
) -> bool {
	image_size, ok := image_size_ctx(r, image)
	if !ok || r.backend.images.draw_region == nil || !image_region_valid(src, image_size) {
		return false
	}
	dst, fitted_src := image_region_fit_rects(box, src, fit)
	push_clip(r, box)
	defer pop_clip(r)
	return draw_image_region_ctx(r, image, fitted_src, dst, tint)
}
```

`image_region_valid` is intentionally stricter than `nine_slice_region_valid`: the zero rectangle is handled by the caller as the whole-image sentinel, while any other explicit rectangle must have a usable positive extent.

- [ ] **Step 4: Route explicit `View_Image.src` values through region drawing**

Replace the final draw in the `View_Image` rendering branch:

```odin
		if vv.src == {} {
			draw_image_fit_ctx(r, img, box, vv.fit, vv.tint)
		} else if !draw_image_region_fit_ctx(r, img, vv.src, box, vv.fit, vv.tint) {
			// Explicit source regions are optional backend functionality.
			// Fail visibly on unsupported backends or invalid atlas bounds.
			draw_rect(r, box, {1, 0, 1, 1}, 0)
		}
```

Keep the existing image-load failure placeholder above this block unchanged.

- [ ] **Step 5: Run the focused test suite**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS. The old whole-image test and the new explicit-region tests must all pass.

- [ ] **Step 6: Run the default Runa-enabled suite**

Run:

```bash
odin test ./skald -collection:gui=.
```

Expected: PASS with no memory-leak warnings.

- [ ] **Step 7: Commit the render behavior**

```bash
git add skald/layout.odin skald/backend_fake_test.odin
git commit -m "feat: render image source regions in Karl2D"
```

### Task 3: Document And Demonstrate Karl2D Image Regions

**Files:**
- Modify: `examples/51_karl2d_backgrounds/main.odin:78-105`
- Modify: `docs/widgets.md:462-501`
- Modify: `docs/examples.md:90`
- Modify: `CHANGELOG.md:11`

- [ ] **Step 1: Add an ordinary image-region row to the Karl2D example**

In `examples/51_karl2d_backgrounds/main.odin`, add this row after the existing image-background row and before the nine-slice row:

```odin
		skald.text(
			"Ordinary image widgets can sample one atlas region; fit modes treat the selected rectangle as a virtual image.",
			th.color.fg_muted,
			th.font.size_md,
		),
		skald.row(
			skald.col(
				skald.image(ctx, FRAME_NAME, width = 96, height = 72, fit = .Fill, src = {17, 17, 28, 28}),
				skald.text(".Fill region", th.color.fg_muted, th.font.size_sm),
				spacing = th.spacing.xs,
			),
			skald.col(
				skald.image(ctx, FRAME_NAME, width = 96, height = 72, fit = .None, src = {17, 17, 28, 28}),
				skald.text(".None region", th.color.fg_muted, th.font.size_sm),
				spacing = th.spacing.xs,
			),
			skald.col(
				skald.image(ctx, FRAME_NAME, width = 96, height = 72, fit = .Contain, src = {17, 17, 56, 28}),
				skald.text(".Contain region", th.color.fg_muted, th.font.size_sm),
				spacing = th.spacing.xs,
			),
			skald.col(
				skald.image(ctx, FRAME_NAME, width = 96, height = 72, fit = .Cover, src = {17, 17, 56, 28}),
				skald.text(".Cover region", th.color.fg_muted, th.font.size_sm),
				spacing = th.spacing.xs,
			),
			spacing = th.spacing.md,
		),
```

The row deliberately exercises all four fit modes. `.Cover` must crop inside `{17, 17, 56, 28}` rather than sample neighbouring atlas pixels.

- [ ] **Step 2: Document the public argument and backend boundary**

Replace the image signature in `docs/widgets.md`:

```odin
image(ctx, path: string, width = 0, height = 0,
      fit = .Cover, tint = {1, 1, 1, 1}, src: Rect = {})
```

Add this text after the fit-mode paragraph:

```markdown
`src = {}` samples the whole image. A non-empty `src` selects a source-image
pixel rectangle and treats it as a virtual image for fitting: `.None` uses the
region's native dimensions, `.Contain` preserves its aspect ratio, and `.Cover`
crops only within that rectangle. Explicit `src` regions currently require the
Karl2D backend; SDL/Vulkan whole-image calls remain unchanged, while an
explicit-region request renders the unsupported-operation placeholder.
```

- [ ] **Step 3: Update the example catalogue**

Replace the `51_karl2d_backgrounds` row in `docs/examples.md` with:

```markdown
| `51_karl2d_backgrounds` | Karl2D-only image regions and container decoration using a real spritesheet: ordinary atlas-backed `image(src = ...)` widgets, fitted single-image backgrounds, asymmetric and open-sided nine-slice frames, a tiled center, and `#load`-embedded encoded image bytes. |
```

- [ ] **Step 4: Add the changelog entry**

Add this bullet at the top of `CHANGELOG.md` under `### Added`:

```markdown
- **Karl2D `image(src = ...)` atlas regions.** The ordinary `image` widget now
  accepts an optional source-image pixel rectangle. Existing fit modes treat
  the selected rectangle as a virtual image, so `.None`, `.Contain`, `.Cover`,
  and `.Fill` work without sampling neighbouring atlas pixels. Whole-image
  calls remain unchanged; explicit regions are currently Karl2D-only.
```

- [ ] **Step 5: Build the Karl2D visual example**

Run:

```bash
./build.sh 51_karl2d_backgrounds
```

Expected: PASS and produce `build/51_karl2d_backgrounds`.

- [ ] **Step 6: Check the Karl2D adapter package**

Run:

```bash
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Expected: PASS.

- [ ] **Step 7: Commit docs and example coverage**

```bash
git add CHANGELOG.md docs/widgets.md docs/examples.md examples/51_karl2d_backgrounds/main.odin
git commit -m "docs: demonstrate Karl2D image regions"
```

### Task 4: Final Verification

**Files:**
- Verify only

- [ ] **Step 1: Run the default core suite**

```bash
odin test ./skald -collection:gui=.
```

Expected: PASS with no memory-leak warnings.

- [ ] **Step 2: Run the legacy text-backend core suite**

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS with no memory-leak warnings.

- [ ] **Step 3: Check the Karl2D adapter**

```bash
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Expected: PASS.

- [ ] **Step 4: Build the existing native image example**

```bash
./build.sh 20_image
```

Expected: PASS and produce `build/20_image`. This verifies unchanged whole-image widget behavior still compiles for SDL/Vulkan.

- [ ] **Step 5: Build the Karl2D backgrounds and image-region example**

```bash
./build.sh 51_karl2d_backgrounds
```

Expected: PASS and produce `build/51_karl2d_backgrounds`.

- [ ] **Step 6: Check the final diff**

```bash
git diff --check main...HEAD
git status --short
```

Expected: no whitespace errors and a clean worktree.

- [ ] **Step 7: Review commits**

```bash
git log --oneline main..HEAD
```

Expected: the approved design and plan commits plus three focused implementation commits:

```text
docs: demonstrate Karl2D image regions
feat: render image source regions in Karl2D
feat: store optional image source region
docs: plan skald image region support
docs: design skald image region support
```
