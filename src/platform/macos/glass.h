#ifndef GLOW_NATIVE_GLASS_H
#define GLOW_NATIVE_GLASS_H
#include <stdbool.h>
// Main-thread, borrowed NSView. The existing winit content view is never replaced.
void *glow_glass_create(void *editor_view, bool enabled);
void glow_glass_set_enabled(void *handle, bool enabled);
void glow_glass_layout(void *handle);
void glow_glass_destroy(void *handle);
// A native panel keeps all content and input above a non-interactive material.
void glow_glass_panel(void *panel_view, bool enabled, double corner_radius);
// Transparent child of a panel; shares its single material instead of nesting it.
void glow_glass_surface(void *child_view, bool enabled);
#endif
