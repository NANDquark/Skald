# Karl2D Container Image Backgrounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add single-image and explicit nine-slice decorative wrappers for Skald layout containers, with encoded `#load` asset registration and concrete backend support limited to Karl2D.

**Architecture:** Add optional image callbacks to Skald's backend service, then implement backend-neutral wrapper view nodes in the core layout walker. Wire the new callbacks only in `skald_karl2d`; leave SDL/Vulkan callback slots unset and verify that unsupported operations fail visibly without breaking the existing runtime.

**Tech Stack:** Odin, Skald backend services and declarative views, Karl2D texture APIs, `core:testing`, existing `odin test`, `odin check`, and `build.sh` verification.

---

## Scope Guard

This plan implements new concrete backend behavior only in `skald_karl2d`.

Do not implement `load_bytes`, `size`, or `draw_region` in Skald's
SDL/Vulkan compatibility backend. Its initializer in `skald/backend.odin`
must leave those optional callbacks unset. Compile-check existing desktop
examples to prove that deferring SDL/Vulkan implementation does not break the
current runtime, but do not claim desktop support for the new wrappers.

## File Map

- Modify `skald/backend.odin`: extend `Backend_Images` with optional callbacks.
- Modify `skald/image.odin`: add optional render-context dispatch helpers.
- Modify `skald/view.odin`: add public helpers, wrapper builders, view nodes,
  explicit `Nine_Slice`, and conservative decoration-extents calculation.
- Modify `skald/layout.odin`: measure wrappers and render single-image and
  nine-slice decoration.
- Modify `skald/backend_fake_test.odin`: cover backend dispatch, wrapper
  measurement, render order, tiling, clipping, and unsupported callbacks.
- Modify `skald_karl2d/backend.odin`: wire Karl2D image callbacks.
- Modify `skald_karl2d/image.odin`: implement encoded bytes, size queries, and
  source-region drawing.
- Create `examples/51_karl2d_backgrounds/main.odin`: demonstrate wrappers,
  explicit atlas regions, open sides, optional center, and `#load`.
- Modify `docs/widgets.md`: document Karl2D-only background wrappers and image
  helpers.
- Modify `docs/examples.md`: list the new focused Karl2D example.
- Modify `docs/architecture.md`: record the optional backend image extensions
  and SDL/Vulkan deferral.
- Modify `CHANGELOG.md`: record the Karl2D feature under `Unreleased`.

## Task 1: Add Optional Backend Image Hooks

**Files:**
- Modify: `skald/backend.odin:100-113`
- Modify: `skald/image.odin:598-671`
- Modify: `skald/backend_fake_test.odin:5-222`

- [ ] **Step 1: Write failing backend-dispatch tests**

Extend the fake backend records in `skald/backend_fake_test.odin`:

```odin
Fake_Draw_Op :: struct {
    kind:   Fake_Draw_Kind,
    rect:   Rect,
    src:    Rect,
    color:  Color,
    radius: f32,
    alpha:  f32,
    image:  Backend_Image,
    fit:    Image_Fit,
}

Fake_Backend_State :: struct {
    ops:               [dynamic]Fake_Draw_Op,
    image_load_path:   string,
    image_load_name:   string,
    image_w:           u32,
    image_h:           u32,
    image_rgba_len:    int,
    image_encoded_len: int,
    image_native_size: [2]f32,
    image_updated:     bool,
}
```

Add fake callbacks and wire them into `fake_backend`:

```odin
fake_image_load_bytes :: proc(state: rawptr, name: string, bytes: []byte) -> Backend_Image {
    s := (^Fake_Backend_State)(state)
    s.image_load_name = name
    s.image_encoded_len = len(bytes)
    if len(name) == 0 || len(bytes) == 0 {return Backend_Image(nil)}
    return Backend_Image(state)
}

fake_image_size :: proc(state: rawptr, image: Backend_Image) -> (size: [2]f32, ok: bool) {
    s := (^Fake_Backend_State)(state)
    return s.image_native_size, rawptr(image) != nil
}

fake_image_draw_region :: proc(
    state: rawptr,
    image: Backend_Image,
    src, dst: Rect,
    tint: Color,
) -> bool {
    s := (^Fake_Backend_State)(state)
    append(&s.ops, Fake_Draw_Op{kind = .Image, src = src, rect = dst, color = tint, image = image})
    return rawptr(image) != nil
}
```

Append focused tests:

```odin
@(test)
extended_image_context_helpers_dispatch_to_backend :: proc(t: ^testing.T) {
    fake := Fake_Backend_State{image_native_size = {64, 48}}
    defer delete(fake.ops)

    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    bytes := []byte{1, 2, 3, 4}

    img := image_load_bytes_ctx(&rc, "app://frame", bytes)
    testing.expect(t, rawptr(img) != nil)
    testing.expect_value(t, fake.image_load_name, "app://frame")
    testing.expect_value(t, fake.image_encoded_len, 4)

    size, ok := image_size_ctx(&rc, img)
    testing.expect_value(t, ok, true)
    testing.expect_value(t, size, [2]f32{64, 48})

    drawn := draw_image_region_ctx(
        &rc,
        img,
        Rect{1, 2, 3, 4},
        Rect{10, 20, 30, 40},
        rgba(0x80FFFFFF),
    )
    testing.expect_value(t, drawn, true)
    if !testing.expect_value(t, len(fake.ops), 1) {return}
    testing.expect_value(t, fake.ops[0].src, Rect{1, 2, 3, 4})
    testing.expect_value(t, fake.ops[0].rect, Rect{10, 20, 30, 40})
    testing.expect_value(t, fake.ops[0].color, rgba(0x80FFFFFF))
}

@(test)
optional_image_context_helpers_fail_without_backend_callbacks :: proc(t: ^testing.T) {
    fake: Fake_Backend_State
    backend := fake_backend(&fake)
    backend.images.load_bytes = nil
    backend.images.size = nil
    backend.images.draw_region = nil
    rc := render_context_from_backend(&backend)

    img := Backend_Image(rawptr(&fake))
    testing.expect(t, rawptr(image_load_bytes_ctx(&rc, "app://missing", []byte{1})) == nil)
    _, size_ok := image_size_ctx(&rc, img)
    testing.expect_value(t, size_ok, false)
    testing.expect_value(
        t,
        draw_image_region_ctx(&rc, img, Rect{0, 0, 1, 1}, Rect{0, 0, 1, 1}),
        false,
    )
}
```

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL because `Backend_Images` and the three context helpers do not
yet define `load_bytes`, `size`, or `draw_region`.

