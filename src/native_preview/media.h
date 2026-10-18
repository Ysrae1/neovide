#ifndef NEOVIDE_GLOW_MEDIA_H
#define NEOVIDE_GLOW_MEDIA_H

#include <stdbool.h>

// All calls must run on the AppKit main thread. The parent is a borrowed NSView*.
// A context is initially hidden; frame() positions it in parent points, measured
// from the parent's top-left, and reveals it. The caller owns the returned context.
void *glow_media_create(void *parent_nsview, const char *path, bool video);
void glow_media_frame(void *ctx, double x, double y, double width, double height);
// play, pause, toggle, seek (absolute seconds), volume (0..1), focus, or blur.
void glow_media_command(void *ctx, const char *action, double value);
// UTF-8 JSON allocated with malloc. The caller must free() it. Never waits for I/O.
const char *glow_media_status(void *ctx);
void glow_media_destroy(void *ctx);

#endif
