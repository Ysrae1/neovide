// PDFKit document loading runs off the AppKit thread; all view mutation stays on it.
#import <AppKit/AppKit.h>
#import <PDFKit/PDFKit.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "media.h"

@class GlowPDFContext;
@interface GlowPDFContainer : NSView
@property(nonatomic, weak) GlowPDFContext *context;
@property(nonatomic, copy) NSArray<NSValue *> *occlusionRegions;
@property(nonatomic) NSSize occlusionSize;
- (void)setOcclusions:(const double *)rects count:(size_t)count;
@end

@interface GlowPDFContext : NSObject
@property(nonatomic, weak) NSView *parent;
@property(nonatomic, strong) GlowPDFContainer *view;
@property(nonatomic, strong) PDFView *pdfView;
@property(nonatomic, strong) NSStackView *toolbar;
@property(nonatomic, strong) NSTextField *pageField;
@property(nonatomic, strong) NSTextField *pageCount;
@property(nonatomic, strong) NSTextField *zoomLabel;
@property(nonatomic, strong) NSTextField *message;
@property(nonatomic, strong) NSButton *previousButton;
@property(nonatomic, strong) NSButton *nextButton;
@property(nonatomic, strong) id pageObserver;
@property(nonatomic, strong) id scaleObserver;
@property(nonatomic, strong) id keyMonitor;
@property(nonatomic, copy) NSString *state;
@property(nonatomic, copy) NSString *error;
@property(nonatomic, strong) NSURL *url;
@property(nonatomic) NSUInteger loadGeneration;
@property(nonatomic) NSUInteger requestedPage;
@property(nonatomic) double requestedZoom;
@property(nonatomic) BOOL fit;
@property(nonatomic) BOOL destroyed;
@property(nonatomic) BOOL closeRequested;
@property(nonatomic, strong) NSDictionary *syncTarget;
@property(nonatomic, strong) NSDictionary *inverseSync;
@property(nonatomic) NSUInteger syncSequence;
@property(nonatomic) NSUInteger highlightGeneration;
@property(nonatomic, strong) PDFAnnotation *syncAnnotation;
- (instancetype)initWithParent:(NSView *)parent path:(const char *)path;
- (void)layout;
- (void)load;
- (void)updateControls;
- (void)command:(NSString *)action value:(double)value;
- (void)blur;
- (NSEvent *)handleKeyEvent:(NSEvent *)event;
- (void)destroy;
- (void)syncPage:(NSUInteger)page x:(double)x y:(double)y width:(double)width height:(double)height;
- (void)inverseAtPoint:(NSPoint)point;
- (void)clearSyncHighlight;
@end

// PDFKit page points are unrotated PDF coordinates. SyncTeX uses big points
// from the MediaBox's upper-left; PDFView handles CropBox/rotation conversion.
static NSPoint GlowPDFPointFromSync(PDFPage *page, double x, double y) {
    NSRect media = [page boundsForBox:kPDFDisplayBoxMediaBox];
    return NSMakePoint(NSMinX(media) + x, NSMaxY(media) - y);
}
static NSPoint GlowPDFPointToSync(PDFPage *page, NSPoint point) {
    NSRect media = [page boundsForBox:kPDFDisplayBoxMediaBox];
    return NSMakePoint(point.x - NSMinX(media), NSMaxY(media) - point.y);
}

@implementation GlowPDFContainer
- (BOOL)isFlipped { return YES; }
- (void)layout { [super layout]; [self.context layout]; }
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

static NSButton *GlowPDFButton(NSString *title, id target, SEL action, NSString *label) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.bezelStyle = NSBezelStyleRounded;
    button.font = [NSFont systemFontOfSize:12];
    [button setAccessibilityLabel:label];
    return button;
}