- [ ] **Step 3: Extend the backend service with optional callbacks**

Add fields to `Backend_Images` in `skald/backend.odin`:

```odin
Backend_Images :: struct {
    load_path:     proc(state: rawptr, path: string) -> Backend_Image,
    load_bytes:    proc(state: rawptr, name: string, bytes: []byte) -> Backend_Image,
    load_pixels:   proc(state: rawptr, name: string, w, h: u32, rgba: []u8) -> Backend_Image,
    update_pixels: proc(state: rawptr, image: Backend_Image, w, h: u32, rgba: []u8) -> bool,
    unload:        proc(state: rawptr, image: Backend_Image),
    size:          proc(state: rawptr, image: Backend_Image) -> (size: [2]f32, ok: bool),
    draw:          proc(state: rawptr, image: Backend_Image, rect: Rect, tint: Color),
    draw_fit:      proc(
        state: rawptr,
        image: Backend_Image,
        rect: Rect,
        fit: Image_Fit,
        tint: Color,
    ) -> bool,
    draw_region: proc(
        state: rawptr,
        image: Backend_Image,
        src, dst: Rect,
        tint: Color,
    ) -> bool,
}
```

Do not wire these fields in `renderer_backend`. Leaving them unset is the
intentional SDL/Vulkan deferral.

- [ ] **Step 4: Add optional render-context helpers**

Add these helpers in `skald/image.odin` after `image_load_path_ctx` and after
`draw_image_fit_ctx` as appropriate:

```odin
image_load_bytes_ctx :: proc(r: ^Render_Context, name: string, bytes: []byte) -> Backend_Image {
    if r == nil || r.backend == nil || r.backend.images.load_bytes == nil {
        return Backend_Image(nil)
    }
    return r.backend.images.load_bytes(r.backend.state, name, bytes)
}

image_size_ctx :: proc(r: ^Render_Context, image: Backend_Image) -> (size: [2]f32, ok: bool) {
    if r == nil || r.backend == nil || r.backend.images.size == nil || rawptr(image) == nil {
        return {}, false
    }
    return r.backend.images.size(r.backend.state, image)
}

draw_image_region_ctx :: proc(
    r: ^Render_Context,
    image: Backend_Image,
    src, dst: Rect,
    tint: Color = Color{1, 1, 1, 1},
) -> bool {
    if r == nil || r.backend == nil || r.backend.images.draw_region == nil || rawptr(image) == nil {
        return false
    }
    return r.backend.images.draw_region(r.backend.state, image, src, dst, tint)
}
```

Keep these helpers non-asserting because the new callbacks are optional by
design.

- [ ] **Step 5: Wire fake callbacks and run tests**

Add to `fake_backend`:

```odin
load_bytes = fake_image_load_bytes,
size = fake_image_size,
draw_region = fake_image_draw_region,
```

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
./build.sh 01_hello
```

Expected: PASS. The desktop example must still compile with the SDL/Vulkan
compatibility backend leaving new callback slots unset.

- [ ] **Step 6: Commit**

```bash
git add skald/backend.odin skald/image.odin skald/backend_fake_test.odin
git commit -m "feat: add optional backend image region services"
```

## Task 2: Add Wrapper View Models And Measurement

**Files:**
- Modify: `skald/view.odin:88-118`
- Modify: `skald/view.odin:626-650`
- Modify: `skald/view.odin:9576-9617`
- Modify: `skald/layout.odin:42-87`
- Modify: `skald/layout.odin:270-292`
- Modify: `skald/backend_fake_test.odin`

- [ ] **Step 1: Write failing measurement and public-helper tests**

Append to `skald/backend_fake_test.odin`:

```odin
@(test)
public_image_helpers_use_render_context :: proc(t: ^testing.T) {
    fake := Fake_Backend_State{image_native_size = {64, 48}}
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    testing.expect_value(t, image_load_bytes(&ctx, "app://frame", []byte{1, 2, 3}), true)
    size, ok := image_size(&ctx, "app://frame")
    testing.expect_value(t, ok, true)
    testing.expect_value(t, size, [2]f32{64, 48})
}

@(test)
image_background_intrinsic_size_matches_child :: proc(t: ^testing.T) {
    fake: Fake_Backend_State
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    v := image_background(&ctx, "app://paper", rect({20, 10}, rgb(0xFFFFFF)))
    testing.expect_value(t, view_size(&rc, v), [2]f32{20, 10})
}

