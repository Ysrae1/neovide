// Standalone macOS WebKit smoke check. Does not open or modify a Neovim session.
// xcrun clang -fobjc-arc -fmodules -mmacosx-version-min=11.0 -Wall -Wextra -Werror \
//   tests/media/web-smoke.m -framework AppKit -framework WebKit -o /tmp/glow-web-smoke
// /tmp/glow-web-smoke
#import "../../src/native_preview/web.m"

static void SmokeCheck(BOOL condition, const char *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

static BOOL SmokeWait(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while (!condition() && deadline.timeIntervalSinceNow > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return condition();
}

static NSDictionary *SmokeStatus(void *handle) {
    const char *raw = glow_web_status(handle);
    SmokeCheck(raw != NULL, "status JSON allocation");
    NSData *data = [NSData dataWithBytes:raw length:strlen(raw)];
    free((void *)raw);
    NSDictionary *status = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    SmokeCheck([status isKindOfClass:[NSDictionary class]], "status JSON parses");
    return status;
}

static id SmokeEvaluate(WKWebView *view, NSString *script, WKFrameInfo *frame) {
    __block BOOL complete = NO;
    __block id result = nil;
    __block NSError *failure = nil;
    [view evaluateJavaScript:script inFrame:frame inContentWorld:WKContentWorld.defaultClientWorld
        completionHandler:^(id value, NSError *error) {
            result = value;
            failure = error;
            complete = YES;
        }];
    SmokeCheck(SmokeWait(^BOOL { return complete; }, 8), "JavaScript completion within 8 seconds");
    if (failure) fprintf(stderr, "JavaScript error: %s\n", failure.localizedDescription.UTF8String);
    SmokeCheck(failure == nil, "WebKit evaluates JavaScript in the requested frame");
    return result;
}

// Observe native frame handles without changing the production controller policy.
@interface GlowWebSmokeDelegate : NSObject <WKNavigationDelegate>
@property(nonatomic, weak) GlowWebPreview *target;
@property(nonatomic, strong) WKFrameInfo *srcdocFrame;
@property(nonatomic, strong) WKFrameInfo *dataFrame;
@property(nonatomic, strong) WKFrameInfo *blankFrame;
@end

@implementation GlowWebSmokeDelegate
- (BOOL)respondsToSelector:(SEL)selector {
    return [super respondsToSelector:selector] || [self.target respondsToSelector:selector];
}
- (id)forwardingTargetForSelector:(SEL)selector {
    return [self.target respondsToSelector:selector] ? self.target : [super forwardingTargetForSelector:selector];
}
- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    if (action.targetFrame != nil && !action.targetFrame.mainFrame) {
        NSString *url = action.request.URL.absoluteString;
        if ([url isEqualToString:@"about:srcdoc"]) self.srcdocFrame = action.targetFrame;
        if ([url hasPrefix:@"data:"]) self.dataFrame = action.targetFrame;
        if ([url isEqualToString:@"about:blank"]) self.blankFrame = action.targetFrame;
    }
    [self.target webView:webView decidePolicyForNavigationAction:action decisionHandler:decisionHandler];
}
@end

@interface GlowWebSmokeParentView : NSView
@end
@implementation GlowWebSmokeParentView
- (BOOL)acceptsFirstResponder { return YES; }
@end

@interface GlowWebSmokeFlippedView : GlowWebSmokeParentView
@end
@implementation GlowWebSmokeFlippedView
- (BOOL)isFlipped { return YES; }
@end

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];
        [NSApp finishLaunching];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [@"neovide-glow-web-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSFileManager *files = NSFileManager.defaultManager;
        SmokeCheck([files createDirectoryAtPath:directory withIntermediateDirectories:YES
            attributes:nil error:NULL], "create isolated fixture directory");
        NSString *html = @"<!doctype html><meta charset='utf-8'><link rel='stylesheet' href='sibling.css'>"
            "<script defer src='sibling.js'></script><div id='styled'>Sibling CSS</div>"
            "<input id='edit' value='Native editing input'>";
        NSString *script = @"window.siblingScriptRan = true;"
            "for (const [id, source] of [['srcdoc', '<p id=output>Saved HTML output</p>'],"
            "['data', 'data:text/html,%3Cp%3EEmbedded%20data%20output%3C/p%3E'], ['blank', 'about:blank']]) {"
            "const f = document.createElement('iframe'); f.id=id; f.setAttribute('sandbox','');"
            "f.onload = () => window[id + 'Loaded'] = true;"
            "if (id === 'srcdoc') f.srcdoc=source; else f.src=source; document.body.appendChild(f); }";
        NSString *file = [directory stringByAppendingPathComponent:@"index.html"];
        NSString *outside = [directory stringByAppendingString:@"-outside"];
        SmokeCheck([files createDirectoryAtPath:outside withIntermediateDirectories:YES attributes:nil error:NULL],
            "create outside-scope fixture directory");
        NSString *outsideFile = [outside stringByAppendingPathComponent:@"outside.html"];
        SmokeCheck([@"<p>outside folder</p>" writeToFile:outsideFile atomically:YES
            encoding:NSUTF8StringEncoding error:NULL], "write outside-scope fixture");
        NSString *escape = [directory stringByAppendingPathComponent:@"linked-outside.html"];
        SmokeCheck([files createSymbolicLinkAtPath:escape withDestinationPath:outsideFile error:NULL],
            "create symlink escape fixture");
        NSURL *root = [NSURL fileURLWithPath:directory isDirectory:YES];
        SmokeCheck(GlowWebFileWithinReadAccess([NSURL fileURLWithPath:file], root), "same folder permitted");
        SmokeCheck(!GlowWebFileWithinReadAccess([NSURL fileURLWithPath:outsideFile], root),
            "similar directory prefix is outside scope");
        SmokeCheck(!GlowWebFileWithinReadAccess([NSURL fileURLWithPath:escape], root),
            "symlink target outside folder is outside scope");
        SmokeCheck(!GlowWebFileWithinReadAccess([NSURL fileURLWithPath:file], nil),
            "remote previews have no local file grant");
        SmokeCheck([html writeToFile:file atomically:YES encoding:NSUTF8StringEncoding error:NULL]
            && [@"#styled { color: rgb(12, 34, 56) }" writeToFile:
                [directory stringByAppendingPathComponent:@"sibling.css"] atomically:YES
                encoding:NSUTF8StringEncoding error:NULL]
            && [script writeToFile:[directory stringByAppendingPathComponent:@"sibling.js"]
                atomically:YES encoding:NSUTF8StringEncoding error:NULL], "write HTML/CSS/JS fixtures");

        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 900, 700)
            styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO];
        window.releasedWhenClosed = NO;
        NSView *parent = [[GlowWebSmokeParentView alloc] initWithFrame:NSMakeRect(0, 0, 900, 700)];
        window.contentView = parent;
        __weak GlowWebPreview *weakPreview;
        __weak WKWebView *weakView;
        @autoreleasepool {
            void *handle = glow_web_create((__bridge void *)parent, file.fileSystemRepresentation);
            SmokeCheck(handle != NULL, "create native WebKit handle");
            GlowWebPreview *preview = (__bridge GlowWebPreview *)handle;
            weakPreview = preview;
            weakView = preview.view;
            SmokeCheck(preview.view.hidden && NSEqualRects(preview.view.frame, NSZeroRect),
                "preview starts hidden until split geometry arrives");
            GlowWebSmokeDelegate *probe = [[GlowWebSmokeDelegate alloc] init];
            probe.target = preview;
            preview.view.navigationDelegate = probe;
            glow_web_frame(handle, 25, 30, 500, 400);
            SmokeCheck(!preview.view.hidden && NSEqualRects(preview.view.frame, NSMakeRect(25, 270, 500, 400)),
                "top-left geometry in an unflipped parent");
            SmokeCheck(SmokeWait(^BOOL {
                return ![SmokeStatus(handle)[@"state"] isEqualToString:@"loading"];
            }, 15), "local document load completes within 15 seconds");
            NSDictionary *status = SmokeStatus(handle);
            if (![status[@"state"] isEqualToString:@"ready"]) fprintf(stderr, "%s\n", status.description.UTF8String);
            SmokeCheck([status[@"state"] isEqualToString:@"ready"], "local document reports ready");
            SmokeCheck([status[@"read_root"] isEqualToString:root.URLByResolvingSymlinksInPath.path],
                "status discloses canonical readable directory");
            // Page scripts and this isolated client world share the DOM, not JS globals.
            SmokeCheck([[SmokeEvaluate(preview.view, @"getComputedStyle(document.querySelector('#styled')).color", nil)
                description] isEqualToString:@"rgb(12, 34, 56)"], "sibling CSS loads");
            SmokeCheck([SmokeEvaluate(preview.view, @"document.querySelectorAll('iframe').length", nil) integerValue] == 3,
                "sibling JavaScript executes and inserts three saved-output frames");
            SmokeCheck(probe.srcdocFrame != nil && probe.dataFrame != nil && probe.blankFrame != nil,
                "srcdoc, data and blank navigations occur in child frames");
            SmokeCheck([[SmokeEvaluate(preview.view, @"document.body.innerText.trim()", probe.srcdocFrame) description]
                isEqualToString:@"Saved HTML output"], "sandboxed srcdoc output renders its saved HTML");
            SmokeCheck([[SmokeEvaluate(preview.view, @"document.body.innerText.trim()", probe.dataFrame) description]
                isEqualToString:@"Embedded data output"], "sandboxed data output renders");
            SmokeCheck([SmokeEvaluate(preview.view, @"document.body.innerText.length", probe.blankFrame) integerValue] == 0,
                "sandboxed about:blank child is available");
            glow_web_command(handle, "zoom", 999);
            SmokeCheck([SmokeStatus(handle)[@"zoom"] doubleValue] == 5, "zoom upper boundary");
            glow_web_command(handle, "zoom", -999);
            SmokeCheck([SmokeStatus(handle)[@"zoom"] doubleValue] == 0.25, "zoom lower boundary");
            glow_web_command(handle, "zoom", 1.5);
            SmokeCheck([SmokeStatus(handle)[@"zoom"] doubleValue] == 1.5, "absolute zoom status");

            glow_web_command(handle, "focus", 0);
            SmokeCheck([(NSView *)window.firstResponder isDescendantOf:preview.view], "native page accepts focus");
            SmokeEvaluate(preview.view, @"document.querySelector('#edit').focus(); true", nil);
            NSEvent *selectAll = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                modifierFlags:NSEventModifierFlagCommand timestamp:0 windowNumber:window.windowNumber
                context:nil characters:@"a" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0];
            SmokeCheck([preview handleKeyEvent:selectAll] == nil,
                "focused WebKit handles and consumes native Cmd+A");
            SmokeCheck([SmokeEvaluate(preview.view,
                @"(() => {const e=document.querySelector('#edit');return e.selectionStart===0 && e.selectionEnd===e.value.length})()",
                nil) boolValue], "Cmd+A selects the native HTML input contents");
            glow_web_command(handle, "blur", 0);
            SmokeCheck(window.firstResponder == parent, "blur returns first responder to editor parent");
            SmokeCheck([preview handleKeyEvent:selectAll] == selectAll,
                "editor-focused Cmd+A remains on the editor event path");
            [preview.view loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:outsideFile]]];
            SmokeCheck(SmokeWait(^BOOL { return [SmokeStatus(handle)[@"state"] isEqualToString:@"error"]; }, 5),
                "actual outside-folder navigation is blocked");
            SmokeCheck([SmokeStatus(handle)[@"error"] containsString:@"outside"],
                "outside navigation explains how to open a separate preview");
            [preview.view loadRequest:[NSURLRequest requestWithURL:[NSURL fileURLWithPath:file]]];
            SmokeCheck(SmokeWait(^BOOL { return [SmokeStatus(handle)[@"state"] isEqualToString:@"ready"]; }, 15),
                "same-folder navigation recovers without widening access");
            // Exercise the actual navigation delegate, separately from initial URL validation.
            [preview.view loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"about:blank"]]];
            SmokeCheck(SmokeWait(^BOOL {
                return [SmokeStatus(handle)[@"state"] isEqualToString:@"error"];
            }, 5), "top-level about:blank navigation remains blocked");

            @autoreleasepool {
                glow_web_destroy(handle);
                SmokeCheck(parent.subviews.count == 0 && preview.view == nil
                    && preview.keyMonitor == nil && preview.destroyed, "destroy detaches and clears owned resources");
            }
            preview = nil;
            probe = nil;
        }
        SmokeCheck(weakPreview == nil, "destroy releases the opaque controller ownership");
        SmokeCheck(SmokeWait(^BOOL { return weakView == nil; }, 3), "WebKit view is released");

        NSView *flipped = [[GlowWebSmokeFlippedView alloc] initWithFrame:parent.bounds];
        [parent addSubview:flipped];
        for (NSString *invalidURL in @[@"about:blank", @"about:srcdoc", @"data:text/html,blocked",
                                       [directory stringByAppendingPathComponent:@"missing.html"]]) {
            void *invalid = glow_web_create((__bridge void *)flipped, invalidURL.UTF8String);
            GlowWebPreview *invalidPreview = (__bridge GlowWebPreview *)invalid;
            NSDictionary *failure = SmokeStatus(invalid);
            SmokeCheck([failure[@"state"] isEqualToString:@"error"] && [failure[@"error"] length] > 0,
                "top-level embedded URL/missing file reports an error");
            glow_web_frame(invalid, 25, 30, 500, 400);
            SmokeCheck(NSEqualRects(invalidPreview.view.frame, NSMakeRect(25, 30, 500, 400)),
                "top-left geometry in a flipped parent");
            glow_web_destroy(invalid);
            SmokeCheck(flipped.subviews.count == 0, "error preview cleans up");
        }
        [flipped removeFromSuperview];
        [window close];
        SmokeCheck([files removeItemAtPath:directory error:NULL], "remove isolated fixture directory");
        SmokeCheck([files removeItemAtPath:outside error:NULL], "remove outside-scope fixture directory");
        puts("PASS: scoped file navigation and canonical symlink boundary; local CSS/JS; sandboxed srcdoc/data/blank child output; main URL errors; zoom; focus/blur; native input Cmd+A; editor command passthrough; flipped geometry; cleanup");
    }
    return 0;
}
