# Skald Image Region Design

## Summary

Add an optional source rectangle to `skald.image`. The default remains the
whole image. When a source rectangle is supplied, the selected region behaves
like a virtual image: the existing `Image_Fit` modes operate on the region's
dimensions and never sample outside it.

Explicit image regions are supported by the Karl2D backend only. Existing
whole-image calls continue to work unchanged on all current backends.

## Motivation

Applications using spritesheets and image atlases need to draw one region of
an image through the ordinary layout widget. Karl2D already exposes
source-region rendering for nine-slice backgrounds, but `skald.image` cannot
currently use that capability.

## API

Extend `image` with a trailing optional `src` argument:

```odin
image :: proc(
    ctx:    ^Ctx($Msg),
    path:   string,
    width:  f32       = 0,
    height: f32       = 0,
    fit:    Image_Fit = .Cover,
    tint:   Color     = {1, 1, 1, 1},
    src:    Rect      = {},
) -> View
```

`Rect{}` means "use the whole image." Keeping `src` trailing preserves all
existing call sites.

Store `src` on `View_Image`.

## Fit Semantics

For a non-empty source rectangle, treat the selected region as a virtual image.
For example, `src = Rect{32, 16, 64, 48}` behaves like a `64 x 48` image:

- `.Fill` stretches the region to the destination slot.
- `.None` draws the region at `64 x 48`, centered in the slot.
- `.Contain` preserves the region's aspect ratio and letterboxes as needed.
- `.Cover` preserves the region's aspect ratio, fills the slot, and crops
  within the selected region.

No fit mode may sample outside the caller-provided source rectangle.

The existing `width` and `height` arguments continue to control the layout
slot. This feature does not change natural-size inference behavior.

## Rendering

The existing `View_Image` render branch continues to load the image handle and
compute the destination slot.

When `src` is empty, render through `draw_image_fit_ctx` exactly as today.

When `src` is non-empty:

1. Query the loaded image size with `image_size_ctx`.
2. Validate the source rectangle.
3. Compute fit-adjusted source and destination rectangles in core Skald.
4. Draw through the existing optional `draw_image_region_ctx` helper.

Core Skald should add a small helper that applies `Image_Fit` to an initial
source rectangle. This avoids adding another backend callback and keeps fit
semantics consistent with the ordinary image widget.

Karl2D already implements `Backend_Images.draw_region`, so no new Karl2D
primitive is required.

## Validation And Failure Behavior

`Rect{}` is the only whole-image sentinel.

Reject an explicit source rectangle when:

- either dimension is non-positive;
- either coordinate is negative;
- its bounds extend outside the loaded image.

If validation fails, image-size lookup fails, or the backend does not implement
`draw_region`, draw the existing magenta placeholder in the widget slot.

This makes the Karl2D-only capability boundary visible without breaking
whole-image rendering on other backends.

## Backend Scope

This change targets Karl2D explicit-region rendering only.

Do not add SDL/Vulkan `size` or `draw_region` callbacks in this work. Existing
SDL/Vulkan calls that omit `src` keep using the established whole-image path.
SDL/Vulkan calls with explicit `src` draw the unsupported-operation
placeholder.

## Testing

Add focused fake-backend tests for:

- existing whole-image `View_Image` dispatch remaining unchanged;
- `.Fill` region dispatch;
- `.None` using the selected region's native dimensions;
- `.Contain` preserving the selected region's aspect ratio;
- `.Cover` cropping within the selected region;
- invalid and out-of-bounds source rectangles drawing a placeholder;
- an explicit region request without `draw_region` support drawing a
  placeholder.

Update the image widget documentation to describe `src` and mark explicit
source-region support as Karl2D-only.