@(test)
nine_slice_intrinsic_size_adds_asymmetric_decoration_extents :: proc(t: ^testing.T) {
    fake: Fake_Backend_State
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    slice := Nine_Slice{
        top_left     = {0, 0, 3, 5},
        top          = {3, 0, 4, 7},
        top_right    = {7, 0, 8, 4},
        left         = {0, 5, 6, 3},
        right        = {9, 4, 2, 9},
        bottom_left  = {0, 8, 4, 10},
        bottom       = {4, 9, 3, 2},
        bottom_right = {7, 9, 5, 6},
    }
    v := nine_slice_background(&ctx, "app://frame", slice, rect({20, 10}, rgb(0xFFFFFF)))
    testing.expect_value(t, view_size(&rc, v), [2]f32{34, 27})
}
```

The expected nine-slice size is `{20 + max(3,6,4) + max(8,2,5),
10 + max(5,7,4) + max(10,2,6)}`.

- [ ] **Step 2: Run tests to verify failure**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL because the public helpers, descriptor, wrappers, and view
variants do not exist.

- [ ] **Step 3: Add the descriptor, wrappers, and builders**

Add `View_Image_Background` and `View_Nine_Slice_Background` to `View`.
Place the structs after `View_Image`, and place the public builders after
`image()`:

```odin
Nine_Slice :: struct {
    top_left:     Rect,
    top:          Rect,
    top_right:    Rect,
    left:         Rect,
    center:       Rect,
    right:        Rect,
    bottom_left:  Rect,
    bottom:       Rect,
    bottom_right: Rect,
}

Nine_Slice_Extents :: struct {
    left, top, right, bottom: f32,
}

nine_slice_extents :: proc(slice: Nine_Slice) -> Nine_Slice_Extents {
    return {
        left   = max(slice.top_left.w, max(slice.left.w, slice.bottom_left.w)),
        top    = max(slice.top_left.h, max(slice.top.h, slice.top_right.h)),
        right  = max(slice.top_right.w, max(slice.right.w, slice.bottom_right.w)),
        bottom = max(slice.bottom_left.h, max(slice.bottom.h, slice.bottom_right.h)),
    }
}

View_Image_Background :: struct {
    path:  string,
    fit:   Image_Fit,
    tint:  Color,
    child: ^View,
}

View_Nine_Slice_Background :: struct {
    path:  string,
    slice: Nine_Slice,
    tint:  Color,
    child: ^View,
}

image_background :: proc(
    ctx:   ^Ctx($Msg),
    path:  string,
    child: View,
    fit:   Image_Fit = .None,
    tint:  Color = {1, 1, 1, 1},
) -> View {
    _ = ctx
    c := new(View, context.temp_allocator)
    c^ = child
    return View_Image_Background{path = path, fit = fit, tint = tint, child = c}
}

nine_slice_background :: proc(
    ctx:   ^Ctx($Msg),
    path:  string,
    slice: Nine_Slice,
    child: View,
    tint:  Color = {1, 1, 1, 1},
) -> View {
    _ = ctx
    c := new(View, context.temp_allocator)
    c^ = child
    return View_Nine_Slice_Background{path = path, slice = slice, tint = tint, child = c}
}
```

- [ ] **Step 4: Add public backend-neutral image helpers**

Add in `skald/view.odin` beside `image()`:

```odin
image_load_bytes :: proc(ctx: ^Ctx($Msg), name: string, bytes: []byte) -> bool {
    if ctx == nil || ctx.render == nil {return false}
    return rawptr(image_load_bytes_ctx(ctx.render, name, bytes)) != nil
}

image_size :: proc(ctx: ^Ctx($Msg), path: string) -> (size: [2]f32, ok: bool) {
    if ctx == nil || ctx.render == nil {return {}, false}
    image := image_load_path_ctx(ctx.render, path)
    if rawptr(image) == nil {return {}, false}
    return image_size_ctx(ctx.render, image)
}
```

- [ ] **Step 5: Thread wrapper measurement through layout**

Add these cases to `view_height_for_width`:

```odin
case View_Image_Background:
    return view_height_for_width(r, vv.child^, width)

case View_Nine_Slice_Background:
    ext := nine_slice_extents(vv.slice)
    child_w := max(width - ext.left - ext.right, 0)
    return ext.top + view_height_for_width(r, vv.child^, child_w) + ext.bottom
```

Add these cases to `view_size`:

```odin
case View_Image_Background:
    return view_size(r, vv.child^)

case View_Nine_Slice_Background:
    ext := nine_slice_extents(vv.slice)
    child := view_size(r, vv.child^)
    return {child.x + ext.left + ext.right, child.y + ext.top + ext.bottom}