@implementation GlowPDFContext
- (instancetype)initWithParent:(NSView *)parent path:(const char *)path {
    self = [super init];
    if (!self) return nil;
    _parent = parent;
    _state = @"loading";
    _error = @"";
    _fit = YES;
    _requestedPage = 1;
    _view = [[GlowPDFContainer alloc] initWithFrame:NSZeroRect];
    _view.context = self;
    _view.hidden = YES;
    _view.wantsLayer = YES;
    _view.layer.masksToBounds = YES;
    _view.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    _pdfView = [[PDFView alloc] initWithFrame:NSZeroRect];
    _pdfView.displayMode = kPDFDisplaySinglePageContinuous;
    _pdfView.displayDirection = kPDFDisplayDirectionVertical;
    _pdfView.displaysPageBreaks = YES;
    _pdfView.minScaleFactor = 0.25;
    _pdfView.maxScaleFactor = 5;
    _pdfView.autoScales = YES;
    _pdfView.hidden = YES;
    [_view addSubview:_pdfView];
    _previousButton = GlowPDFButton(@"‹", self, @selector(previous:), @"上一页");
    _nextButton = GlowPDFButton(@"›", self, @selector(next:), @"下一页");
    _pageField = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 44, 22)];
    _pageField.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    _pageField.alignment = NSTextAlignmentCenter;
    _pageField.target = self;
    _pageField.action = @selector(pageEntered:);
    [_pageField.widthAnchor constraintEqualToConstant:44].active = YES;
    [_pageField setAccessibilityLabel:@"跳转页码"];
    _pageCount = [NSTextField labelWithString:@"/ —"];
    _pageCount.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    _zoomLabel = [NSTextField labelWithString:@"100%"];
    _zoomLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    _toolbar = [NSStackView stackViewWithViews:@[_previousButton, _pageField, _pageCount, _nextButton,
        GlowPDFButton(@"−", self, @selector(zoomOut:), @"缩小"), _zoomLabel,
        GlowPDFButton(@"+", self, @selector(zoomIn:), @"放大"),
        GlowPDFButton(@"适合", self, @selector(fitPage:), @"适合窗口")]];
    _toolbar.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    _toolbar.alignment = NSLayoutAttributeCenterY;
    _toolbar.spacing = 5;
    // The themed Lua PDF capsules own navigation and zoom. Keep the duplicate
    // native controls hidden, without reserving a second toolbar above the page.
    _toolbar.hidden = YES;
    [_view addSubview:_toolbar];
    _message = [NSTextField labelWithString:@"正在加载 PDF…"];
    _message.alignment = NSTextAlignmentCenter;
    _message.lineBreakMode = NSLineBreakByWordWrapping;
    _message.maximumNumberOfLines = 0;
    _message.textColor = NSColor.secondaryLabelColor;
    [_view addSubview:_message];
    [parent addSubview:_view];
    __weak GlowPDFContext *weakSelf = self;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    _pageObserver = [center addObserverForName:PDFViewPageChangedNotification object:_pdfView
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; [weakSelf updateControls]; }];
    _scaleObserver = [center addObserverForName:PDFViewScaleChangedNotification object:_pdfView
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) { (void)note; [weakSelf updateControls]; }];
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:(NSEventMaskKeyDown | NSEventMaskLeftMouseDown) handler:^NSEvent *(NSEvent *event) {
        GlowPDFContext *context = weakSelf;
        if (!context || context.destroyed || context.view.hidden || event.window != context.view.window) return event;
        // PDFKit sends mouseDown to its internal PDFPageView. Intercept the
        // exact modifier in the event stream, scoped to this visible PDF tree.
        if (event.type == NSEventTypeLeftMouseDown) {
            NSEventModifierFlags mods = event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption);
            if (mods != NSEventModifierFlagCommand) return event;
            NSView *content = event.window.contentView;
            NSView *hit = [content hitTest:[content convertPoint:event.locationInWindow fromView:nil]];
            if (hit != context.pdfView && ![hit isDescendantOf:context.pdfView]) return event;
            [context inverseAtPoint:[context.pdfView convertPoint:event.locationInWindow fromView:nil]];
            return nil;
        }
        return [context handleKeyEvent:event];
    }];
    NSString *text = path ? [NSString stringWithUTF8String:path] : nil;
    if (text.isAbsolutePath) _url = [NSURL fileURLWithPath:text];
    else {
        NSURL *url = text ? [NSURL URLWithString:text] : nil;
        if (url.isFileURL && url.path.isAbsolutePath && (!url.host.length || [url.host isEqualToString:@"localhost"])) _url = url;
    }
    [self load];
    return self;
}

