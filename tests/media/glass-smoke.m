// Standalone material/layering check; never attaches to an existing editor.
// xcrun clang -fobjc-arc -fmodules -mmacosx-version-min=11.0 -Wall -Wextra -Werror \
//   tests/media/glass-smoke.m -framework AppKit -framework QuartzCore -o /tmp/glow-glass-smoke
#import "../../src/platform/macos/glass.m"
#include <stdio.h>
#include <stdlib.h>
static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
@interface GlassEditor : NSView
@end
@implementation GlassEditor
- (BOOL)acceptsFirstResponder { return YES; }
@end
// Discovery uses only our own preview container classes, never web/PDF content.
@interface GlowMediaView : NSView
@end
@implementation GlowMediaView
@end
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSApp finishLaunching];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,480)
            styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        GlassEditor *editor = [[GlassEditor alloc] initWithFrame:NSMakeRect(0,0,640,480)];
        window.contentView = editor;
        [window makeFirstResponder:editor];
        NSView *originalParent = editor.superview;
        void *handle = glow_glass_create((__bridge void *)editor, true);
        GlowGlassContext *context = (__bridge GlowGlassContext *)handle;
        Check(context.effect != nil, "native material created");
        Class systemGlass = NSClassFromString(@"NSGlassEffectView");
        if (systemGlass) Check([context.effect isKindOfClass:systemGlass], "actual NSGlassEffectView when runtime class exists");
        Check(window.contentView == editor && editor.superview == originalParent, "winit contentView identity/hierarchy preserved");
        Check(window.firstResponder == editor, "creating background does not steal keyboard/IME focus");
        Check([originalParent.subviews indexOfObject:context.effect] < [originalParent.subviews indexOfObject:editor], "glass is below editor/Metal content");
        Check([context.effect hitTest:NSMakePoint(20,20)] == nil, "glass background passes all mouse input through");
        editor.frame = NSMakeRect(0,0,720,520);
        glow_glass_layout(handle);
        Check(NSEqualRects(context.effect.frame, [editor convertRect:editor.bounds toView:originalParent]), "material tracks resized content geometry");

        GlowMediaView *panel = [[GlowMediaView alloc] initWithFrame:NSMakeRect(10,10,300,200)];
        panel.wantsLayer = YES;
        panel.layer.backgroundColor = NSColor.redColor.CGColor;
        NSButton *button = [NSButton buttonWithTitle:@"Play" target:nil action:nil];
        button.frame = NSMakeRect(20,20,70,30);
        [panel addSubview:button]; [editor addSubview:panel];
        context.lastPanelScan = 0;
        glow_glass_layout(handle);
        GlowGlassPanelState *state = objc_getAssociatedObject(panel, GlowGlassPanelKey);
        Check(state.effect != nil && [panel.subviews indexOfObject:state.effect] == 0, "new native preview gets a single lower material");
        Check(CGColorGetAlpha(panel.layer.backgroundColor) == 0, "preview container background becomes transparent");
        Check([panel hitTest:NSMakePoint(50,45)] == button, "preview controls retain click handling above glass");
        glow_glass_set_enabled(handle, false);
        Check(context.effect == nil && state.effect == nil, "runtime off removes all native material layers");
        Check(CGColorEqualToColor(panel.layer.backgroundColor, NSColor.redColor.CGColor), "runtime off restores original preview background");
        Check(window.contentView == editor && window.firstResponder == editor, "off preserves editor input identity");
        glow_glass_set_enabled(handle, true);
        Check(context.effect != nil, "runtime on recreates material cleanly");
        NSView *fallback = GlowGlassMakeEffect(12, YES);
        Check([fallback isKindOfClass:NSVisualEffectView.class], "legacy vibrancy fallback can be constructed");
        Check([fallback hitTest:NSMakePoint(0,0)] == nil, "legacy fallback never intercepts input");
        glow_glass_set_enabled(handle, false);
        glow_glass_destroy(handle);
        Check(window.contentView == editor, "destroy never replaces/removes editor contentView");
        [window close];
        puts("PASS: actual native Glass; preserved contentView/focus; sibling z-order; input passthrough; resize; preview discovery; runtime on/off/background restore; legacy fallback construction");
    }
    return 0;
}