```

- [ ] **Step 6: Run tests and commit**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

Commit:

```bash
git add skald/view.odin skald/layout.odin skald/backend_fake_test.odin
git commit -m "feat: add container background wrapper views"
```

## Task 3: Render Single Images And Explicit Nine-Slice Tiles

**Files:**
- Modify: `skald/layout.odin:335-590`
- Modify: `skald/layout.odin:1760-1773`
- Modify: `skald/backend_fake_test.odin`

- [ ] **Step 1: Write failing single-image render-order test**

Append:

```odin
@(test)
image_background_draws_before_child_inside_wrapper_clip :: proc(t: ^testing.T) {
    fake: Fake_Backend_State
    defer delete(fake.ops)
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    v := image_background(
        &ctx,
        "app://paper",
        rect({0, 0}, rgb(0x00FF00)),
        fit = .Contain,
        tint = rgba(0x80FFFFFF),
    )
    render_view(&rc, v, {5, 6}, {30, 40})

    if !testing.expect_value(t, len(fake.ops), 4) {return}
    testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Push_Clip)
    testing.expect_value(t, fake.ops[0].rect, Rect{5, 6, 30, 40})
    testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Image)
    testing.expect_value(t, fake.ops[1].fit, Image_Fit.Contain)
    testing.expect_value(t, fake.ops[1].color, rgba(0x80FFFFFF))
    testing.expect_value(t, fake.ops[2].kind, Fake_Draw_Kind.Rect)
    testing.expect_value(t, fake.ops[2].rect, Rect{5, 6, 30, 40})
    testing.expect_value(t, fake.ops[3].kind, Fake_Draw_Kind.Pop_Clip)
}
```

The fake `draw_fit` does not push its own clip. The wrapper contributes
operations 0 and 3. Keep the implementation minimal: one wrapper clip
brackets image drawing and child rendering.

- [ ] **Step 2: Write failing asymmetric nine-slice tiling tests**

Append:

```odin
@(test)
nine_slice_background_tiles_partial_top_edge_and_places_child_in_conservative_interior :: proc(
    t: ^testing.T,
) {
    fake := Fake_Backend_State{image_native_size = {32, 32}}
    defer delete(fake.ops)
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    slice := Nine_Slice{
        top_left  = {0, 0, 3, 4},
        top       = {3, 0, 4, 2},
        top_right = {7, 0, 5, 6},
        left      = {0, 4, 2, 3},
    }
    v := nine_slice_background(&ctx, "app://frame", slice, rect({0, 0}, rgb(0x00FF00)))
    render_view(&rc, v, {10, 20}, {19, 16})

    testing.expect_value(t, fake.ops[1].src, Rect{0, 0, 3, 4})
    testing.expect_value(t, fake.ops[1].rect, Rect{10, 20, 3, 4})
    testing.expect_value(t, fake.ops[2].src, Rect{7, 0, 5, 6})
    testing.expect_value(t, fake.ops[2].rect, Rect{24, 20, 5, 6})

    // Available top span is 19 - 3 - 5 = 11, so tile widths are 4 + 4 + 3.
    testing.expect_value(t, fake.ops[3].src, Rect{3, 0, 4, 2})
    testing.expect_value(t, fake.ops[3].rect, Rect{13, 20, 4, 2})
    testing.expect_value(t, fake.ops[4].src, Rect{3, 0, 4, 2})
    testing.expect_value(t, fake.ops[4].rect, Rect{17, 20, 4, 2})
    testing.expect_value(t, fake.ops[5].src, Rect{3, 0, 3, 2})
    testing.expect_value(t, fake.ops[5].rect, Rect{21, 20, 3, 2})

    // Conservative extents: left=max(3,2,0), top=max(4,2,6).
    // Child receives x=13, y=26, w=11, h=10.
    testing.expect_value(t, fake.ops[len(fake.ops) - 2].kind, Fake_Draw_Kind.Rect)
    testing.expect_value(t, fake.ops[len(fake.ops) - 2].rect, Rect{13, 26, 11, 10})
}

@(test)
nine_slice_background_tiles_center_with_partial_column_and_row :: proc(t: ^testing.T) {
    fake := Fake_Backend_State{image_native_size = {16, 16}}
    defer delete(fake.ops)
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    slice := Nine_Slice{center = {4, 5, 3, 2}}
    v := nine_slice_background(&ctx, "app://center", slice, spacer(0))
    render_view(&rc, v, {0, 0}, {8, 5})

    // 3 + 3 + 2 columns crossed with 2 + 2 + 1 rows.
    testing.expect_value(t, len(fake.ops), 11)
    testing.expect_value(t, fake.ops[9].src, Rect{4, 5, 2, 1})
    testing.expect_value(t, fake.ops[9].rect, Rect{6, 4, 2, 1})
}
```

The expected operation indexes assume the minimal render order described
above: wrapper clip, decoration, child, wrapper pop.

- [ ] **Step 3: Run tests to verify failure**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: FAIL because wrapper cases are not rendered.

- [ ] **Step 4: Add reusable tile helpers**

Import `core:fmt` in `skald/layout.odin` for debug warnings. Add private
helpers above `draw_focus_ring`:

```odin
@(private)
rect_empty :: proc(r: Rect) -> bool {
    return r.w == 0 || r.h == 0
}

@(private)
nine_slice_region_valid :: proc(r: Rect, image_size: [2]f32) -> bool {
    if r.w < 0 || r.h < 0 || r.x < 0 || r.y < 0 {return false}
    if rect_empty(r) {return true}
    return r.x + r.w <= image_size.x && r.y + r.h <= image_size.y
}

@(private)
draw_image_region_tiled_x :: proc(
    r: ^Render_Context,
    image: Backend_Image,
    src: Rect,
    dst: Rect,
    tint: Color,
) -> bool {
    if rect_empty(src) || dst.w <= 0 || dst.h <= 0 {return true}
    x := dst.x
    remaining := dst.w
    for remaining > 0 {
        width := min(src.w, remaining)
        part := src
        part.w = width
        if !draw_image_region_ctx(r, image, part, Rect{x, dst.y, width, dst.h}, tint) {return false}
        x += width
        remaining -= width
    }
    return true
}

@(private)
draw_image_region_tiled_y :: proc(
    r: ^Render_Context,
    image: Backend_Image,
    src: Rect,
    dst: Rect,
    tint: Color,
) -> bool {
    if rect_empty(src) || dst.w <= 0 || dst.h <= 0 {return true}
    y := dst.y
    remaining := dst.h
    for remaining > 0 {
        height := min(src.h, remaining)
        part := src
        part.h = height
        if !draw_image_region_ctx(r, image, part, Rect{dst.x, y, dst.w, height}, tint) {return false}
        y += height
        remaining -= height
    }
    return true
}