- (NSEvent *)handleKeyEvent:(NSEvent *)event {
    GlowPDFContext *context = self;
    if (self.destroyed || self.view.hidden || event.window != self.view.window) return event;
    NSResponder *responder = context.view.window.firstResponder;
    if (![responder isKindOfClass:NSView.class] || ![(NSView *)responder isDescendantOf:context.view]) return event;
    NSEventModifierFlags modifiers = event.modifierFlags & (NSEventModifierFlagCommand
        | NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption);
    BOOL editing = [responder isKindOfClass:NSTextView.class] && [(NSTextView *)responder isFieldEditor];
    if (!modifiers && !editing && (event.keyCode == 53 || [event.charactersIgnoringModifiers isEqualToString:@"q"])) {
        // PDFKit owns these keystrokes while its controls are focused;
        // Neovim's current window may still be the SyncTeX source. Route
        // closure by this preview's status/id instead of injecting q.
        context.closeRequested = YES;
        [context blur];
        return nil;
    }
    if (event.keyCode == 48 && (modifiers == NSEventModifierFlagControl
        || modifiers == (NSEventModifierFlagControl | NSEventModifierFlagShift))) {
        [context blur]; return event;
    }
    if (modifiers == NSEventModifierFlagCommand && event.keyCode == 53) {
        [context blur]; return nil;
    }
    if (modifiers == (NSEventModifierFlagCommand | NSEventModifierFlagShift)
        && [@[@"[", @"]", @"{", @"}"] containsObject:event.charactersIgnoringModifiers ?: @""]) [context blur];
    if (modifiers == NSEventModifierFlagCommand && [event.charactersIgnoringModifiers.lowercaseString isEqualToString:@"c"]
        && [NSApp sendAction:@selector(copy:) to:nil from:context.pdfView]) return nil;
    return event;
}

- (void)load {
    if (self.destroyed) return;
    NSUInteger generation = ++self.loadGeneration;
    [self clearSyncHighlight];
    self.pdfView.document = nil;
    self.state = @"loading";
    self.error = @"";
    if (!self.url) {
        self.state = @"error";
        self.error = @"请使用本地 PDF 的绝对路径。";
        [self updateControls];
        return;
    }
    [self updateControls];
    NSURL *url = self.url;
    __weak GlowPDFContext *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            PDFDocument *document = [[PDFDocument alloc] initWithURL:url];
            NSUInteger pages = document.pageCount;
            NSString *failure = !document ? @"无法打开 PDF，文件可能不存在、已损坏或不可读取。"
                : document.isLocked ? @"此 PDF 已加密，请先在其他应用中解锁。"
                : pages == 0 ? @"此 PDF 没有可显示的页面。" : nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                GlowPDFContext *context = weakSelf;
                // A closed/replaced preview never receives a late loading result.
                if (!context || context.destroyed || context.loadGeneration != generation) return;
                if (failure) {
                    context.state = @"error";
                    context.error = failure;
                } else {
                    context.pdfView.document = document;
                    context.state = @"ready";
                    [context.pdfView layoutDocumentView];
                    [context command:context.fit ? @"fit" : @"zoom" value:context.requestedZoom];
                    [context command:@"page" value:context.requestedPage];
                    if (context.syncTarget) {
                        NSDictionary *target = context.syncTarget;
                        [context syncPage:[target[@"page"] unsignedIntegerValue] x:[target[@"x"] doubleValue]
                            y:[target[@"y"] doubleValue] width:[target[@"width"] doubleValue] height:[target[@"height"] doubleValue]];
                    }
                }
                [context updateControls];
            });
        }
    });
}

- (void)layout {
    if (self.destroyed) return;
    CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
    self.pdfView.frame = self.view.bounds;
    self.message.frame = NSMakeRect(16, fmax(40, height / 2 - 32), fmax(0, width - 32), 90);
}

- (void)updateControls {
    if (self.destroyed) return;
    BOOL ready = [self.state isEqualToString:@"ready"];
    self.pdfView.hidden = !ready;
    self.message.hidden = ready;
    self.message.stringValue = self.error.length ? self.error : @"正在加载 PDF…";
    NSUInteger pages = self.pdfView.document.pageCount;
    NSUInteger index = self.pdfView.currentPage ? [self.pdfView.document indexForPage:self.pdfView.currentPage] : NSNotFound;
    NSUInteger page = index == NSNotFound ? 0 : index + 1;
    self.pageField.stringValue = page ? [NSString stringWithFormat:@"%lu", (unsigned long)page] : @"—";
    self.pageField.enabled = ready;
    self.pageCount.stringValue = [NSString stringWithFormat:@"/ %lu", (unsigned long)pages];
    self.previousButton.enabled = ready && page > 1;
    self.nextButton.enabled = ready && page < pages;
    self.zoomLabel.stringValue = [NSString stringWithFormat:@"%.0f%%", self.pdfView.scaleFactor * 100];
}

