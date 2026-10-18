#ifndef NEOVIDE_GLOW_MEDIA_H
#define NEOVIDE_GLOW_MEDIA_H

#include <stdbool.h>
#include <stddef.h>

// All calls must run on the AppKit main thread. The parent is a borrowed NSView*.
// A context is initially hidden; frame() positions it in parent points, measured
// from the parent's top-left, and reveals it. The caller owns the returned context.
void *glow_media_create(void *parent_nsview, const char *path, bool video);
void glow_media_frame(void *ctx, double x, double y, double width, double height);
// Preview-local top-left point rectangles, four doubles per rectangle.
void glow_media_occlusion(void *ctx, const double *rects, size_t count);
// play, pause, toggle, seek (absolute seconds), volume (0..1), focus, or blur.
void glow_media_command(void *ctx, const char *action, double value);
// UTF-8 JSON allocated with malloc. The caller must free() it. Never waits for I/O.
const char *glow_media_status(void *ctx);
void glow_media_destroy(void *ctx);

#ifdef __OBJC__
#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>

// The rectangles use preview-local coordinates measured from its top-left.
// The same geometry drives both the native layer mask and AppKit hit testing.
static inline NSArray<NSValue *> *GlowPreviewOcclusionRects(
    NSView *view, const double *rects, size_t count) {
    NSMutableArray<NSValue *> *regions = [NSMutableArray array];
    for (size_t index = 0; rects && index < count; index++) {
        const double *r = rects + index * 4;
        if (!isfinite(r[0]) || !isfinite(r[1]) || !isfinite(r[2]) || !isfinite(r[3])
            || r[2] <= 0 || r[3] <= 0) continue;
        NSRect rect = NSIntersectionRect(view.bounds, NSMakeRect(r[0], r[1], r[2], r[3]));
        if (!NSIsEmptyRect(rect)) [regions addObject:[NSValue valueWithRect:rect]];
    }
    return regions;
}

static inline BOOL GlowPreviewOccludesPoint(NSView *view, NSArray<NSValue *> *regions, NSPoint point) {
    NSPoint local = [view convertPoint:point fromView:view.superview];
    for (NSValue *region in regions) {
        if (NSPointInRect(local, region.rectValue)) return YES;
    }
    return NO;
}

static inline void GlowPreviewApplyOcclusion(NSView *view, NSArray<NSValue *> *regions) {
    view.wantsLayer = YES;
    if (regions.count == 0) {
        view.layer.mask = nil;
        return;
    }
    // Subtract each hole from disjoint visible rectangles. An even-odd path of
    // overlapping holes would accidentally reveal native content at their overlap.
    NSMutableArray<NSValue *> *visible = [NSMutableArray arrayWithObject:[NSValue valueWithRect:view.bounds]];
    for (NSValue *region in regions) {
        NSMutableArray<NSValue *> *next = [NSMutableArray array];
        NSRect hole = region.rectValue;
        for (NSValue *piece in visible) {
            NSRect rect = piece.rectValue;
            NSRect cut = NSIntersectionRect(rect, hole);
            if (NSIsEmptyRect(cut)) { [next addObject:piece]; continue; }
            NSRect parts[] = {
                NSMakeRect(NSMinX(rect), NSMinY(rect), rect.size.width, NSMinY(cut) - NSMinY(rect)),
                NSMakeRect(NSMinX(rect), NSMaxY(cut), rect.size.width, NSMaxY(rect) - NSMaxY(cut)),
                NSMakeRect(NSMinX(rect), NSMinY(cut), NSMinX(cut) - NSMinX(rect), cut.size.height),
                NSMakeRect(NSMaxX(cut), NSMinY(cut), NSMaxX(rect) - NSMaxX(cut), cut.size.height),
            };
            for (size_t index = 0; index < 4; index++) {
                if (!NSIsEmptyRect(parts[index])) [next addObject:[NSValue valueWithRect:parts[index]]];
            }
        }
        visible = next;
    }
    CGMutablePathRef path = CGPathCreateMutable();
    for (NSValue *piece in visible) CGPathAddRect(path, NULL, NSRectToCGRect(piece.rectValue));
    CAShapeLayer *mask = [CAShapeLayer layer];
    mask.frame = view.bounds;
    mask.path = path;
    mask.fillColor = NSColor.blackColor.CGColor;
    // The mask inherits the backing layer coordinate system; flipping the mask
    // again would mirror its holes vertically in a flipped AppKit view.
    view.layer.mask = mask;
    CGPathRelease(path);
}
#endif

#endif