@(private)
draw_image_region_tiled_xy :: proc(
    r: ^Render_Context,
    image: Backend_Image,
    src: Rect,
    dst: Rect,
    tint: Color,
) -> bool {
    if rect_empty(src) || dst.w <= 0 || dst.h <= 0 {return true}
    y := dst.y
    remaining_h := dst.h
    for remaining_h > 0 {
        height := min(src.h, remaining_h)
        x := dst.x
        remaining_w := dst.w
        for remaining_w > 0 {
            width := min(src.w, remaining_w)
            part := src
            part.w = width
            part.h = height
            if !draw_image_region_ctx(r, image, part, Rect{x, y, width, height}, tint) {return false}
            x += width
            remaining_w -= width
        }
        y += height
        remaining_h -= height
    }
    return true
}
```

- [ ] **Step 5: Add nine-slice validation and drawing**

Add:

```odin
@(private)
draw_nine_slice_background :: proc(
    r: ^Render_Context,
    image: Backend_Image,
    bounds: Rect,
    slice: Nine_Slice,
    tint: Color,
) -> bool {
    image_size, ok := image_size_ctx(r, image)
    if !ok || r.backend.images.draw_region == nil {return false}

    regions := [?]Rect{
        slice.top_left, slice.top, slice.top_right,
        slice.left, slice.center, slice.right,
        slice.bottom_left, slice.bottom, slice.bottom_right,
    }
    for region in regions {
        if !nine_slice_region_valid(region, image_size) {return false}
    }

    ext := nine_slice_extents(slice)
    inner := Rect{
        bounds.x + ext.left,
        bounds.y + ext.top,
        max(bounds.w - ext.left - ext.right, 0),
        max(bounds.h - ext.top - ext.bottom, 0),
    }

    if !rect_empty(slice.top_left) {
        if !draw_image_region_ctx(r, image, slice.top_left, Rect{bounds.x, bounds.y, slice.top_left.w, slice.top_left.h}, tint) {return false}
    }
    if !rect_empty(slice.top_right) {
        if !draw_image_region_ctx(r, image, slice.top_right, Rect{bounds.x + bounds.w - slice.top_right.w, bounds.y, slice.top_right.w, slice.top_right.h}, tint) {return false}
    }
    if !rect_empty(slice.bottom_left) {
        if !draw_image_region_ctx(r, image, slice.bottom_left, Rect{bounds.x, bounds.y + bounds.h - slice.bottom_left.h, slice.bottom_left.w, slice.bottom_left.h}, tint) {return false}
    }
    if !rect_empty(slice.bottom_right) {
        if !draw_image_region_ctx(r, image, slice.bottom_right, Rect{bounds.x + bounds.w - slice.bottom_right.w, bounds.y + bounds.h - slice.bottom_right.h, slice.bottom_right.w, slice.bottom_right.h}, tint) {return false}
    }

    if !draw_image_region_tiled_x(r, image, slice.top, Rect{bounds.x + slice.top_left.w, bounds.y, max(bounds.w - slice.top_left.w - slice.top_right.w, 0), slice.top.h}, tint) {return false}
    if !draw_image_region_tiled_x(r, image, slice.bottom, Rect{bounds.x + slice.bottom_left.w, bounds.y + bounds.h - slice.bottom.h, max(bounds.w - slice.bottom_left.w - slice.bottom_right.w, 0), slice.bottom.h}, tint) {return false}
    if !draw_image_region_tiled_y(r, image, slice.left, Rect{bounds.x, bounds.y + slice.top_left.h, slice.left.w, max(bounds.h - slice.top_left.h - slice.bottom_left.h, 0)}, tint) {return false}
    if !draw_image_region_tiled_y(r, image, slice.right, Rect{bounds.x + bounds.w - slice.right.w, bounds.y + slice.top_right.h, slice.right.w, max(bounds.h - slice.top_right.h - slice.bottom_right.h, 0)}, tint) {return false}
    if !draw_image_region_tiled_xy(r, image, slice.center, inner, tint) {return false}
    return true
}
```

Keep each edge independent. Do not enforce matching corner dimensions.

- [ ] **Step 6: Render wrapper variants and unsupported placeholders**

Add cases to `render_view` immediately after `View_Image`:

```odin
case View_Image_Background:
    bounds := Rect{origin.x, origin.y, size.x, size.y}
    push_clip(r, bounds)
    image := image_load_path_ctx(r, vv.path)
    if rawptr(image) == nil || !draw_image_fit_ctx(r, image, bounds, vv.fit, vv.tint) {
        draw_rect(r, bounds, {1, 0, 1, 1}, 0)
    }
    render_view(r, vv.child^, origin, size)
    pop_clip(r)

case View_Nine_Slice_Background:
    ext := nine_slice_extents(vv.slice)
    bounds := Rect{origin.x, origin.y, size.x, size.y}
    child_size := [2]f32{
        max(size.x - ext.left - ext.right, 0),
        max(size.y - ext.top - ext.bottom, 0),
    }
    child_origin := [2]f32{origin.x + ext.left, origin.y + ext.top}

    push_clip(r, bounds)
    image := image_load_path_ctx(r, vv.path)
    if rawptr(image) == nil || !draw_nine_slice_background(r, image, bounds, vv.slice, vv.tint) {
        when ODIN_DEBUG {
            fmt.eprintfln("skald: nine-slice background unsupported or invalid: %s", vv.path)
        }
        draw_rect(r, bounds, {1, 0, 1, 1}, 0)
    }
    render_view(r, vv.child^, child_origin, child_size)
    pop_clip(r)