- (void)command:(NSString *)action value:(double)value {
    if (self.destroyed) return;
    if ([action isEqualToString:@"focus"]) {
        if (!self.view.hidden) [self.view.window makeFirstResponder:self.pdfView];
    } else if ([action isEqualToString:@"blur"]) [self blur];
    else if ([action isEqualToString:@"reload"]) [self load];
    else if ([action isEqualToString:@"page"] && isfinite(value)) {
        self.requestedPage = (NSUInteger)fmin(1000000000, fmax(1, value));
        NSUInteger pages = self.pdfView.document.pageCount;
        if (pages) [self.pdfView goToPage:[self.pdfView.document pageAtIndex:MIN(pages, self.requestedPage) - 1]];
    } else if ([action isEqualToString:@"next"]) [self.pdfView goToNextPage:nil];
    else if ([action isEqualToString:@"previous"]) [self.pdfView goToPreviousPage:nil];
    else if ([action isEqualToString:@"zoom"] && isfinite(value)) {
        self.fit = NO;
        self.requestedZoom = fmin(5, fmax(0.25, value));
        self.pdfView.autoScales = NO;
        self.pdfView.scaleFactor = self.requestedZoom;
    } else if ([action isEqualToString:@"fit"]) {
        self.fit = YES;
        self.pdfView.autoScales = YES;
    }
    [self updateControls];
}
- (void)clearSyncHighlight {
    self.highlightGeneration++;
    if (self.syncAnnotation) [self.syncAnnotation.page removeAnnotation:self.syncAnnotation];
    self.syncAnnotation = nil;
}
- (void)syncPage:(NSUInteger)number x:(double)x y:(double)y width:(double)width height:(double)height {
    if (self.destroyed || !number || !isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height)) return;
    self.syncTarget = @{@"page": @(number), @"x": @(x), @"y": @(y), @"width": @(width), @"height": @(height)};
    self.requestedPage = number;
    if (![self.state isEqualToString:@"ready"] || number > self.pdfView.document.pageCount) return;
    PDFPage *page = [self.pdfView.document pageAtIndex:number - 1];
    NSPoint point = GlowPDFPointFromSync(page, x, y);
    NSRect marker = NSMakeRect(point.x, point.y, fmax(8, width), fmax(10, height));
    marker = NSIntersectionRect(marker, [page boundsForBox:kPDFDisplayBoxMediaBox]);
    [self clearSyncHighlight];
    PDFAnnotation *annotation = [[PDFAnnotation alloc] initWithBounds:marker forType:PDFAnnotationSubtypeSquare withProperties:nil];
    annotation.color = [NSColor.controlAccentColor colorWithAlphaComponent:0.45];
    annotation.interiorColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.13];
    PDFBorder *border = [[PDFBorder alloc] init]; border.lineWidth = 0.75; annotation.border = border;
    [page addAnnotation:annotation]; self.syncAnnotation = annotation;
    [self.pdfView goToRect:NSInsetRect(marker, -18, -24) onPage:page];
    [self updateControls];
    NSUInteger generation = self.highlightGeneration;
    __weak GlowPDFContext *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        GlowPDFContext *context = weakSelf;
        if (context && !context.destroyed && context.highlightGeneration == generation) [context clearSyncHighlight];
    });
}
- (void)inverseAtPoint:(NSPoint)point {
    if (self.destroyed || ![self.state isEqualToString:@"ready"]) return;
    PDFPage *page = [self.pdfView pageForPoint:point nearest:NO];
    if (!page) return;
    NSPoint pdfPoint = [self.pdfView convertPoint:point toPage:page];
    NSPoint sync = GlowPDFPointToSync(page, pdfPoint);
    NSUInteger index = [self.pdfView.document indexForPage:page];
    if (index == NSNotFound || !isfinite(sync.x) || !isfinite(sync.y) || sync.x < 0 || sync.y < 0) return;
    self.inverseSync = @{@"seq": @(++self.syncSequence), @"page": @(index + 1), @"x": @(sync.x), @"y": @(sync.y)};
    [self blur];
}
- (void)previous:(id)sender { (void)sender; [self command:@"previous" value:0]; }
- (void)next:(id)sender { (void)sender; [self command:@"next" value:0]; }
- (void)pageEntered:(id)sender { (void)sender; [self command:@"page" value:self.pageField.doubleValue]; }
- (void)zoomOut:(id)sender { (void)sender; [self command:@"zoom" value:self.pdfView.scaleFactor / 1.2]; }
- (void)zoomIn:(id)sender { (void)sender; [self command:@"zoom" value:self.pdfView.scaleFactor * 1.2]; }
- (void)fitPage:(id)sender { (void)sender; [self command:@"fit" value:0]; }
- (void)blur { if (self.parent) [self.view.window makeFirstResponder:self.parent]; }
- (void)destroy {
    if (self.destroyed) return;
    self.destroyed = YES;
    [self clearSyncHighlight];
    self.syncTarget = nil; self.inverseSync = nil;
    self.loadGeneration++;
    if (self.keyMonitor) [NSEvent removeMonitor:self.keyMonitor];
    if (self.pageObserver) [NSNotificationCenter.defaultCenter removeObserver:self.pageObserver];
    if (self.scaleObserver) [NSNotificationCenter.defaultCenter removeObserver:self.scaleObserver];
    self.keyMonitor = nil; self.pageObserver = nil; self.scaleObserver = nil;
    NSResponder *responder = self.view.window.firstResponder;
    if ([responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:self.view]) [self blur];
    self.pdfView.document = nil;
    self.view.hidden = YES;
    [self.view removeFromSuperview];
    self.view.context = nil;
    self.view = nil; self.pdfView = nil; self.parent = nil;
}
@end

