#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include "media.h"

static void *GlowMediaItemStatusContext = &GlowMediaItemStatusContext;
static void *GlowMediaPlayerStatusContext = &GlowMediaPlayerStatusContext;

@class GlowMediaContext;

@interface GlowMediaView : NSView
@property(nonatomic, weak) GlowMediaContext *context;
@end

@interface GlowMediaContext : NSObject
@property(nonatomic, weak) NSView *parent;
@property(nonatomic, strong) GlowMediaView *view;
@property(nonatomic, strong) AVPlayerView *playerView;
@property(nonatomic, strong) AVPlayer *player;
@property(nonatomic, strong) AVPlayerItem *item;
@property(nonatomic, strong) NSButton *playButton;
@property(nonatomic, strong) NSSlider *seekSlider;
@property(nonatomic, strong) NSSlider *volumeSlider;
@property(nonatomic, strong) NSTextField *timeLabel;
@property(nonatomic, strong) NSTextField *titleLabel;
@property(nonatomic, strong) NSTextField *messageLabel;
@property(nonatomic, strong) NSTextField *volumeLabel;
@property(nonatomic, strong) NSTextField *audioSymbol;
@property(nonatomic, strong) id timeObserver;
@property(nonatomic, strong) id endObserver;
@property(nonatomic, strong) id failureObserver;
@property(nonatomic, strong) id keyMonitor;
@property(nonatomic, copy) NSString *lastError;
@property(nonatomic) BOOL video;
@property(nonatomic) BOOL ready;
@property(nonatomic) BOOL ended;
@property(nonatomic) BOOL destroyed;
@property(nonatomic) BOOL observingItem;
@property(nonatomic) BOOL observingPlayer;
@property(nonatomic) BOOL playRequested;
@property(nonatomic) BOOL userPaused;
@property(nonatomic) double pendingSeek;
- (instancetype)initWithParent:(NSView *)parent path:(const char *)path video:(BOOL)video;
- (void)layout;
- (void)updateControls;
- (void)performCommand:(NSString *)action value:(double)value;
- (NSDictionary *)status;
- (void)destroy;
- (void)blur;
@end