```

Before `push_clip`, add:

```odin
when ODIN_DEBUG {
    if size.x < ext.left + ext.right || size.y < ext.top + ext.bottom {
        fmt.eprintfln(
            "skald: nine-slice destination smaller than decoration extents: %s",
            vv.path,
        )
    }
}
```

Keep drawing through the active wrapper clip and clamp the child interior to
zero.

- [ ] **Step 7: Add focused invalid and unsupported-path tests**

Append:

```odin
@(test)
nine_slice_background_draws_placeholder_when_region_service_is_missing :: proc(t: ^testing.T) {
    fake := Fake_Backend_State{image_native_size = {16, 16}}
    defer delete(fake.ops)
    backend := fake_backend(&fake)
    backend.images.draw_region = nil
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    slice := Nine_Slice{top_left = {0, 0, 4, 4}}
    v := nine_slice_background(&ctx, "app://frame", slice, rect({0, 0}, rgb(0x00FF00)))
    render_view(&rc, v, {1, 2}, {20, 12})

    if !testing.expect_value(t, len(fake.ops), 4) {return}
    testing.expect_value(t, fake.ops[0].kind, Fake_Draw_Kind.Push_Clip)
    testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Rect)
    testing.expect_value(t, fake.ops[1].rect, Rect{1, 2, 20, 12})
    testing.expect_value(t, fake.ops[1].color, Color{1, 0, 1, 1})
    testing.expect_value(t, fake.ops[2].rect, Rect{5, 6, 16, 8})
    testing.expect_value(t, fake.ops[3].kind, Fake_Draw_Kind.Pop_Clip)
}

@(test)
nine_slice_background_draws_placeholder_for_out_of_bounds_source :: proc(t: ^testing.T) {
    fake := Fake_Backend_State{image_native_size = {8, 8}}
    defer delete(fake.ops)
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    slice := Nine_Slice{top_left = {7, 7, 2, 2}}
    v := nine_slice_background(&ctx, "app://invalid", slice, spacer(0))
    render_view(&rc, v, {0, 0}, {12, 12})

    testing.expect_value(t, fake.ops[1].kind, Fake_Draw_Kind.Rect)
    testing.expect_value(t, fake.ops[1].color, Color{1, 0, 1, 1})
}

@(test)
nine_slice_background_clamps_child_when_destination_is_too_small :: proc(t: ^testing.T) {
    fake := Fake_Backend_State{image_native_size = {16, 16}}
    defer delete(fake.ops)
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    slice := Nine_Slice{
        top_left = {0, 0, 6, 7},
        top_right = {6, 0, 6, 7},
        bottom_left = {0, 7, 6, 7},
        bottom_right = {6, 7, 6, 7},
    }
    v := nine_slice_background(&ctx, "app://tight", slice, rect({0, 0}, rgb(0x00FF00)))
    render_view(&rc, v, {10, 20}, {8, 8})

    testing.expect_value(t, fake.ops[len(fake.ops) - 2].kind, Fake_Draw_Kind.Rect)
    testing.expect_value(t, fake.ops[len(fake.ops) - 2].rect, Rect{16, 27, 0, 0})
}

@(test)
nine_slice_background_allows_corner_only_frames :: proc(t: ^testing.T) {
    fake := Fake_Backend_State{image_native_size = {16, 16}}
    defer delete(fake.ops)
    backend := fake_backend(&fake)
    rc := render_context_from_backend(&backend)
    ctx := Ctx(int){render = &rc}

    slice := Nine_Slice{
        top_left = {0, 0, 3, 4},
        bottom_right = {4, 5, 6, 7},
    }
    v := nine_slice_background(&ctx, "app://corners", slice, spacer(0))
    render_view(&rc, v, {10, 20}, {30, 40})

    if !testing.expect_value(t, len(fake.ops), 4) {return}
    testing.expect_value(t, fake.ops[1].src, Rect{0, 0, 3, 4})
    testing.expect_value(t, fake.ops[1].rect, Rect{10, 20, 3, 4})
    testing.expect_value(t, fake.ops[2].src, Rect{4, 5, 6, 7})
    testing.expect_value(t, fake.ops[2].rect, Rect{34, 53, 6, 7})
}
```

- [ ] **Step 8: Run tests and commit**

Run:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

Commit:

```bash
git add skald/layout.odin skald/backend_fake_test.odin
git commit -m "feat: render tiled nine-slice container backgrounds"
```

## Task 4: Implement Karl2D Image Services

**Files:**
- Modify: `skald_karl2d/backend.odin:54-61`
- Modify: `skald_karl2d/image.odin:13-194`

- [ ] **Step 1: Write the Karl2D callback wiring before implementation**

Add to `skald_karl2d/backend.odin`:

```odin
load_bytes = k2_image_load_bytes,
size = k2_image_size,
draw_region = k2_image_draw_region,
```

- [ ] **Step 2: Run Karl2D library check to verify failure**

Run:

```bash
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Expected: FAIL because the three Karl2D procedures are undefined.

- [ ] **Step 3: Implement idempotent encoded-byte loading**

Add to `skald_karl2d/image.odin` after `k2_image_load_path`:

```odin
k2_image_load_bytes :: proc(state: rawptr, name: string, bytes: []byte) -> skald.Backend_Image {
    if len(name) == 0 || len(bytes) == 0 {return skald.Backend_Image(nil)}
    s := (^Backend_State)(state)
    if s.images == nil {
        s.images = make(map[string]^Image_Entry)
    }
    if entry, ok := s.images[name]; ok && entry != nil {
        if entry.alive {return skald.Backend_Image(entry)}
        texture := k2.load_texture_from_bytes(bytes)
        if texture.handle == k2.TEXTURE_NONE {return skald.Backend_Image(nil)}
        entry.texture = texture
        entry.alive = true
        return skald.Backend_Image(entry)
    }

    texture := k2.load_texture_from_bytes(bytes)
    if texture.handle == k2.TEXTURE_NONE {return skald.Backend_Image(nil)}
    key := strings.clone(name)
    entry := new(Image_Entry)
    entry^ = Image_Entry{key = key, texture = texture, alive = true}
    s.images[key] = entry
    return skald.Backend_Image(entry)
}
```

The live-entry early return is required because declarative `view` rebuilds
may call `image_load_bytes` every frame.

- [ ] **Step 4: Implement native-size queries and source-region draws**

Add after `k2_image_draw_fit`:

