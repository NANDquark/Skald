# Container Image Backgrounds Design

## Summary

Skald will add two decorative wrapper views:

- `image_background` draws one image behind a child.
- `nine_slice_background` draws scalable tiled decoration behind a child
  from explicit source-image regions.

The wrappers compose with existing layout containers such as `col`, `row`,
`wrap_row`, and `grid`. They do not add image-specific parameters to those
builders and do not change the existing `bg` color property.

This milestone targets the Karl2D backend only. Core Skald contracts and view
nodes will change where needed so `skald_karl2d` can provide the feature, but
implementing equivalent new behavior in Skald's SDL/Vulkan renderer is
explicitly out of scope.

## Motivation

Layout containers currently support a solid background color and optional
corner radius. Applications also need authored UI decoration:

- a fixed or fitted image behind a container;
- a scalable frame whose corners remain pixel-exact;
- tiled borders and optional tiled center artwork;
- asymmetric decorative chrome;
- partial frames with intentionally absent sides or center artwork;
- embedded assets for filesystem-free builds.

A single fitted image is appropriate when native-size clipping or an explicit
fit mode is acceptable. Nine-slice decoration is appropriate when a panel must
grow without distorting authored corners and border patterns.

## Existing Architecture

`View_Stack` and `View_Wrap_Row` paint their `bg` before rendering children.
`grid` composes ordinary view nodes and forwards its background color through
its generated layout.

Skald already has a backend-neutral image pipeline:

- `image(ctx, path, ...)` creates a `View_Image`;
- `Backend_Images.load_path` loads an opaque `Backend_Image`;
- `Backend_Images.draw_fit` draws an opaque image handle using `Image_Fit`;
- the Karl2D adapter stores dimensions on `k2.Texture`;
- Karl2D can draw source and destination rectangles through
  `k2.draw_texture_fit(texture, source, destination)`.

The current backend service does not expose image dimensions, encoded byte
registration, or arbitrary source-region drawing. Those additions are needed
for embedded image assets and nine-slice rendering.

## Scope

### In Scope

- Decorative image wrappers usable around existing layout containers.
- Single-image backgrounds with standard `Image_Fit` behavior.
- Nine-slice backgrounds with explicit optional source rectangles.
- Asymmetric corners, borders, and open-sided frames.
- Optional tiled center image region.
- Existing child-container `bg` colors filling the nine-slice interior.
- Backend-neutral service contract additions required by the wrappers.
- Karl2D implementations of image-size queries, source-region drawing, and
  encoded in-memory image registration.
- Encoded `#load` asset support through Karl2D.
- Backend-neutral fake-backend tests for core layout and dispatch behavior.
- Karl2D compile checks and a visual Karl2D example.

### Explicitly Out Of Scope

- Implementing the new backend callbacks in Skald's SDL/Vulkan renderer.
- Claiming the new wrappers are supported by the SDL/Vulkan runtime.
- Adding image backgrounds directly to buttons or styled widgets.
- Replacing existing container `bg` semantics.
- Parsing atlas metadata files.
- Stretching or round-fitting nine-slice borders.
- New shaders.
- Automatically locking `image_background` to the source image size.

The core service additions must be optional so the existing SDL/Vulkan
compatibility backend continues to compile while its new callbacks remain
unset. When a caller requests unsupported behavior through a backend without
the required callback, Skald should fail visibly without crashing: return
`false` from helper APIs and draw a conspicuous magenta placeholder for an
unsupported background draw.

## API Design

### Single-Image Wrapper

```odin
image_background :: proc(
    ctx:   ^Ctx($Msg),
    path:  string,
    child: View,
    fit:   Image_Fit = .None,
    tint:  Color     = {1, 1, 1, 1},
) -> View
```

`path` follows the existing `image()` convention. It may be a filesystem path
or a synthetic registered name such as `"app://panel"`.

The wrapper does not control layout size. It reports the child's intrinsic
size and accepts the size assigned by its parent. The image paints into that
final rectangle using `fit`:

- `.None`: keep native image pixels centered and clip overflow;
- `.Contain`: preserve aspect ratio and allow transparent gaps;
- `.Cover`: preserve aspect ratio, fill the rectangle, and crop overflow;
- `.Fill`: stretch to the rectangle.

`.None` is the default because authored UI decoration should not be cropped or
distorted unless the caller requests it explicitly.

Applications that intentionally want a fixed container matching the asset can
query `image_size`, then pass those dimensions to the wrapped `col` or `row`:

```odin
size, ok := skald.image_size(ctx, "app://dialog")
if !ok {
    return skald.text("Missing dialog asset", th.color.danger)
}

return skald.image_background(
    ctx,
    "app://dialog",
    skald.col(content, width = size.x, height = size.y),
)
```