@implementation GlowMediaView
- (BOOL)isFlipped { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (void)layout {
    [super layout];
    [self.context layout];
}
@end

static NSTextField *GlowMediaLabel(NSString *text, CGFloat size) {
    NSTextField *field = [NSTextField labelWithString:text];
    field.font = [NSFont systemFontOfSize:size];
    field.lineBreakMode = NSLineBreakByTruncatingMiddle;
    field.selectable = NO;
    return field;
}

static double GlowMediaSeconds(CMTime time) {
    double value = CMTimeGetSeconds(time);
    return isfinite(value) && value > 0 ? value : 0;
}

static NSString *GlowMediaTime(double value) {
    unsigned long long total = (unsigned long long)fmax(0, value);
    if (total >= 3600) {
        return [NSString stringWithFormat:@"%llu:%02llu:%02llu", total / 3600,
                (total / 60) % 60, total % 60];
    }
    return [NSString stringWithFormat:@"%llu:%02llu", total / 60, total % 60];
}

// URL parsing does not inspect the filesystem. AVFoundation opens the asset and
// prepares its required metadata asynchronously after attaching the player item.
static NSURL *GlowMediaURL(const char *path, NSString **failure) {
    NSString *string = path ? [[NSString alloc] initWithUTF8String:path] : nil;
    if (!string.length) {
        *failure = @"媒体路径为空或不是有效的 UTF-8。";
        return nil;
    }
    if (string.isAbsolutePath) return [NSURL fileURLWithPath:string];
    NSURLComponents *components = [NSURLComponents componentsWithString:string];
    NSString *scheme = components.scheme.lowercaseString;
    NSURL *url = components.URL;
    if ([scheme isEqualToString:@"file"] && url.isFileURL && url.path.isAbsolutePath
        && (!url.host.length || [url.host isEqualToString:@"localhost"])) return url;
    if (([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])
        && components.host.length && url) return url;
    *failure = @"请使用本地媒体的绝对路径或有效的 http/https 地址。";
    return nil;
}

@implementation GlowMediaContext

- (instancetype)initWithParent:(NSView *)parent path:(const char *)path video:(BOOL)video {
    self = [super init];
    if (!self) return nil;
    _parent = parent;
    _video = video;
    _pendingSeek = NAN;
    _view = [[GlowMediaView alloc] initWithFrame:NSMakeRect(0, 0, 640, 360)];
    _view.context = self;
    _view.hidden = YES;
    _view.wantsLayer = YES;
    _view.layer.masksToBounds = YES;
    _view.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
    if (video) {
        _playerView = [[AVPlayerView alloc] initWithFrame:NSMakeRect(0, 0, 640, 268)];
        // Explicit controls remain visible for audio, narrow panes and video alike.
        _playerView.controlsStyle = AVPlayerViewControlsStyleNone;
        _playerView.videoGravity = AVLayerVideoGravityResizeAspect;
        _playerView.showsFullScreenToggleButton = NO;
        _playerView.showsSharingServiceButton = NO;
        [_view addSubview:_playerView];
    }

    _audioSymbol = GlowMediaLabel(@"♫", 56);
    _audioSymbol.alignment = NSTextAlignmentCenter;
    _audioSymbol.textColor = NSColor.secondaryLabelColor;
    _audioSymbol.hidden = video;
    [_view addSubview:_audioSymbol];
    _titleLabel = GlowMediaLabel(@"媒体预览", 14);
    _titleLabel.alignment = NSTextAlignmentCenter;
    [_view addSubview:_titleLabel];
    _messageLabel = GlowMediaLabel(@"正在加载…", 12);
    _messageLabel.alignment = NSTextAlignmentCenter;
    _messageLabel.lineBreakMode = NSLineBreakByTruncatingTail;
    _messageLabel.textColor = NSColor.secondaryLabelColor;
    [_view addSubview:_messageLabel];
    _playButton = [NSButton buttonWithTitle:@"播放" target:self action:@selector(togglePlayback:)];
    _playButton.bezelStyle = NSBezelStyleRounded;
    [_playButton setAccessibilityLabel:@"Play or pause media"];
    [_view addSubview:_playButton];
    _seekSlider = [NSSlider sliderWithValue:0 minValue:0 maxValue:1 target:self action:@selector(seekChanged:)];
    _seekSlider.continuous = YES;
    _seekSlider.enabled = NO;
    [_seekSlider setAccessibilityLabel:@"Playback position in seconds"];
    [_view addSubview:_seekSlider];
    _volumeSlider = [NSSlider sliderWithValue:1 minValue:0 maxValue:1 target:self action:@selector(volumeChanged:)];
    _volumeSlider.continuous = YES;
    [_volumeSlider setAccessibilityLabel:@"Playback volume"];
    [_view addSubview:_volumeSlider];
    _volumeLabel = GlowMediaLabel(@"音量", 11);
    [_view addSubview:_volumeLabel];
    _timeLabel = GlowMediaLabel(@"0:00 / --:--", 11);
    _timeLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightRegular];
    _timeLabel.alignment = NSTextAlignmentCenter;
    [_view addSubview:_timeLabel];
    [parent addSubview:_view];
    __weak GlowMediaContext *weakSelf = self;
    _keyMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown
        handler:^NSEvent *(NSEvent *event) {
            GlowMediaContext *context = weakSelf;
            NSView *view = context.view;
            if (!context || context.destroyed || view.hidden || event.window != view.window) return event;
            NSResponder *responder = view.window.firstResponder;
            if (![responder isKindOfClass:NSView.class] || ![(NSView *)responder isDescendantOf:view]) return event;
            NSEventModifierFlags modifiers = event.modifierFlags
                & (NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagControl | NSEventModifierFlagOption);
            if (event.keyCode == 48 && (modifiers == NSEventModifierFlagControl
                || modifiers == (NSEventModifierFlagControl | NSEventModifierFlagShift))) {
                // Give Neovim's gt/gT bindings this event after leaving native controls.
                [context blur];
                return event;
            }
            if (modifiers == NSEventModifierFlagCommand && event.keyCode == 53) {
                [context blur];
                return nil;
            }
            if (modifiers == (NSEventModifierFlagCommand | NSEventModifierFlagShift)) {
                NSString *key = event.charactersIgnoringModifiers;
                if (key && [@[@"[", @"]", @"{", @"}"] containsObject:key]) [context blur];
            }
            return event;
        }];

    NSString *failure = nil;
    NSURL *url = GlowMediaURL(path, &failure);
    if (!url) {
        _lastError = failure;
        [self updateControls];
        return self;
    }
    _titleLabel.stringValue = url.lastPathComponent.length ? url.lastPathComponent : url.host;
    _titleLabel.toolTip = url.isFileURL ? url.path : url.absoluteString;
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:@{
        AVURLAssetPreferPreciseDurationAndTimingKey: @YES
    }];
    _item = [AVPlayerItem playerItemWithAsset:asset automaticallyLoadedAssetKeys:@[@"playable", @"duration"]];
    _player = [AVPlayer playerWithPlayerItem:_item];
    _player.actionAtItemEnd = AVPlayerActionAtItemEndPause;
    _playerView.player = _player;
    _observingItem = YES;
    [_item addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
               context:GlowMediaItemStatusContext];
    _observingPlayer = YES;
    [_player addObserver:self forKeyPath:@"timeControlStatus" options:NSKeyValueObservingOptionNew
                 context:GlowMediaPlayerStatusContext];
    _timeObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 4)
                                                        queue:dispatch_get_main_queue() usingBlock:^(CMTime time) {
        (void)time;
        [weakSelf updateControls];
    }];
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    _endObserver = [center addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:_item
                                      queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        (void)notification;
        GlowMediaContext *context = weakSelf;
        if (!context || context.destroyed) return;
        context.ended = YES;
        context.playRequested = NO;
        [context updateControls];
    }];
    _failureObserver = [center addObserverForName:AVPlayerItemFailedToPlayToEndTimeNotification object:_item
                                          queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
        GlowMediaContext *context = weakSelf;
        if (!context || context.destroyed) return;
        NSError *error = notification.userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey];
        context.lastError = error.localizedDescription ?: @"媒体播放失败。";
        context.playRequested = NO;
        [context.player pause];
        [context updateControls];
    }];
    [self updateControls];
    return self;
}

