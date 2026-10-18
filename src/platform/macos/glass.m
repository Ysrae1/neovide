#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include "glass.h"

// Resolve the public class dynamically. A static subclass of an unavailable
// superclass can fail during Objective-C image loading on older macOS, before
// a runtime availability branch gets a chance to select the fallback.
@protocol GlowGlassProperties
@property(nonatomic, strong) NSView *contentView;
@property(nonatomic) CGFloat cornerRadius;
@property(nonatomic) NSInteger style;
@end

static id GlowGlassPassThrough(id view, SEL selector, NSPoint point) {
    (void)view; (void)selector; (void)point; return nil;
}

static Class GlowLiquidGlassClass(void) {
    Class base = NSClassFromString(@"NSGlassEffectView");
    if (!base) return Nil;
    Class subclass = NSClassFromString(@"GlowLiquidGlassView");
    if (subclass) return subclass;
    subclass = objc_allocateClassPair(base, "GlowLiquidGlassView", 0);
    if (!subclass) return Nil;
    Method hitTest = class_getInstanceMethod(NSView.class, @selector(hitTest:));
    if (!class_addMethod(subclass, @selector(hitTest:), (IMP)GlowGlassPassThrough,
        method_getTypeEncoding(hitTest))) {
        objc_disposeClassPair(subclass); return Nil;
    }
    objc_registerClassPair(subclass);
    return subclass;
}

@interface GlowVibrancyView : NSVisualEffectView
@end
@implementation GlowVibrancyView
- (NSView *)hitTest:(NSPoint)point { (void)point; return nil; }
@end

// forceFallback is exercised by the native smoke on new macOS as well, so the
// older-system path is compiled and checked without claiming a legacy OS run.
static NSView *GlowGlassMakeEffect(CGFloat radius, BOOL forceFallback) {
    Class glassClass = forceFallback ? Nil : GlowLiquidGlassClass();
    if (glassClass) {
        NSView<GlowGlassProperties> *glass = [[glassClass alloc] initWithFrame:NSZeroRect];
        // NSGlassEffectViewStyleRegular is the public style value zero.
        // Protocol messages avoid a link-time reference to the newer class or
        // compiler_rt availability helper under Rust's -nodefaultlibs link.
        glass.style = 0;
        glass.cornerRadius = radius;
        glass.contentView = [[NSView alloc] initWithFrame:NSZeroRect];
        return glass;
    }
    GlowVibrancyView *material = [[GlowVibrancyView alloc] initWithFrame:NSZeroRect];
    material.material = NSVisualEffectMaterialUnderWindowBackground;
    material.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    material.state = NSVisualEffectStateFollowsWindowActiveState;
    material.wantsLayer = YES;
    material.layer.cornerRadius = radius;
    material.layer.masksToBounds = radius > 0;
    return material;
}

@interface GlowGlassPanelState : NSObject
@property(nonatomic, strong) NSView *effect;
@property(nonatomic, strong) NSColor *originalColor;
@property(nonatomic) BOOL captured;
@property(nonatomic) BOOL material;
@property(nonatomic) CGFloat radius;
@property(nonatomic, weak) NSWindow *window;
@property(nonatomic, strong) NSColor *windowColor;
@property(nonatomic) BOOL windowOpaque;
@end
@implementation GlowGlassPanelState
@end

static const void *GlowGlassPanelKey = &GlowGlassPanelKey;
static NSHashTable<NSView *> *GlowGlassPanels;

