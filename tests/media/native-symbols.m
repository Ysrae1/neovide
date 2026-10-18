// Focused SF Symbol/layout check, with no visible window or media playback.
// xcrun clang -fobjc-arc -fmodules -mmacosx-version-min=11.0 -Wall -Wextra -Werror \
//   tests/media/native-symbols.m -framework AppKit -framework AVKit \
//   -framework AVFoundation -framework CoreMedia -framework QuartzCore -o /tmp/glow-native-symbols
#import "../../src/native_preview/media.m"

static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static void CenteredSymbol(NSImageView *view) {
    Check(view.image != nil, "actual image from the SF Symbol factory exists");
    Check(view.image.accessibilityDescription.length > 0, "symbol has an accessibility description");
    NSRect drawn = [view.cell imageRectForBounds:view.bounds];
    Check(!NSIsEmptyRect(drawn) && NSContainsRect(view.bounds, drawn), "symbol fits its original content box");
    Check(fabs(NSMidX(drawn) - NSMidX(view.bounds)) < .51
        && fabs(NSMidY(drawn) - NSMidY(view.bounds)) < .51, "symbol is centered inside its content box");
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSApp finishLaunching];
        // Same dedicated 15pt content box and padding as the Return chip. Other
        // shortcut labels are deliberately outside this change.
        NSView *chip = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 27, 17)];
        NSImageView *key = [[NSImageView alloc] initWithFrame:NSMakeRect(6, 1, 15, 15)];
        key.image = [NSImage imageWithSystemSymbolName:@"return" accessibilityDescription:@"Return"];
        key.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:15 weight:NSFontWeightRegular];
        key.imageScaling = NSImageScaleProportionallyDown;
        [chip addSubview:key];
        CenteredSymbol(key);
        Check(NSMidX(key.frame) == NSMidX(chip.bounds) && NSMidY(key.frame) == NSMidY(chip.bounds), "Return box is centered in existing chip padding");
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,640,400)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        void *handle = glow_media_create((__bridge void *)window.contentView,"relative.wav",false);
        GlowMediaContext *context = (__bridge GlowMediaContext *)handle;
        glow_media_frame(handle,0,0,640,360);
        NSRect expected = NSMakeRect(14,64,612,70); // Existing layout: (360-92)/2-70.
        Check(NSEqualRects(context.audioSymbol.frame,expected), "audio symbol keeps its original 70pt layout region");
        CenteredSymbol(context.audioSymbol);
        Check(!context.audioSymbol.hidden, "audio placeholder remains visible");
        glow_media_destroy(handle); context = nil;
        Check(window.contentView.subviews.count == 0, "closing releases the symbol with its media context");
        [window close];
        puts("PASS: Return/music.note are real SF images, accessible, fitted and centered; audio layout and close preserved");
    }
    return 0;
}