### Explicit Nine-Slice Descriptor

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
```

Each rectangle identifies a source-image region in pixel coordinates.
Zero-width or zero-height rectangles are empty and skipped. All nine regions
are optional, including borders and center.

The explicit representation is the core API because it supports:

- conventional contiguous nine-slice images;
- atlas-packed regions;
- asymmetric decorative corners;
- different source dimensions for each edge;
- open-sided frames;
- corner-only decoration;
- omitted center artwork.

An inset-based convenience helper may be added later for conventional assets,
but it is not required for this milestone.

### Nine-Slice Wrapper

```odin
nine_slice_background :: proc(
    ctx:   ^Ctx($Msg),
    path:  string,
    slice: Nine_Slice,
    child: View,
    tint:  Color = {1, 1, 1, 1},
) -> View
```

The wrapper draws decoration first and renders the child only inside the
reserved interior. This allows the child's existing `bg` property to fill the
center without painting over the frame:

```odin
skald.nine_slice_background(
    ctx,
    "app://dialog-frame",
    DIALOG_FRAME,
    skald.col(content, padding = 12, bg = th.color.surface),
)
```

### Image Helpers

```odin
image_size :: proc(
    ctx:  ^Ctx($Msg),
    path: string,
) -> (size: [2]f32, ok: bool)

image_load_bytes :: proc(
    ctx:   ^Ctx($Msg),
    name:  string,
    bytes: []byte,
) -> bool
```

`image_size` loads or retrieves the image through the active backend and
returns its native dimensions. It works for filesystem paths and registered
synthetic names.

`image_load_bytes` registers encoded in-memory image data under a synthetic
name. This supports compile-time embedded assets:

```odin
DIALOG_FRAME_PNG :: #load("assets/dialog-frame.png", []byte)

if !skald.image_load_bytes(ctx, "app://dialog-frame", DIALOG_FRAME_PNG) {
    // Surface an application-appropriate failure.
}
```

The bytes are encoded image data, not raw RGBA pixels. Existing
`image_load_pixels` remains the raw-RGBA registration path.

Both helpers route through `Ctx.render` and `Render_Context`, not
`Ctx.renderer`. Embedded Karl2D views can have no native `Renderer` pointer.

## View Nodes

Add two wrappers to `View`:

```odin
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
```

These follow established patterns such as `View_Clip`, `View_Flex`,
`View_Tooltip`, and `View_Zone`: a wrapper adds behavior while preserving a
child view as the composable layout unit.

## Layout Semantics

### Single Image

`view_size(View_Image_Background)` returns the child's intrinsic size
unchanged. During rendering, the child receives the wrapper's full assigned
rectangle.

### Nine Slice

Nine-slice child insets are conservative decoration extents calculated from
all non-empty regions touching each edge:

```text
left   = max(top_left.w, left.w, bottom_left.w)
right  = max(top_right.w, right.w, bottom_right.w)
top    = max(top_left.h, top.h, top_right.h)
bottom = max(bottom_left.h, bottom.h, bottom_right.h)
```

`view_size(View_Nine_Slice_Background)` returns:

```text
child intrinsic width  + left + right
child intrinsic height + top + bottom
```

The wrapper remains scalable. An explicit parent size, flex allocation, or
cross-axis stretch may assign a larger rectangle.

At render time, the child receives:

```text
x = wrapper.x + left
y = wrapper.y + top
w = wrapper.w - left - right
h = wrapper.h - top - bottom
```

This guarantees that a child container's `bg` fills only the conservative
interior and does not obscure asymmetric decorative chrome.

## Rendering Semantics

### Draw Order

`View_Image_Background`:

1. Clip to the assigned wrapper rectangle.
2. Draw the image with `draw_fit`.
3. Render the child in the same assigned rectangle.
4. Pop the clip.

`View_Nine_Slice_Background`:

1. Clip to the assigned wrapper rectangle.
2. Draw optional corners once at native source-region size, anchored to the
   matching wrapper corners.
3. Tile each optional border independently between its adjacent corner
   extents.
4. Tile the optional center region across the conservative interior.
5. Render the child inside the conservative interior.
6. Pop the clip.

Drawing the center before the child allows the child container's existing
`bg` to cover it intentionally. A caller uses either the image center, the
child's solid background, transparency, or a combination.

### Tiling

Border and center tiling preserve native pixel scale:

- Repeat each source tile from the leading edge.
- If the destination length is not an exact multiple of the tile length,
  clip the final partial tile.
- Shrink both destination and sampled source rectangles for the final partial
  tile.
- Do not rescale all tiles to fit a rounded count.

For a `24 px` top-border tile covering `50 px`, draw widths `24 + 24 + 2`.

Each border uses its own adjacent corner dimensions as start and end offsets.
For example:

```text
top border x range  = wrapper.x + top_left.w
                      through wrapper.x + wrapper.w - top_right.w

left border y range = wrapper.y + top_left.h
                      through wrapper.y + wrapper.h - bottom_left.h