void *glow_pdf_create(void *parent_nsview, const char *path) {
    if (!parent_nsview || !NSThread.isMainThread) return NULL;
    @autoreleasepool {
        GlowPDFContext *context = [[GlowPDFContext alloc] initWithParent:(__bridge NSView *)parent_nsview path:path];
        return (__bridge_retained void *)context;
    }
}
void glow_pdf_frame(void *handle, double x, double y, double width, double height) {
    if (!handle || !NSThread.isMainThread) return;
    @autoreleasepool {
        GlowPDFContext *context = (__bridge GlowPDFContext *)handle;
        if (context.destroyed || !context.parent) return;
        if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height) || width <= 0 || height <= 0) {
            context.view.hidden = YES; return;
        }
        NSRect bounds = context.parent.bounds;
        CGFloat originY = context.parent.isFlipped ? NSMinY(bounds) + y : NSMaxY(bounds) - y - height;
        context.view.frame = NSMakeRect(NSMinX(bounds) + x, originY, width, height);
        context.view.hidden = NO;
        [context.view setNeedsLayout:YES];
        [context.view layoutSubtreeIfNeeded];
    }
}
void glow_pdf_occlusion(void *handle, const double *rects, size_t count) {
    if (!handle || !NSThread.isMainThread) return;
    @autoreleasepool {
        GlowPDFContext *context = (__bridge GlowPDFContext *)handle;
        if (!context.destroyed) [context.view setOcclusions:rects count:count];
    }
}
void glow_pdf_command(void *handle, const char *action, double value) {
    if (!handle || !action || !NSThread.isMainThread) return;
    @autoreleasepool {
        GlowPDFContext *context = (__bridge GlowPDFContext *)handle;
        [context command:[NSString stringWithUTF8String:action] ?: @"" value:value];
    }
}
void glow_pdf_sync(void *handle, unsigned long long page, double x, double y, double width, double height) {
    if (!handle || !NSThread.isMainThread) return;
    @autoreleasepool { [(__bridge GlowPDFContext *)handle syncPage:(NSUInteger)page x:x y:y width:width height:height]; }
}
const char *glow_pdf_status(void *handle) {
    if (!handle || !NSThread.isMainThread) return strdup("{\"kind\":\"pdf\",\"state\":\"error\",\"error\":\"PDF unavailable\",\"page\":0,\"pages\":0,\"zoom\":1}");
    @autoreleasepool {
        GlowPDFContext *context = (__bridge GlowPDFContext *)handle;
        NSUInteger index = context.pdfView.currentPage ? [context.pdfView.document indexForPage:context.pdfView.currentPage] : NSNotFound;
        NSMutableDictionary *status = [@{@"kind": @"pdf", @"state": context.state ?: @"error", @"error": context.error ?: @"",
            @"page": @(index == NSNotFound ? 0 : index + 1), @"pages": @(context.pdfView.document.pageCount),
            @"zoom": @(context.pdfView.scaleFactor)} mutableCopy];
        if (context.closeRequested) status[@"close_requested"] = @YES;
        if (context.inverseSync) status[@"synctex"] = context.inverseSync;
        NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:NULL];
        NSString *text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : nil;
        return strdup(text.UTF8String ?: "{}");
    }
}
void glow_pdf_destroy(void *handle) {
    if (!handle || !NSThread.isMainThread) return;
    @autoreleasepool {
        GlowPDFContext *context = (__bridge_transfer GlowPDFContext *)handle;
        [context destroy];
    }
}