static void GlowGlassPanelApply(NSView *view, BOOL enabled, CGFloat radius, BOOL material) {
    if (!view) return;
    GlowGlassPanelState *state = objc_getAssociatedObject(view, GlowGlassPanelKey);
    if (!state && !enabled) return;
    if (!state) {
        state = [GlowGlassPanelState new];
        objc_setAssociatedObject(view, GlowGlassPanelKey, state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        state.material = material;
        state.radius = radius;
        if (material && view.window.contentView == view) {
            state.window = view.window; state.windowColor = view.window.backgroundColor;
            state.windowOpaque = view.window.opaque;
        }
        if (!GlowGlassPanels) GlowGlassPanels = [NSHashTable weakObjectsHashTable];
        [GlowGlassPanels addObject:view];
    }
    if (!state.captured) {
        state.captured = YES;
        CGColorRef color = view.layer.backgroundColor;
        state.originalColor = color ? [NSColor colorWithCGColor:color] : nil;
    }
    if (enabled) {
        if (state.material && !state.effect) {
            state.effect = GlowGlassMakeEffect(radius, NO);
            state.effect.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
            [view addSubview:state.effect positioned:NSWindowBelow relativeTo:nil];
        }
        state.effect.frame = view.bounds;
        view.wantsLayer = YES;
        view.layer.backgroundColor = NSColor.clearColor.CGColor;
        if (state.window) { state.window.opaque = NO; state.window.backgroundColor = NSColor.clearColor; }
    } else {
        [state.effect removeFromSuperview];
        state.effect = nil;
        view.layer.backgroundColor = state.originalColor.CGColor;
        if (state.window) { state.window.opaque = state.windowOpaque; state.window.backgroundColor = state.windowColor; }
    }
}

@interface GlowGlassContext : NSObject
@property(nonatomic, weak) NSView *editor;
@property(nonatomic, strong) NSView *effect;
@property(nonatomic) BOOL enabled;
@property(nonatomic) NSTimeInterval lastPanelScan;
- (void)layout;
- (void)setMaterialEnabled:(BOOL)enabled;
@end
@implementation GlowGlassContext
- (void)setMaterialEnabled:(BOOL)enabled {
    self.enabled = enabled;
    if (!enabled) {
        [self.effect removeFromSuperview];
        self.effect = nil;
    }
    for (NSView *panel in GlowGlassPanels.allObjects) {
        GlowGlassPanelState *state = objc_getAssociatedObject(panel, GlowGlassPanelKey);
        GlowGlassPanelApply(panel, enabled, state.radius, state.material);
    }
    self.lastPanelScan = 0;
    [self layout];
}
- (void)layout {
    NSView *editor = self.editor;
    NSView *parent = editor.superview;
    if (!self.enabled || !editor || !parent) return;
    if (!self.effect) self.effect = GlowGlassMakeEffect(0, NO);
    // Sibling insertion keeps winit's contentView identity, first responder,
    // CAMetalLayer and the entire native preview hierarchy intact.
    if (self.effect.superview != parent) {
        [self.effect removeFromSuperview];
        [parent addSubview:self.effect positioned:NSWindowBelow relativeTo:editor];
    }
    self.effect.frame = [editor convertRect:editor.bounds toView:parent];
    self.effect.hidden = editor.hidden;
    NSTimeInterval now = NSDate.timeIntervalSinceReferenceDate;
    if (now - self.lastPanelScan < 0.15) return;
    self.lastPanelScan = now;
    // Only our own preview containers become transparent. PDF pages, video and
    // web document content retain their own readable, unmodified backgrounds.
    for (NSView *child in editor.subviews.copy) {
        NSString *name = NSStringFromClass(child.class);
        if ([name isEqualToString:@"GlowMediaView"] || [name isEqualToString:@"GlowPDFContainer"]) {
            GlowGlassPanelApply(child, YES, 12, YES);
        }
    }
}
@end

void *glow_glass_create(void *editor_view, bool enabled) {
    if (!editor_view || !NSThread.isMainThread) return NULL;
    @autoreleasepool {
        GlowGlassContext *context = [GlowGlassContext new];
        context.editor = (__bridge NSView *)editor_view;
        [context setMaterialEnabled:enabled];
        return (__bridge_retained void *)context;
    }
}
void glow_glass_set_enabled(void *handle, bool enabled) {
    if (!handle || !NSThread.isMainThread) return;
    @autoreleasepool { [(__bridge GlowGlassContext *)handle setMaterialEnabled:enabled]; }
}
void glow_glass_layout(void *handle) {
    if (!handle || !NSThread.isMainThread) return;
    @autoreleasepool { [(__bridge GlowGlassContext *)handle layout]; }
}
void glow_glass_destroy(void *handle) {
    if (!handle || !NSThread.isMainThread) return;
    @autoreleasepool {
        GlowGlassContext *context = (__bridge_transfer GlowGlassContext *)handle;
        [context.effect removeFromSuperview];
        context.effect = nil;
        context.editor = nil;
    }
}
void glow_glass_panel(void *panel_view, bool enabled, double corner_radius) {
    if (!panel_view || !NSThread.isMainThread) return;
    @autoreleasepool { GlowGlassPanelApply((__bridge NSView *)panel_view, enabled, corner_radius, YES); }
}

void glow_glass_surface(void *child_view, bool enabled) {
    if (!child_view || !NSThread.isMainThread) return;
    @autoreleasepool { GlowGlassPanelApply((__bridge NSView *)child_view, enabled, 0, NO); }
}
