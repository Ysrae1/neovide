// xcrun clang -fobjc-arc -fmodules -mmacosx-version-min=11.0 -Wall -Wextra -Werror \
//   tests/media/synctex-native.m -framework AppKit -framework PDFKit -framework QuartzCore -o /tmp/glow-synctex-native
// /tmp/glow-synctex-native '/tmp/neovide-glow-synctex-check/build/main document.pdf'
#import "../../src/native_preview/pdf.m"

static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static BOOL Wait(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    return condition();
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, "pass real SyncTeX PDF fixture");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSApp finishLaunching];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,900,760)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed=NO;
        NSView *parent=[[NSView alloc] initWithFrame:NSMakeRect(0,0,900,760)]; window.contentView=parent;
        void *handle=glow_pdf_create((__bridge void *)parent,argv[1]);
        GlowPDFContext *context=(__bridge GlowPDFContext *)handle;
        glow_pdf_frame(handle,0,0,900,760);
        glow_pdf_sync(handle,1,133.768356,148.656967,343.711060,8.855677);
        Check(Wait(^BOOL { return [context.state isEqualToString:@"ready"]; }),"asynchronous PDF loads");
        Check(context.syncAnnotation != nil,"forward before load retains point and highlight");
        PDFPage *page=[context.pdfView.document pageAtIndex:0];
        Check([context.pdfView.document indexForPage:context.pdfView.currentPage]==0,"forward selects page 1");
        NSPoint sync=NSMakePoint(165.870209,146.719788);
        NSPoint pdf=GlowPDFPointFromSync(page,sync.x,sync.y);
        for (NSNumber *rotation in @[@0,@90,@180,@270]) {
            page.rotation=rotation.integerValue;
            [page setBounds:NSInsetRect([page boundsForBox:kPDFDisplayBoxMediaBox],12,16) forBox:kPDFDisplayBoxCropBox];
            [context.pdfView layoutDocumentView];
            NSPoint view=[context.pdfView convertPoint:pdf fromPage:page];
            NSPoint back=GlowPDFPointToSync(page,[context.pdfView convertPoint:view toPage:page]);
            Check(hypot(back.x-sync.x,back.y-sync.y)<.001,"CropBox/rotation preserves SyncTeX MediaBox coordinates");
        }
        page.rotation=0; [context.pdfView layoutDocumentView];
        NSPoint view=[context.pdfView convertPoint:pdf fromPage:page];
        [context inverseAtPoint:view];
        Check([context.inverseSync[@"page"] intValue]==1 && fabs([context.inverseSync[@"x"] doubleValue]-sync.x)<.001
            && fabs([context.inverseSync[@"y"] doubleValue]-sync.y)<.001,"PDFKit point produces real inverse coordinates");
        context.inverseSync=nil;
        NSPoint windowPoint=[context.pdfView convertPoint:view toView:nil];
        NSView *target=[window.contentView hitTest:[window.contentView convertPoint:windowPoint fromView:nil]];
        fprintf(stderr,"Command-click dispatch target: %s\n",NSStringFromClass(target.class).UTF8String);
        NSEvent *click=[NSEvent mouseEventWithType:NSEventTypeLeftMouseDown location:windowPoint
            modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:window.windowNumber context:nil
            eventNumber:1 clickCount:1 pressure:1];
        // PDFKit's selection tracker can wait for a release when a child view
        // receives mouseDown. Supply one just as a real event stream does.
        NSEvent *up=[NSEvent mouseEventWithType:NSEventTypeLeftMouseUp location:windowPoint
            modifierFlags:NSEventModifierFlagCommand timestamp:.01 windowNumber:window.windowNumber context:nil
            eventNumber:2 clickCount:1 pressure:0];
        [NSApp postEvent:up atStart:NO];
        [NSApp sendEvent:click];
        Check(context.inverseSync!=nil,"Command-click reaches inverse handler through actual PDFKit child view");
        glow_pdf_destroy(handle); context=nil;
        Check(parent.subviews.count==0,"close removes native view");
        [window close];
        puts("PASS: async pending forward; native page/highlight; PDFKit MediaBox/CropBox/rotation; actual Command-click inverse; close");
    }
    return 0;
}
