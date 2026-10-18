// Native macOS Web preview. All entry points are called on the AppKit main thread.
// The opaque handle owns the controller; the caller must free status JSON with free().
#import <AppKit/AppKit.h>
#import <WebKit/WebKit.h>

#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "media.h"

@interface GlowWebView : WKWebView
@property(nonatomic, copy) NSArray<NSValue *> *occlusionRegions;
@property(nonatomic) NSSize occlusionSize;
- (void)setOcclusions:(const double *)rects count:(size_t)count;
@end

@implementation GlowWebView
- (void)setOcclusions:(const double *)rects count:(size_t)count {
    NSArray<NSValue *> *regions = GlowPreviewOcclusionRects(self, rects, count);
    if (NSEqualSizes(self.occlusionSize, self.bounds.size) && [self.occlusionRegions isEqualToArray:regions]) return;
    self.occlusionRegions = regions;
    self.occlusionSize = self.bounds.size;
    GlowPreviewApplyOcclusion(self, regions);
}
- (NSView *)hitTest:(NSPoint)point {
    return GlowPreviewOccludesPoint(self, self.occlusionRegions, point) ? nil : [super hitTest:point];
}
@end

@interface GlowWebPreview : NSObject <WKNavigationDelegate, WKUIDelegate>
@property(nonatomic, weak) NSView *parent;
@property(nonatomic, strong) GlowWebView *view;
@property(nonatomic, strong) id keyMonitor;
@property(nonatomic, copy) NSString *state;
@property(nonatomic, copy) NSString *error;
@property(nonatomic, copy) NSString *requestedURL;
@property(nonatomic) BOOL destroyed;
- (instancetype)initWithParent:(NSView *)parent url:(NSString *)url;
- (void)fail:(NSString *)message;
- (void)blur;
- (NSEvent *)handleKeyEvent:(NSEvent *)event;
- (void)destroy;
@end

static BOOL GlowWebAllowedURL(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"file"]) {
        return url.isFileURL && (url.host.length == 0 || [url.host isEqualToString:@"localhost"]);
    }
    return ([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        && url.host.length > 0;
}

static BOOL GlowWebAllowedChildURL(NSURL *url) {
    NSString *scheme = url.scheme.lowercaseString;
    if ([scheme isEqualToString:@"data"]) return YES;
    if (![scheme isEqualToString:@"about"]) return NO;
    NSURLComponents *components = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
    return [components.path isEqualToString:@"blank"] || [components.path isEqualToString:@"srcdoc"];
}

@implementation GlowWebPreview

- (instancetype)initWithParent:(NSView *)parent url:(NSString *)text {
    self = [super init];
    if (!self) return nil;
    _parent = parent;
    _state = @"loading";
    _error = @"";
    _requestedURL = text ?: @"";

    WKWebViewConfiguration *configuration = [[WKWebViewConfiguration alloc] init];
    configuration.defaultWebpagePreferences.allowsContentJavaScript = YES;
    // Keep preview browser state in an ephemeral WebKit data store.
    configuration.websiteDataStore = [WKWebsiteDataStore nonPersistentDataStore];
    _view = [[GlowWebView alloc] initWithFrame:NSZeroRect configuration:configuration];
    _view.navigationDelegate = self;
    _view.UIDelegate = self;
    _view.autoresizingMask = NSViewNotSizable;
    _view.allowsMagnification = NO;
    // Wait for the editor's first split geometry before exposing the child view.
    _view.hidden = YES;
    [parent addSubview:_view];

    __weak GlowWebPreview *weakSelf = self;
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
        handler:^NSEvent *(NSEvent *event) {
            GlowWebPreview *preview = weakSelf;
            return preview ? [preview handleKeyEvent:event] : event;
        }];

    NSURL *url = nil;
    NSString *path = [text stringByExpandingTildeInPath];
    if ([path hasPrefix:@"/"]) {
        url = [NSURL fileURLWithPath:path.stringByStandardizingPath];
    } else {
        url = [NSURL URLWithString:text ?: @""];
    }
    if (!url || !GlowWebAllowedURL(url)) {
        [self fail:@"Web preview requires an absolute local file path or an http/https URL."];
        return self;
    }
    _requestedURL = url.absoluteString;
    if (url.isFileURL) {
        BOOL isDirectory = NO;
        if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDirectory]
            || isDirectory || ![[NSFileManager defaultManager] isReadableFileAtPath:url.path]) {
            [self fail:@"The local web preview file is missing or unreadable."];
            return self;
        }
        // Grant the containing directory so sibling CSS, JS and images can be loaded.
        [_view loadFileURL:url allowingReadAccessToURL:url.URLByDeletingLastPathComponent];
    } else {
        [_view loadRequest:[NSURLRequest requestWithURL:url]];
    }
    return self;
}

