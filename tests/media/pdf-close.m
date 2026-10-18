// xcrun clang -fobjc-arc -fmodules -mmacosx-version-min=11.0 -Wall -Wextra -Werror \
//   tests/media/pdf-close.m -framework AppKit -framework PDFKit -framework QuartzCore -o /tmp/glow-pdf-close
// /tmp/glow-pdf-close /tmp/glow-pdf-fixture.pdf
#import "../../src/native_preview/pdf.m"

static void Check(BOOL value, const char *message) {
    if (!value) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}
@interface PDFKeyParent : NSView
@end
@implementation PDFKeyParent
- (BOOL)acceptsFirstResponder { return YES; }
@end
static BOOL Send(GlowPDFContext *context, NSString *key, unsigned short code, NSEventModifierFlags modifiers) {
    NSWindow *window = context.view.window;
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifiers
        timestamp:0 windowNumber:window.windowNumber context:nil characters:key charactersIgnoringModifiers:key
        isARepeat:NO keyCode:code];
    return [context handleKeyEvent:event] == nil;
}
int main(int argc, const char **argv) {
    @autoreleasepool {
        Check(argc == 2, "pass existing PDF fixture");
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSApp finishLaunching];
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,800,600)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        PDFKeyParent *parent = [[PDFKeyParent alloc] initWithFrame:NSMakeRect(0,0,800,600)];
        window.contentView = parent;
        void *handle = glow_pdf_create((__bridge void *)parent, argv[1]);
        GlowPDFContext *context = (__bridge GlowPDFContext *)handle;
        glow_pdf_frame(handle,0,0,800,600);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while ([context.state isEqualToString:@"loading"] && deadline.timeIntervalSinceNow > 0)
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        Check([context.state isEqualToString:@"ready"], "fixture ready");
        [window makeFirstResponder:parent];
        Check(!Send(context,@"q",12,0) && !context.closeRequested, "editor q remains normal editor input");
        glow_pdf_command(handle,"focus",0);
        Check(!Send(context,@"q",12,NSEventModifierFlagControl) && !context.closeRequested, "modified q does not close PDF");
        [window makeFirstResponder:context.pageField];
        Check([window.firstResponder isKindOfClass:NSTextView.class], "page field uses a real editor");
        Check(!Send(context,@"q",12,0) && !context.closeRequested, "page field q remains text input");
        glow_pdf_command(handle,"focus",0);
        BOOL consumed = Send(context,@"q",12,0);
        Check(consumed && context.closeRequested && window.firstResponder == parent,
            "native PDF q requests owner close without injecting an editor macro");
        const char *raw = glow_pdf_status(handle);
        NSDictionary *status = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:raw length:strlen(raw)] options:0 error:NULL];
        free((void *)raw);
        Check([status[@"close_requested"] boolValue], "existing async status carries close request");
        context.closeRequested = NO;
        glow_pdf_command(handle,"focus",0);
        consumed = Send(context,@"\033",53,0);
        Check(consumed && context.closeRequested && window.firstResponder == parent,
            "native PDF Escape requests close and is consumed");
        glow_pdf_destroy(handle);
        [window close];
        puts("PASS: editor q preserved; PDF q/Escape close request; modifiers/page input untouched; async status");
    }
    return 0;
}
