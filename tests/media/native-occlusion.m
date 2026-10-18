// Native preview stacking check, isolated from all Neovim sessions.
// xcrun clang -fobjc-arc -fmodules -mmacosx-version-min=11.0 -Wall -Wextra -Werror \
//   tests/media/native-occlusion.m -framework AppKit -framework WebKit -framework AVKit \
//   -framework AVFoundation -framework CoreMedia -framework QuartzCore -o /tmp/glow-native-occlusion
#import "../../src/native_preview/media.m"
#import "../../src/native_preview/web.m"

static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

@interface OcclusionParent : NSView
@property(nonatomic) BOOL useFlippedCoordinates;
@end
@implementation OcclusionParent
- (BOOL)isFlipped { return self.useFlippedCoordinates; }
@end

// Composite the actual native layers. Using only the path's contains-point test
// would miss layer coordinate/masking errors that still paint over editor floats.
static BOOL LayerShowsParent(NSView *parent, NSPoint localPoint) {
    const size_t width = 640, height = 480;
    unsigned char *pixels = calloc(width * height, 4);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, width * 4, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    [parent layoutSubtreeIfNeeded];
    [parent displayIfNeeded];
    [CATransaction flush];
    [parent.layer renderInContext:context];
    // CALayer renderInContext writes bitmap rows opposite to the root layer's local Y axis.
    size_t x = (size_t)localPoint.x;
    size_t y = (size_t)(height - localPoint.y);
    const unsigned char *pixel = pixels + (y * width + x) * 4;
    BOOL green = pixel[1] > 200 && pixel[0] < 40;
    CGContextRelease(context); CGColorSpaceRelease(space); free(pixels);
    return green;
}

static void CheckView(NSView *view, NSView *parent, void (^occlude)(const double *, size_t)) {
    const double rectangles[] = {40, 20, 130, 70, 110, 45, 110, 110};
    occlude(rectangles, 2);
    Check(view.layer.mask != nil, "intersecting floats install a native mask");
    NSPoint hole = [view convertPoint:NSMakePoint(50, 30) toView:parent];
    NSPoint overlap = [view convertPoint:NSMakePoint(125, 60) toView:parent];
    NSPoint untouched = [view convertPoint:NSMakePoint(10, 10) toView:parent];
    Check([view hitTest:hole] == nil, "float hit passes through native preview");
    Check([view hitTest:overlap] == nil, "overlapping floats both remain excluded");
    Check([view hitTest:untouched] != nil, "uncovered preview still receives mouse input");
    CAShapeLayer *mask = (CAShapeLayer *)view.layer.mask;
    Check(!CGPathContainsPoint(mask.path, NULL, CGPointMake(50, 30), NO), "first float visual hole");
    Check(!CGPathContainsPoint(mask.path, NULL, CGPointMake(125, 60), NO), "overlap does not reopen the mask");
    Check(CGPathContainsPoint(mask.path, NULL, CGPointMake(10, 10), NO), "uncovered visual content retained");
    Check(!LayerShowsParent(parent, untouched), "uncovered native layer actually composites above editor");
    Check(LayerShowsParent(parent, hole), "native compositing exposes editor layer at float");
    Check(LayerShowsParent(parent, overlap), "native compositing exposes editor at overlapping floats");
    const double offscreen[] = {-30, -20, 70, 45, 10000, 10000, 50, 50};
    occlude(offscreen, 2);
    NSPoint edge = [view convertPoint:NSMakePoint(10, 10) toView:parent];
    Check([view hitTest:edge] == nil, "partially offscreen float clips at native viewport edge");
    occlude(NULL, 0);
    Check(view.layer.mask == nil && [view hitTest:hole] != nil, "closing floats restores visuals and mouse input");
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSApp finishLaunching];
        for (NSNumber *flipped in @[@NO, @YES]) {
            NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 480)
                styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
            window.releasedWhenClosed = NO;
            OcclusionParent *parent = [[OcclusionParent alloc] initWithFrame:NSMakeRect(0, 0, 640, 480)];
            parent.useFlippedCoordinates = flipped.boolValue;
            window.contentView = parent;
            [window orderBack:nil];
            parent.wantsLayer = YES;
            parent.layer.backgroundColor = NSColor.greenColor.CGColor;
            void *media = glow_media_create((__bridge void *)parent, "invalid", false);
            glow_media_frame(media, 75, 65, 300, 240);
            GlowMediaContext *controller = (__bridge GlowMediaContext *)media;
            controller.view.layer.backgroundColor = NSColor.redColor.CGColor;
            CheckView(controller.view, parent, ^(const double *rects, size_t count) {
                glow_media_occlusion(media, rects, count);
            });
            glow_media_destroy(media);
            Check(parent.subviews.count == 0, "media close releases masked child view");
            void *web = glow_web_create((__bridge void *)parent, "invalid:");
            glow_web_frame(web, 75, 65, 300, 240);
            GlowWebPreview *preview = (__bridge GlowWebPreview *)web;
            preview.view.wantsLayer = YES;
            preview.view.layer.backgroundColor = NSColor.redColor.CGColor;
            CheckView(preview.view, parent, ^(const double *rects, size_t count) {
                glow_web_occlusion(web, rects, count);
            });
            glow_web_destroy(web);
            Check(parent.subviews.count == 0, "web close releases masked child view");
            [window close];
        }
        puts("PASS: media and WebKit layer occlusion, overlapping/offscreen floats, hit testing, close, flipped/unflipped parents");
    }
    return 0;
}
