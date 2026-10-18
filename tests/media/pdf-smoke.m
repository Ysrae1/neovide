// Uses the official PDF.js sample as a read-only local fixture; touches no editor.
// curl -fL https://mozilla.github.io/pdf.js/web/compressed.tracemonkey-pldi-09.pdf -o /tmp/glow-pdf-fixture.pdf
// xcrun clang -fobjc-arc -fmodules -mmacosx-version-min=11.0 -Wall -Wextra -Werror \
//   tests/media/pdf-smoke.m -framework AppKit -framework PDFKit -framework QuartzCore -o /tmp/glow-pdf-smoke
// /tmp/glow-pdf-smoke /tmp/glow-pdf-fixture.pdf
#import "../../src/native_preview/pdf.m"

static void PDFCheck(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
static BOOL PDFWait(BOOL (^condition)(void), NSTimeInterval seconds) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    return condition();
}
static NSDictionary *PDFStatus(void *handle) {
    const char *raw = glow_pdf_status(handle);
    NSData *data = [NSData dataWithBytes:raw length:strlen(raw)]; free((void *)raw);
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
}
@interface PDFSmokeParent : NSView
@end
@implementation PDFSmokeParent
- (BOOL)acceptsFirstResponder { return YES; }
@end

int main(int argc, const char **argv) {
    @autoreleasepool {
        PDFCheck(argc == 2, "provide local PDF fixture path");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSApp finishLaunching];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        PDFSmokeParent *parent = [[PDFSmokeParent alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
        window.contentView = parent;
        void *handle = glow_pdf_create((__bridge void *)parent, argv[1]);
        GlowPDFContext *preview = (__bridge GlowPDFContext *)handle;
        PDFCheck(handle != NULL && preview.view.hidden, "PDF starts hidden awaiting split geometry");
        glow_pdf_frame(handle, 40, 30, 430, 520);
        PDFCheck(NSEqualRects(preview.view.frame, NSMakeRect(40, 150, 430, 520)), "top-left viewport conversion");
        PDFCheck(PDFWait(^BOOL { return ![PDFStatus(handle)[@"state"] isEqualToString:@"loading"]; }, 15), "asynchronous PDF load finishes");
        NSDictionary *ready = PDFStatus(handle);
        if (![ready[@"state"] isEqualToString:@"ready"]) fprintf(stderr, "%s\n", ready.description.UTF8String);
        PDFCheck([ready[@"state"] isEqualToString:@"ready"] && [ready[@"pages"] unsignedIntegerValue] > 3, "multipage PDF ready");
        PDFCheck(preview.pdfView.document.string.length > 100, "PDFKit provides selectable document text");
        glow_pdf_command(handle, "page", 3);
        PDFCheck([PDFStatus(handle)[@"page"] integerValue] == 3, "absolute page navigation");
        glow_pdf_command(handle, "next", 0);
        PDFCheck([PDFStatus(handle)[@"page"] integerValue] == 4, "next page");
        glow_pdf_command(handle, "previous", 0);
        PDFCheck([PDFStatus(handle)[@"page"] integerValue] == 3, "previous page");
        glow_pdf_command(handle, "page", -100);
        PDFCheck([PDFStatus(handle)[@"page"] integerValue] == 1, "page lower boundary");
        glow_pdf_command(handle, "page", 1e300);
        PDFCheck([PDFStatus(handle)[@"page"] integerValue] == [ready[@"pages"] integerValue], "large page clamps to final page");
        glow_pdf_command(handle, "zoom", 2);
        PDFCheck(fabs([PDFStatus(handle)[@"zoom"] doubleValue] - 2) < 0.01, "absolute zoom");
        glow_pdf_command(handle, "zoom", 100);
        PDFCheck([PDFStatus(handle)[@"zoom"] doubleValue] == 5, "zoom upper limit");
        glow_pdf_command(handle, "zoom", -10);
        PDFCheck([PDFStatus(handle)[@"zoom"] doubleValue] == 0.25, "zoom lower limit");
        glow_pdf_command(handle, "fit", 0);
        PDFCheck(preview.pdfView.autoScales, "fit window enables PDFKit autoscaling");
        glow_pdf_command(handle, "focus", 0);
        PDFCheck([(NSView *)window.firstResponder isDescendantOf:preview.view], "native PDF focus");
        glow_pdf_command(handle, "blur", 0);
        PDFCheck(window.firstResponder == parent, "PDF blur returns to editor");
        const double rect[] = {60, 50, 120, 180};
        glow_pdf_occlusion(handle, rect, 1);
        NSPoint point = [preview.view convertPoint:NSMakePoint(80, 70) toView:parent];
        PDFCheck(preview.view.layer.mask != nil && [preview.view hitTest:point] == nil, "PDF floats expose layer and bypass native hit testing");
        glow_pdf_occlusion(handle, NULL, 0);
        PDFCheck(preview.view.layer.mask == nil && [preview.view hitTest:point] != nil, "closing float restores PDF interaction");
        glow_pdf_destroy(handle);
        preview = nil;
        PDFCheck(parent.subviews.count == 0, "PDF close releases child view");
        void *missing = glow_pdf_create((__bridge void *)parent, "/tmp/neovide-glow-missing-pdf-fixture.pdf");
        PDFCheck(PDFWait(^BOOL { return [PDFStatus(missing)[@"state"] isEqualToString:@"error"]; }, 10), "missing file reports load failure");
        PDFCheck([PDFStatus(missing)[@"error"] length] > 0, "load error has useful message");
        glow_pdf_destroy(missing);
        __weak GlowPDFContext *late;
        @autoreleasepool {
            void *closing = glow_pdf_create((__bridge void *)parent, argv[1]);
            late = (__bridge GlowPDFContext *)closing;
            glow_pdf_destroy(closing);
        }
        PDFCheck(PDFWait(^BOOL { return late == nil; }, 10), "closing while loading releases controller");
        PDFCheck(parent.subviews.count == 0, "late completion never reattaches closed PDF");
        [window close];
        puts("PASS: async PDF load, selectable text, page navigation, zoom limits/fit, focus, float occlusion, failure, close during load");
    }
    return 0;
}