- (NSEvent *)handleKeyEvent:(NSEvent *)event {
    WKWebView *view = self.view;
    if (self.destroyed || view.hidden || event.window != view.window) {
        return event;
    }
    NSResponder *responder = view.window.firstResponder;
    if (![responder isKindOfClass:[NSView class]]
        || ![(NSView *)responder isDescendantOf:view]) {
        return event;
    }
    NSEventModifierFlags modifiers = event.modifierFlags
        & (NSEventModifierFlagCommand | NSEventModifierFlagShift
           | NSEventModifierFlagControl | NSEventModifierFlagOption);
    if (modifiers == NSEventModifierFlagCommand
        || modifiers == (NSEventModifierFlagCommand | NSEventModifierFlagShift)) {
        NSString *key = event.charactersIgnoringModifiers.lowercaseString;
        NSString *action = nil;
        if (modifiers == NSEventModifierFlagCommand) {
            if ([key isEqualToString:@"a"]) action = @"selectAll:";
            else if ([key isEqualToString:@"c"]) action = @"copy:";
            else if ([key isEqualToString:@"x"]) action = @"cut:";
            else if ([key isEqualToString:@"v"]) action = @"paste:";
            else if ([key isEqualToString:@"z"]) action = @"undo:";
        } else if ([key isEqualToString:@"z"]) {
            action = @"redo:";
        }
        // winit's editor menu does not contain an Edit menu. Dispatch standard
        // native editing actions directly through the focused WebKit responder.
        // Return unhandled commands to the normal application event path.
        if (action && [responder tryToPerform:NSSelectorFromString(action) with:view]) return nil;
    }
    if (modifiers == NSEventModifierFlagCommand && event.keyCode == 53) {
        [self blur];
        return nil; // Cmd+Esc is the explicit escape from native page input.
    }
    if (event.keyCode == 48
        && (modifiers == NSEventModifierFlagControl
            || modifiers == (NSEventModifierFlagControl | NSEventModifierFlagShift))) {
        // Ctrl+Tab/Ctrl+Shift+Tab select Neovim tabs via the editor mappings.
        [self blur];
        return event;
    }
    if (modifiers == (NSEventModifierFlagCommand | NSEventModifierFlagShift)) {
        NSString *key = event.charactersIgnoringModifiers;
        if ([key isEqualToString:@"["] || [key isEqualToString:@"]"]
            || [key isEqualToString:@"{"] || [key isEqualToString:@"}"]) {
            // Send this same event to winit's NSView after changing responder.
            // Lua maps these commands to Neovim tabs. Plain Tab stays in the page.
            [self blur];
        }
    }
    return event;
}

- (void)fail:(NSString *)message {
    if (self.destroyed) return;
    self.state = @"error";
    self.error = message ?: @"Web preview failed.";
}

- (void)blur {
    NSWindow *window = self.view.window;
    if (window && self.parent) [window makeFirstResponder:self.parent];
}