```odin
k2_image_size :: proc(state: rawptr, image: skald.Backend_Image) -> (size: [2]f32, ok: bool) {
    entry := (^Image_Entry)(rawptr(image))
    if entry == nil || !entry.alive || entry.texture.handle == k2.TEXTURE_NONE {
        return {}, false
    }
    return {f32(entry.texture.width), f32(entry.texture.height)}, true
}

k2_image_draw_region :: proc(
    state: rawptr,
    image: skald.Backend_Image,
    src, dst: skald.Rect,
    tint: skald.Color,
) -> bool {
    entry := (^Image_Entry)(rawptr(image))
    if entry == nil || !entry.alive || entry.texture.handle == k2.TEXTURE_NONE {
        return false
    }
    s := (^Backend_State)(state)
    k2.draw_texture_fit(entry.texture, to_k2_rect(src), to_k2_rect(dst), tint = to_k2_color(tint, s.alpha))
    return true
}
```

- [ ] **Step 5: Verify Karl2D and existing desktop compilation**

Run:

```bash
odin check ./skald_karl2d -collection:gui=. -no-entry-point
./build.sh 01_hello
./build.sh 20_image
./build.sh 50_karl2d_overlay
```

Expected: PASS. `20_image` proves the pre-existing SDL/Vulkan image widget
still compiles without implementing the new optional callbacks.

- [ ] **Step 6: Commit**

```bash
git add skald_karl2d/backend.odin skald_karl2d/image.odin
git commit -m "feat: support background image regions in Karl2D"
```

## Task 5: Add A Focused Karl2D Background Example And Documentation

**Files:**
- Create: `examples/51_karl2d_backgrounds/main.odin`
- Modify: `docs/examples.md:84-89`
- Modify: `docs/widgets.md:462-543`
- Modify: `docs/architecture.md:253-265`
- Modify: `CHANGELOG.md:7-35`

- [ ] **Step 1: Create the Karl2D-only visual example**

Create `examples/51_karl2d_backgrounds/main.odin`. Embed the existing
`64 x 64` Karl2D tile atlas so the example adds no generated binary asset:

```odin
package karl2d_backgrounds

import k2 "../../karl2d"
import "../../skald"
import skald_k2 "../../skald_karl2d"
import "core:fmt"

ATLAS_NAME :: "app://karl2d-background-atlas"
ATLAS_PNG  :: #load("../../karl2d/examples/dual_grid_tilemap/tileset_path.png", []byte)

FRAME :: skald.Nine_Slice {
    top_left     = {0, 0, 16, 16},
    top          = {16, 0, 16, 16},
    top_right    = {32, 0, 16, 16},
    left         = {0, 16, 16, 16},
    center       = {16, 16, 16, 16},
    right        = {32, 16, 16, 16},
    bottom_left  = {0, 32, 16, 16},
    bottom       = {16, 32, 16, 16},
    bottom_right = {32, 32, 16, 16},
}

ASYMMETRIC_FRAME :: skald.Nine_Slice {
    top_left     = {0, 0, 16, 16},
    top          = {16, 0, 8, 16},
    top_right    = {32, 0, 16, 8},
    left         = {0, 16, 16, 8},
    right        = {32, 16, 8, 16},
    bottom_left  = {0, 32, 8, 16},
    bottom       = {16, 32, 16, 8},
    bottom_right = {32, 32, 16, 16},
}

OPEN_FRAME :: skald.Nine_Slice {
    top_left  = {0, 0, 16, 16},
    top       = {16, 0, 16, 16},
    top_right = {32, 0, 16, 16},
    left      = {0, 16, 16, 16},
    right     = {32, 16, 16, 16},
}

State :: struct {}
Msg :: enum {Unused}

init :: proc() -> State {return {}}

update :: proc(s: State, m: Msg) -> (State, skald.Command(Msg)) {
    _ = m
    return s, {}
}

panel_content :: proc(
    ctx: ^skald.Ctx(Msg),
    title, body: string,
    bg: skald.Color = {},
) -> skald.View {
    th := ctx.theme
    return skald.col(
        skald.text(title, th.color.fg, th.font.size_lg),
        skald.text(body, th.color.fg_muted, th.font.size_sm),
        spacing = th.spacing.xs,
        padding = th.spacing.md,
        width = 220,
        height = 96,
        bg = bg,
    )
}

view :: proc(s: State, ctx: ^skald.Ctx(Msg)) -> skald.View {
    _ = s
    th := ctx.theme
    _ = skald.image_load_bytes(ctx, ATLAS_NAME, ATLAS_PNG)
    atlas_size, _ := skald.image_size(ctx, ATLAS_NAME)

    return skald.col(
        skald.text("Karl2D container image backgrounds", th.color.fg, th.font.size_xl),
        skald.text(
            "Embedded atlas loaded through #load; single images fit normally and nine-slice frames tile without stretching.",
            th.color.fg_muted,
            th.font.size_md,
        ),
        skald.text(
            fmt.tprintf("atlas size: %.0f x %.0f", atlas_size.x, atlas_size.y),
            th.color.fg_muted,
            th.font.size_sm,
        ),
        skald.row(
            skald.image_background(ctx, ATLAS_NAME, panel_content(ctx, ".None", "native pixels"), fit = .None),
            skald.image_background(ctx, ATLAS_NAME, panel_content(ctx, ".Contain", "preserve aspect"), fit = .Contain),
            skald.image_background(ctx, ATLAS_NAME, panel_content(ctx, ".Cover", "explicit crop"), fit = .Cover),
            skald.image_background(ctx, ATLAS_NAME, panel_content(ctx, ".Fill", "explicit stretch"), fit = .Fill),
            spacing = th.spacing.md,
        ),
        skald.row(
            skald.nine_slice_background(ctx, ATLAS_NAME, FRAME, panel_content(ctx, "Complete frame", "corners, borders, center", bg = th.color.surface)),
            skald.nine_slice_background(ctx, ATLAS_NAME, ASYMMETRIC_FRAME, panel_content(ctx, "Asymmetric frame", "independent source regions", bg = th.color.surface)),
            skald.nine_slice_background(ctx, ATLAS_NAME, OPEN_FRAME, panel_content(ctx, "Open frame", "optional bottom and center", bg = th.color.surface)),
            spacing = th.spacing.lg,
        ),
        spacing = th.spacing.lg,
        padding = th.spacing.xl,
    )
}

main :: proc() {
    k2.init(1280, 720, "Skald Karl2D Backgrounds", options = {window_mode = .Windowed_Resizable})
    defer k2.shutdown()

    app := skald.App(State, Msg) {
        title = "Skald Karl2D Backgrounds",
        size = {1280, 720},
        theme = skald.theme_dark(),
        init = init,
        update = update,
        view = view,
    }

    ui: skald_k2.Context(State, Msg)
    if !skald_k2.init(&ui, app) {return}
    defer skald_k2.shutdown(&ui)

    for k2.update() {
        k2.clear(k2.DARK_BLUE)
        skald_k2.frame(&ui)
        k2.present()
    }
}
```