- (void)layout {
    if (_destroyed) return;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    CGFloat margin = fmin(14, width / 16);
    CGFloat contentWidth = fmax(0, width - margin * 2);
    CGFloat barTop = fmax(0, height - 92);
    // AVKit's own unsupported-content indicator needs a nonzero layout even while
    // hidden; the outer view clips it safely when a split temporarily collapses.
    _playerView.frame = NSMakeRect(0, 0, fmax(64, width), fmax(64, barTop));
    _playerView.hidden = width < 64 || barTop < 64;
    CGFloat center = fmax(0, barTop / 2);
    _audioSymbol.frame = NSMakeRect(margin, fmax(0, center - 70), contentWidth, 70);
    _titleLabel.frame = NSMakeRect(margin, _video ? 7 : center + 6, contentWidth, 20);
    _titleLabel.hidden = _video && !_lastError.length;
    _messageLabel.frame = NSMakeRect(margin, barTop + 2, contentWidth, 18);
    _seekSlider.frame = NSMakeRect(margin, barTop + 22, contentWidth, 20);
    CGFloat row = barTop + 47;
    CGFloat playWidth = fmin(64, contentWidth * 0.23);
    _playButton.frame = NSMakeRect(margin, row, playWidth, 30);
    CGFloat volumeWidth = fmin(84, contentWidth * 0.25);
    CGFloat labelWidth = width >= 340 ? 42 : 0;
    _volumeLabel.hidden = labelWidth == 0;
    _volumeSlider.frame = NSMakeRect(width - margin - volumeWidth, row + 5, volumeWidth, 20);
    _volumeLabel.frame = NSMakeRect(width - margin - volumeWidth - labelWidth, row + 7, labelWidth, 16);
    CGFloat timeX = margin + playWidth + 6;
    CGFloat timeWidth = fmax(0, width - margin - volumeWidth - labelWidth - timeX - 6);
    _timeLabel.frame = NSMakeRect(timeX, row + 7, timeWidth, 18);
}

- (double)duration {
    return _ready ? GlowMediaSeconds(_item.duration) : 0;
}

- (NSString *)state {
    if (_lastError.length) return @"error";
    if (!_ready) return @"loading";
    if (_ended) return @"ended";
    if (_player.timeControlStatus == AVPlayerTimeControlStatusPlaying) return @"playing";
    if (_playRequested && _player.timeControlStatus == AVPlayerTimeControlStatusWaitingToPlayAtSpecifiedRate) return @"loading";
    return _userPaused ? @"paused" : @"ready";
}