- (void)webView:(WKWebView *)webView didStartProvisionalNavigation:(WKNavigation *)navigation {
    if (self.destroyed) return;
    self.state = @"loading";
    self.error = @"";
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
    if (self.destroyed) return;
    self.state = @"ready";
    self.error = @"";
    if (webView.URL) self.requestedURL = webView.URL.absoluteString;
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation
    withError:(NSError *)error {
    // Replacing a load (reload/back/forward) cancels the previous request normally.
    if (error.code == NSURLErrorCancelled && [error.domain isEqualToString:NSURLErrorDomain]) return;
    // WebKit reports policy cancellation as legacy error 102; preserve our cause.
    if (error.code == 102 && [error.domain isEqualToString:@"WebKitErrorDomain"]
        && [self.state isEqualToString:@"error"]) return;
    [self fail:error.localizedDescription];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation
    withError:(NSError *)error {
    if (error.code == NSURLErrorCancelled && [error.domain isEqualToString:NSURLErrorDomain]) return;
    if (error.code == 102 && [error.domain isEqualToString:@"WebKitErrorDomain"]
        && [self.state isEqualToString:@"error"]) return;
    [self fail:error.localizedDescription];
}

- (void)webViewWebContentProcessDidTerminate:(WKWebView *)webView {
    [self fail:@"The WebKit content process stopped. Reload the preview to try again."];
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationAction:(WKNavigationAction *)action
    decisionHandler:(void (^)(WKNavigationActionPolicy))decisionHandler {
    NSURL *url = action.request.URL;
    // Notebook HTML outputs use a sandboxed srcdoc iframe. Only existing child
    // frames may navigate to inert/about or embedded data documents; a new
    // window (nil target) and the main frame retain the file/http(s) policy.
    BOOL childFrame = action.targetFrame != nil && !action.targetFrame.mainFrame;
    BOOL allowed = GlowWebAllowedURL(url) || (childFrame && GlowWebAllowedChildURL(url));
    if (self.destroyed || !allowed) {
        if (!self.destroyed && (action.targetFrame == nil || action.targetFrame.mainFrame)) {
            [self fail:[NSString stringWithFormat:@"Unsupported web navigation: %@", url.scheme ?: @"(missing URL)"]];
        }
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (action.targetFrame == nil) {
        // target=_blank/window.open remain in the managed preview, not a new NSWindow.
        [webView loadRequest:action.request];
        decisionHandler(WKNavigationActionPolicyCancel);
        return;
    }
    if (action.targetFrame.mainFrame) self.requestedURL = url.absoluteString;
    decisionHandler(WKNavigationActionPolicyAllow);
}

- (void)webView:(WKWebView *)webView decidePolicyForNavigationResponse:(WKNavigationResponse *)response
    decisionHandler:(void (^)(WKNavigationResponsePolicy))decisionHandler {
    if (self.destroyed) {
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }
    if (response.forMainFrame && [response.response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSInteger status = ((NSHTTPURLResponse *)response.response).statusCode;
        if (status >= 400) {
            [self fail:[NSString stringWithFormat:@"HTTP %ld: %@", (long)status,
                [NSHTTPURLResponse localizedStringForStatusCode:status]]];
            decisionHandler(WKNavigationResponsePolicyCancel);
            return;
        }
    }
    if (response.forMainFrame && !response.canShowMIMEType) {
        [self fail:@"WebKit cannot display this response type."];
        decisionHandler(WKNavigationResponsePolicyCancel);
        return;
    }
    decisionHandler(WKNavigationResponsePolicyAllow);
}

- (void)destroy {
    if (self.destroyed) return;
    self.destroyed = YES;
    if (self.keyMonitor) {
        [NSEvent removeMonitor:self.keyMonitor];
        self.keyMonitor = nil;
    }
    NSResponder *responder = self.view.window.firstResponder;
    if ([responder isKindOfClass:[NSView class]]
        && [(NSView *)responder isDescendantOf:self.view]) [self blur];
    self.view.navigationDelegate = nil;
    self.view.UIDelegate = nil;
    [self.view stopLoading];
    self.view.hidden = YES;
    [self.view removeFromSuperview];
    self.view = nil;
    self.parent = nil;
}

@end

void *glow_web_create(void *parent_nsview, const char *url) {
    if (![NSThread isMainThread] || !parent_nsview) return NULL;
    @autoreleasepool {
        NSView *parent = (__bridge NSView *)parent_nsview;
        NSString *text = url ? [NSString stringWithUTF8String:url] : nil;
        GlowWebPreview *preview = [[GlowWebPreview alloc] initWithParent:parent url:text ?: @""];
        return (__bridge_retained void *)preview;
    }
}

void glow_web_frame(void *handle, double x, double y, double width, double height) {
    if (!handle || ![NSThread isMainThread]) return;
    @autoreleasepool {
        GlowWebPreview *preview = (__bridge GlowWebPreview *)handle;
        NSView *parent = preview.parent;
        if (preview.destroyed || !parent) return;
        if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height)) return;
        width = fmax(0, width);
        height = fmax(0, height);
        NSRect bounds = parent.bounds;
        double originY = parent.isFlipped ? NSMinY(bounds) + y : NSMaxY(bounds) - y - height;
        preview.view.frame = NSMakeRect(NSMinX(bounds) + x, originY, width, height);
        preview.view.hidden = width <= 0 || height <= 0;
    }
}

void glow_web_occlusion(void *handle, const double *rects, size_t count) {
    if (!handle || ![NSThread isMainThread]) return;
    @autoreleasepool {
        GlowWebPreview *preview = (__bridge GlowWebPreview *)handle;
        if (!preview.destroyed) [preview.view setOcclusions:rects count:count];
    }
}

void glow_web_command(void *handle, const char *action, double value) {
    if (!handle || !action || ![NSThread isMainThread]) return;
    @autoreleasepool {
        GlowWebPreview *preview = (__bridge GlowWebPreview *)handle;
        if (preview.destroyed) return;
        if (strcmp(action, "reload") == 0) {
            [preview.view reloadFromOrigin];
        } else if (strcmp(action, "zoom") == 0 && isfinite(value)) {
            preview.view.pageZoom = fmin(5, fmax(0.25, value));
        } else if (strcmp(action, "focus") == 0) {
            if (!preview.view.hidden) [preview.view.window makeFirstResponder:preview.view];
        } else if (strcmp(action, "blur") == 0) {
            [preview blur];
        } else if (strcmp(action, "back") == 0 && preview.view.canGoBack) {
            [preview.view goBack];
        } else if (strcmp(action, "forward") == 0 && preview.view.canGoForward) {
            [preview.view goForward];
        }
    }
}

const char *glow_web_status(void *handle) {
    if (!handle || ![NSThread isMainThread]) {
        return strdup("{\"state\":\"error\",\"error\":\"Web preview is unavailable on this thread.\",\"url\":\"\",\"zoom\":1,\"kind\":\"web\"}");
    }
    @autoreleasepool {
        GlowWebPreview *preview = (__bridge GlowWebPreview *)handle;
        NSDictionary *status = @{
            @"state": preview.state ?: @"error",
            @"error": preview.error ?: @"",
            @"url": preview.requestedURL ?: @"",
            @"zoom": @(preview.view ? preview.view.pageZoom : 1),
            @"kind": @"web",
        };
        NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
        NSString *text = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        return strdup(text.UTF8String ?: "{\"state\":\"error\",\"error\":\"Cannot encode web status.\",\"url\":\"\",\"zoom\":1,\"kind\":\"web\"}");
    }
}

void glow_web_destroy(void *handle) {
    if (!handle || ![NSThread isMainThread]) return;
    @autoreleasepool {
        GlowWebPreview *preview = (__bridge_transfer GlowWebPreview *)handle;
        [preview destroy];
    }
}
