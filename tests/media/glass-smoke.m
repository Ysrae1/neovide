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
// These preview containers must keep their ordinary Neovide-style surfaces.
@interface GlowMediaView : NSView
@end
@implementation GlowMediaView
@end
@interface GlowPDFContainer : NSView
@end
@implementation GlowPDFContainer
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
        GlowPDFContainer *pdf = [[GlowPDFContainer alloc] initWithFrame:NSMakeRect(320,10,300,200)];
        pdf.wantsLayer = YES;
        pdf.layer.backgroundColor = NSColor.blueColor.CGColor;
        [editor addSubview:pdf];
        glow_glass_layout(handle);
        Check(objc_getAssociatedObject(panel, GlowGlassPanelKey) == nil
            && objc_getAssociatedObject(pdf, GlowGlassPanelKey) == nil, "media/PDF previews never receive independent material");
        Check(panel.subviews.count == 1 && pdf.subviews.count == 0, "no extra preview children are installed");
        Check(CGColorEqualToColor(panel.layer.backgroundColor, NSColor.redColor.CGColor)
            && CGColorEqualToColor(pdf.layer.backgroundColor, NSColor.blueColor.CGColor), "preview backgrounds remain unchanged");
        Check([panel hitTest:NSMakePoint(50,45)] == button, "preview controls retain click handling");
        // Switcher uses the explicit panel API; removing preview discovery must
        // leave its existing material and background restoration intact.
        NSView *switcher = [[NSView alloc] initWithFrame:NSMakeRect(10,230,300,200)];
        switcher.wantsLayer = YES;
        switcher.layer.backgroundColor = NSColor.grayColor.CGColor;
        [editor addSubview:switcher];
        glow_glass_panel((__bridge void *)switcher,true,12);
        GlowGlassPanelState *state = objc_getAssociatedObject(switcher, GlowGlassPanelKey);
        Check(state.effect != nil && switcher.subviews.count == 1, "explicit Switcher material is preserved");
        glow_glass_set_enabled(handle, false);
        Check(context.effect == nil && state.effect == nil, "runtime off removes all native material layers");
        Check(CGColorEqualToColor(switcher.layer.backgroundColor, NSColor.grayColor.CGColor), "runtime off restores explicit panel background");
        Check(CGColorEqualToColor(panel.layer.backgroundColor, NSColor.redColor.CGColor)
            && CGColorEqualToColor(pdf.layer.backgroundColor, NSColor.blueColor.CGColor), "runtime off leaves preview style intact");
        Check(window.contentView == editor && window.firstResponder == editor, "off preserves editor input identity");
        glow_glass_set_enabled(handle, true);
        Check(context.effect != nil && state.effect != nil, "runtime on recreates window and explicit panel material cleanly");
        Check(objc_getAssociatedObject(panel, GlowGlassPanelKey) == nil
            && objc_getAssociatedObject(pdf, GlowGlassPanelKey) == nil, "runtime on does not add preview materials");
        NSView *fallback = GlowGlassMakeEffect(12, YES);
        Check([fallback isKindOfClass:NSVisualEffectView.class], "legacy vibrancy fallback can be constructed");
        Check([fallback hitTest:NSMakePoint(0,0)] == nil, "legacy fallback never intercepts input");
        glow_glass_set_enabled(handle, false);
        glow_glass_destroy(handle);
        Check(window.contentView == editor, "destroy never replaces/removes editor contentView");
        [window close];
        puts("PASS: whole-editor Glass; contentView/focus/z-order/resize; unchanged media/PDF surfaces; preserved explicit Switcher material; runtime on/off; legacy fallback construction");
    }
    return 0;
}