```

The conservative interior calculation is independent of these per-edge tile
ranges.

## Backend Service Extensions

Extend `Backend_Images` with optional callbacks:

```odin
Backend_Images :: struct {
    load_path:     proc(state: rawptr, path: string) -> Backend_Image,
    load_bytes:    proc(state: rawptr, name: string, bytes: []byte) -> Backend_Image,
    load_pixels:   proc(state: rawptr, name: string, w, h: u32, rgba: []u8) -> Backend_Image,
    update_pixels: proc(state: rawptr, image: Backend_Image, w, h: u32, rgba: []u8) -> bool,
    unload:        proc(state: rawptr, image: Backend_Image),
    size:          proc(state: rawptr, image: Backend_Image) -> (size: [2]f32, ok: bool),
    draw:          proc(state: rawptr, image: Backend_Image, rect: Rect, tint: Color),
    draw_fit:      proc(state: rawptr, image: Backend_Image, rect: Rect, fit: Image_Fit, tint: Color) -> bool,
    draw_region:   proc(state: rawptr, image: Backend_Image, src, dst: Rect, tint: Color) -> bool,
}
```

`draw_region` is necessary because `draw_fit` samples the whole image.
Nine-slice rendering must repeatedly sample independently defined subregions
from one texture, including cropped source regions for final partial tiles.

### Karl2D Backend

Implement all three new callbacks in `skald_karl2d`:

- `load_bytes` uses `k2.load_texture_from_bytes`;
- `size` reads `k2.Texture.width` and `k2.Texture.height`;
- `draw_region` uses
  `k2.draw_texture_fit(texture, source, destination, tint = ...)`.

Encoded-byte registration should be idempotent by synthetic name. If a live
entry already exists for `name`, return its handle without decoding and
uploading the same embedded asset again on every view rebuild. Applications
that need to replace an encoded asset can unload it before registering the
new bytes.

### SDL/Vulkan Backend

Do not implement the three new callbacks in the SDL/Vulkan compatibility
backend during this milestone. Leave them unset and document the limitation.
The underlying Vulkan renderer could support equivalent behavior later, but
that follow-up is separate work.

The pre-existing `draw_fit` path may allow `image_background` to work in some
SDL/Vulkan cases incidentally. This milestone does not guarantee, document,
or verify SDL/Vulkan support for either new wrapper.

## Validation And Failure Behavior

Validation must not impose matching dimensions across corners or borders.
Asymmetric decorative chrome is supported intentionally.

Skip an optional source region when either dimension is zero. Reject a
non-empty region when:

- width or height is negative;
- its origin is negative;
- its bounds extend outside the loaded texture;
- a tiled source region has no usable extent on its repeat axis.

When a nine-slice wrapper's assigned destination is smaller than the sum of
opposing conservative decoration extents:

- emit a debug warning;
- clamp the child interior extent to zero;
- keep the wrapper clip active;
- draw only the portions of decoration that fit without rescaling.

Missing or undecodable images continue to use Skald's existing conspicuous
magenta placeholder behavior rather than crashing.

Invalid encoded bytes passed to `image_load_bytes` return `false` and log a
decode failure.

If the active backend does not provide a newly required optional callback:

- `image_load_bytes` and `image_size` return `false`;
- `nine_slice_background` draws a magenta placeholder and still renders its
  child in the computed interior;
- Skald emits a debug warning identifying the unsupported backend image
  operation.

## Testing

Add backend-neutral fake-backend tests for:

- `image_size` dispatch and native dimension return value;
- `image_load_bytes` dispatch;
- `draw_region` dispatch;
- missing optional callback failure behavior;
- `View_Image_Background` intrinsic size passthrough;
- single-image draw order, fit forwarding, tint forwarding, and clipping;
- nine-slice intrinsic size with asymmetric optional regions;
- conservative child-interior placement;
- omitted center region;
- omitted border regions and open-sided frames;
- corner drawing at native size;
- border tiling with a clipped final partial tile;
- center tiling with clipped final row and column tiles;
- undersized destinations;
- missing-image placeholders.

Verification for this milestone:

```bash
odin test ./skald -collection:gui=. -define:SKALD_RUNA=false
odin check ./skald_karl2d -collection:gui=. -no-entry-point
odin build examples/50_karl2d_overlay -collection:gui=. -debug -out:build/50_karl2d_overlay
```

Add or extend a Karl2D image example to visually demonstrate:

- a native-pixel single-image background;
- explicit `.Contain`, `.Cover`, and `.Fill` choices;
- a conventional complete nine-slice frame;
- asymmetric decorative chrome;
- an open-sided frame;
- omitted center tile with child `bg`;
- an image registered from compile-time `#load` bytes.

SDL/Vulkan visual verification is not part of this milestone.

## Documentation

Update the widget reference and Karl2D example documentation to explain:

- the wrappers currently require the Karl2D backend;
- wrappers compose with layout containers;
- paths and synthetic names share the same lookup convention;
- `#load` bytes use `image_load_bytes`;
- `image_load_pixels` remains the API for already decoded RGBA buffers;
- nine-slice rectangles are source-image pixel coordinates;
- zero-sized nine-slice regions are optional;
- borders and center tile without stretching;
- the child container's existing `bg` fills the reserved interior.