- (void)updateControls {
    if (_destroyed) return;
    double duration = [self duration];
    double position = GlowMediaSeconds(_player.currentTime);
    _seekSlider.maxValue = fmax(duration, 1);
    _seekSlider.enabled = _ready && duration > 0 && !_lastError.length;
    _seekSlider.doubleValue = fmin(position, _seekSlider.maxValue);
    _volumeSlider.doubleValue = _player ? _player.volume : 1;
    _playButton.title = _playRequested ? @"暂停" : @"播放";
    _playButton.enabled = !_lastError.length;
    _volumeSlider.enabled = !_lastError.length;
    _timeLabel.stringValue = [NSString stringWithFormat:@"%@ / %@", GlowMediaTime(position),
                             duration > 0 ? GlowMediaTime(duration) : @"--:--"];
    NSString *state = [self state];
    _messageLabel.stringValue = _lastError.length ? _lastError :
        ([state isEqualToString:@"loading"] ? @"正在加载…" :
         ([state isEqualToString:@"ended"] ? @"播放结束" : @""));
    _messageLabel.toolTip = _lastError;
    _messageLabel.textColor = _lastError.length ? NSColor.systemRedColor : NSColor.secondaryLabelColor;
    [self.view setNeedsLayout:YES];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                       change:(NSDictionary<NSKeyValueChangeKey, id> *)change context:(void *)context {
    (void)keyPath;
    (void)object;
    (void)change;
    if (context != GlowMediaItemStatusContext && context != GlowMediaPlayerStatusContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    // AVFoundation can deliver status on its internal queue. Do not touch AppKit
    // there, and retain neither this context nor a destroyed view in late work.
    __weak GlowMediaContext *weakSelf = self;
    void (^update)(void) = ^{
        GlowMediaContext *contextObject = weakSelf;
        if (!contextObject || contextObject.destroyed) return;
        if (contextObject.item.status == AVPlayerItemStatusFailed && !contextObject.lastError.length) {
            contextObject.lastError = contextObject.item.error.localizedDescription ?: @"无法加载此媒体。";
            contextObject.playRequested = NO;
            [contextObject.player pause];
        } else if (!contextObject.ready && contextObject.item.status == AVPlayerItemStatusReadyToPlay) {
            contextObject.ready = YES;
            if (isfinite(contextObject.pendingSeek)) {
                double pendingSeek = contextObject.pendingSeek;
                contextObject.pendingSeek = NAN;
                [contextObject performCommand:@"seek" value:pendingSeek];
            }
            if (contextObject.playRequested) [contextObject.player play];
        }
        [contextObject updateControls];
    };
    // Defer even a main-thread notification: calling pause/play inside a status
    // observation can synchronously send another AVPlayer status notification.
    dispatch_async(dispatch_get_main_queue(), update);
}

- (void)togglePlayback:(id)sender {
    (void)sender;
    [self performCommand:@"toggle" value:0];
}

- (void)seekChanged:(NSSlider *)sender {
    [self performCommand:@"seek" value:sender.doubleValue];
}

- (void)volumeChanged:(NSSlider *)sender {
    [self performCommand:@"volume" value:sender.doubleValue];
}

- (void)performCommand:(NSString *)action value:(double)value {
    if (_destroyed) return;
    if ([action isEqualToString:@"blur"]) {
        [self blur];
        return;
    }
    if ([action isEqualToString:@"focus"]) {
        [self.view.window makeFirstResponder:_playButton];
        return;
    }
    if (_lastError.length) return;
    if ([action isEqualToString:@"toggle"]) action = _playRequested ? @"pause" : @"play";
    if ([action isEqualToString:@"play"]) {
        _playRequested = YES;
        _userPaused = NO;
        if (_ended) {
            _ended = NO;
            [_player seekToTime:kCMTimeZero toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        }
        if (_ready) [_player play];
    } else if ([action isEqualToString:@"pause"]) {
        _playRequested = NO;
        _userPaused = YES;
        [_player pause];
    } else if ([action isEqualToString:@"seek"] && isfinite(value)) {
        if (!_ready) {
            _pendingSeek = fmax(0, value);
        } else {
            double duration = [self duration];
            double position = fmax(0, duration > 0 ? fmin(duration, value) : value);
            _ended = duration > 0 && position >= duration;
            [_player seekToTime:CMTimeMakeWithSeconds(position, 600)
               toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero];
        }
    } else if ([action isEqualToString:@"volume"] && isfinite(value)) {
        _player.volume = (float)fmin(1, fmax(0, value));
    }
    [self updateControls];
}

- (NSDictionary *)status {
    NSMutableDictionary *result = [@{
        @"state": [self state],
        @"position": @(GlowMediaSeconds(_player.currentTime)),
        @"duration": @([self duration]),
        @"volume": @(_player ? _player.volume : 1),
        @"kind": _video ? @"video" : @"audio"
    } mutableCopy];
    if (_lastError.length) result[@"error"] = _lastError;
    return result;
}

- (void)blur {
    if (_view.window && _parent) [_view.window makeFirstResponder:_parent];
}

- (void)destroy {
    if (_destroyed) return;
    _destroyed = YES;
    _playRequested = NO;
    if (_keyMonitor) [NSEvent removeMonitor:_keyMonitor];
    _keyMonitor = nil;
    [_player pause];
    if (_timeObserver) [_player removeTimeObserver:_timeObserver];
    _timeObserver = nil;
    NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
    if (_endObserver) [center removeObserver:_endObserver];
    if (_failureObserver) [center removeObserver:_failureObserver];
    _endObserver = nil;
    _failureObserver = nil;
    if (_observingItem) [_item removeObserver:self forKeyPath:@"status" context:GlowMediaItemStatusContext];
    if (_observingPlayer) [_player removeObserver:self forKeyPath:@"timeControlStatus" context:GlowMediaPlayerStatusContext];
    _observingItem = NO;
    _observingPlayer = NO;
    [_item cancelPendingSeeks];
    [_item.asset cancelLoading];
    [_player replaceCurrentItemWithPlayerItem:nil];
    _playerView.player = nil;
    NSResponder *responder = _view.window.firstResponder;
    if ([responder isKindOfClass:NSView.class] && [(NSView *)responder isDescendantOf:_view]) {
        [_view.window makeFirstResponder:_parent];
    }
    _view.context = nil;
    [_view removeFromSuperview];
    _item = nil;
    _player = nil;
    _view = nil;
    _parent = nil;
}

@end

void *glow_media_create(void *parent_nsview, const char *path, bool video) {
    @autoreleasepool {
        if (!NSThread.isMainThread || !parent_nsview) return NULL;
        NSView *parent = (__bridge NSView *)parent_nsview;
        if (![parent isKindOfClass:NSView.class]) return NULL;
        GlowMediaContext *context = [[GlowMediaContext alloc] initWithParent:parent path:path video:video];
        return context ? (void *)CFBridgingRetain(context) : NULL;
    }
}

void glow_media_frame(void *ctx, double x, double y, double width, double height) {
    @autoreleasepool {
        if (!ctx || !NSThread.isMainThread) return;
        GlowMediaContext *context = (__bridge GlowMediaContext *)ctx;
        if (context.destroyed || !context.parent) return;
        if (!isfinite(x) || !isfinite(y) || !isfinite(width) || !isfinite(height)
            || width <= 0 || height <= 0) {
            context.view.hidden = YES;
            return;
        }
        NSRect bounds = context.parent.bounds;
        CGFloat bottom = context.parent.isFlipped ? bounds.origin.y + y : NSMaxY(bounds) - y - height;
        context.view.frame = NSMakeRect(bounds.origin.x + x, bottom, width, height);
        context.view.hidden = NO;
        [context.view setNeedsLayout:YES];
        [context.view layoutSubtreeIfNeeded];
    }
}

void glow_media_command(void *ctx, const char *action, double value) {
    @autoreleasepool {
        if (!ctx || !action || !NSThread.isMainThread) return;
        NSString *command = [[NSString alloc] initWithUTF8String:action];
        if (command) [(__bridge GlowMediaContext *)ctx performCommand:command value:value];
    }
}

const char *glow_media_status(void *ctx) {
    @autoreleasepool {
        NSDictionary *status;
        if (!NSThread.isMainThread || !ctx) {
            status = @{@"state": @"error", @"position": @0, @"duration": @0, @"volume": @0,
                       @"error": @"Media context must be accessed on the AppKit main thread."};
        } else {
            status = [(__bridge GlowMediaContext *)ctx status];
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:status options:0 error:nil];
        NSString *string = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : @"{\"state\":\"error\"}";
        return strdup(string.UTF8String);
    }
}

void glow_media_destroy(void *ctx) {
    @autoreleasepool {
        if (!ctx || !NSThread.isMainThread) return;
        GlowMediaContext *context = CFBridgingRelease(ctx);
        [context destroy];
    }
}