Keep the example non-interactive; its purpose is visual verification of
rendering, layout, and `#load` registration.

- [ ] **Step 2: Build the focused example**

Run:

```bash
./build.sh 51_karl2d_backgrounds
```

Expected: PASS and produce `build/51_karl2d_backgrounds`.

- [ ] **Step 3: Update documentation**

In `docs/examples.md`, add under `Embedding`:

```markdown
| `51_karl2d_backgrounds` | Karl2D-only container decoration: fitted single-image backgrounds, explicit nine-slice atlas regions, asymmetric and open-sided frames, optional center tiles, and `#load`-embedded encoded image bytes. |
```

In `docs/widgets.md`, add a `Karl2D container image backgrounds` subsection
after the existing `image` subsection. Include the three signatures:

```odin
image_background(ctx, path, child, fit = .None, tint = {1, 1, 1, 1})
nine_slice_background(ctx, path, slice: Nine_Slice, child, tint = {1, 1, 1, 1})
image_load_bytes(ctx, name, bytes) -> bool
image_size(ctx, path) -> ([2]f32, bool)
```

Add this text after the signatures:

```markdown
These wrappers and the encoded-byte helper are implemented for Karl2D only in
this milestone. The native SDL/Vulkan backend does not yet wire the optional
encoded-byte, size, or source-region services.

`path` accepts disk paths and registered synthetic names. Use
`image_load_bytes` to register encoded bytes, including bytes embedded with
`#load`, under a synthetic name. `image_load_pixels` remains the existing
raw-RGBA desktop registration API.

`Nine_Slice` rectangles are optional source-image pixel regions. Corners keep
their native dimensions. Borders and the optional center tile repeat at native
pixel scale, with a clipped final tile when needed. The child renders in the
conservative interior, so its existing `bg` fills the center without covering
the decorative chrome.
```

In `docs/architecture.md`, replace the single image-cache sentence with:

```markdown
Images are uploaded lazily on first reference and cached by path. The backend
service also has optional hooks for encoded byte registration, native-size
queries, and source-region draws. The Karl2D adapter implements those optional
hooks for `#load` assets and container background wrappers; the SDL/Vulkan
compatibility backend intentionally leaves them unset for now.
```

In `CHANGELOG.md`, add under `Unreleased`:

```markdown
### Added

- **Karl2D container image backgrounds.** Added `image_background` and
  `nine_slice_background` wrappers for layout containers, explicit optional
  atlas regions for asymmetric or open-sided chrome, native-scale tiling with
  clipped final tiles, and `image_load_bytes` / `image_size` helpers for
  `#load`-embedded assets. Concrete backend support is currently Karl2D-only;
  SDL/Vulkan support remains deferred.
```

- [ ] **Step 4: Run documentation example checks**

Run:

```bash
./build.sh 51_karl2d_backgrounds
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add examples/51_karl2d_backgrounds/main.odin docs/examples.md docs/widgets.md docs/architecture.md CHANGELOG.md
git commit -m "docs: demonstrate Karl2D container image backgrounds"
```

## Task 6: Final Verification

**Files:**
- Verify only

- [ ] **Step 1: Run the core backend-neutral test suite**

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
```

Expected: PASS.

- [ ] **Step 2: Check the Karl2D adapter as a library**

```bash
odin check ./skald_karl2d -collection:gui=. -no-entry-point
```

Expected: PASS.

- [ ] **Step 3: Build existing desktop examples for regression coverage**

```bash
./build.sh 01_hello
./build.sh 20_image
```

Expected: PASS. These are compile checks only. Do not claim the new wrappers
work through SDL/Vulkan.

- [ ] **Step 4: Build Karl2D examples**

```bash
./build.sh 50_karl2d_overlay
./build.sh 51_karl2d_backgrounds
```

Expected: PASS.

- [ ] **Step 5: Run a bounded Karl2D launch smoke test**

```bash
timeout 3s ./build/51_karl2d_backgrounds
```

Expected: the app initializes and stays alive until `timeout` exits with
status `124`. Record whether a desktop session was available. A human visual
pass should confirm native-pixel tiling, clipped partial tiles, open sides,
and child backgrounds staying inside frame chrome.

- [ ] **Step 6: Inspect final diff**

```bash
git status --short
git log --oneline --max-count=8
git diff HEAD~5..HEAD --stat
```

Expected: only the scoped core contracts, Karl2D adapter, tests, example, and
documentation changed. No SDL/Vulkan image implementation was added.
