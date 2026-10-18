// Focused macOS video check. Requires ffmpeg on PATH; fixture and executable are
// temporary. Does not measure external display/speaker latency or prove lip sync.
// xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Werror -mmacosx-version-min=11.0 \
//   tests/native_video.m src/native_preview/media.m -framework AppKit \
//   -framework AVKit -framework AVFoundation -framework QuartzCore \
//   -framework CoreMedia -framework CoreVideo -o /tmp/neovide-glow-video-test
// OS_ACTIVITY_MODE=disable /tmp/neovide-glow-video-test
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <QuartzCore/QuartzCore.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "../src/native_preview/media.h"

static void check(BOOL value, NSString *message) {
    if (!value) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        exit(1);
    }
}

static NSDictionary *status(void *ctx) {
    const char *raw = glow_media_status(ctx);
    check(raw != NULL, @"status allocation");
    NSData *data = [NSData dataWithBytes:raw length:strlen(raw)];
    free((void *)raw);
    NSDictionary *result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    check([result isKindOfClass:NSDictionary.class], @"valid status JSON");
    return result;
}

static BOOL waitFor(NSTimeInterval timeout, BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    do {
        if (condition()) return YES;
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    } while (deadline.timeIntervalSinceNow > 0);
    return condition();
}

static NSString *makeMP4(NSString *directory) {
    NSString *path = [directory stringByAppendingPathComponent:@"clock-test.mp4"];
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/usr/bin/env"];
    task.arguments = @[@"ffmpeg", @"-nostdin", @"-hide_banner", @"-loglevel", @"error", @"-y",
        @"-f", @"lavfi", @"-i", @"testsrc2=size=320x180:rate=30:duration=8",
        @"-f", @"lavfi", @"-i", @"sine=frequency=440:sample_rate=48000:duration=8",
        @"-c:v", @"libx264", @"-preset", @"ultrafast", @"-pix_fmt", @"yuv420p", @"-g", @"30",
        @"-c:a", @"aac", @"-b:a", @"96k", @"-ac", @"2", @"-movflags", @"+faststart", @"-shortest", path];
    check([task launchAndReturnError:nil], @"launch local fixture generation");
    [task waitUntilExit];
    check(task.terminationStatus == 0, @"generate H.264 + AAC MP4 fixture");
    return path;
}

static void checkEnabledTracks(AVPlayerItem *item) {
    NSUInteger audio = 0;
    NSUInteger video = 0;
    for (AVPlayerItemTrack *track in item.tracks) {
        if (!track.enabled) continue;
        if ([track.assetTrack.mediaType isEqualToString:AVMediaTypeAudio]) audio++;
        if ([track.assetTrack.mediaType isEqualToString:AVMediaTypeVideo]) video++;
    }
    check(audio == 1 && video == 1, @"one enabled audio track and one enabled video track");
}

// AVPlayerItemVideoOutput reports the actual decoded image's display timestamp.
// Request an image at AVPlayer.currentTime, so drift is measured against this
// same player's audio/video media clock rather than two independent decoders.
static double samplePlayback(AVPlayer *player, AVPlayerItemVideoOutput *output,
                             NSTimeInterval seconds, NSUInteger *sampleCount) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:seconds];
    double maxDrift = 0;
    CMTime previous = kCMTimeInvalid;
    while (deadline.timeIntervalSinceNow > 0) {
        CMTime clock = player.currentTime;
        if ([output hasNewPixelBufferForItemTime:clock]) {
            CMTime display = kCMTimeInvalid;
            CVPixelBufferRef pixel = [output copyPixelBufferForItemTime:clock itemTimeForDisplay:&display];
            if (pixel) {
                check(CVPixelBufferGetWidth(pixel) == 320 && CVPixelBufferGetHeight(pixel) == 180,
                      @"decoded frame dimensions");
                check(CMTIME_IS_NUMERIC(display), @"decoded frame has numeric timestamp");
                check(!CMTIME_IS_VALID(previous) || CMTimeCompare(display, previous) >= 0,
                      @"frame timestamps advance during playback");
                double drift = fabs(CMTimeGetSeconds(CMTimeSubtract(display, clock)));
                check(isfinite(drift) && drift < 0.12,
                      [NSString stringWithFormat:@"decoded frame is within 120 ms of shared clock (%.4f s)", drift]);
                maxDrift = fmax(maxDrift, drift);
                previous = display;
                (*sampleCount)++;
                CVPixelBufferRelease(pixel);
            }
        }
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
    return maxDrift;
}

int main(void) {
    @autoreleasepool {
        (void)NSApplication.sharedApplication;
        NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 400)
                                                     styleMask:NSWindowStyleMaskBorderless
                                                       backing:NSBackingStoreBuffered defer:NO];
        NSView *parent = window.contentView;
        NSUInteger baseline = parent.subviews.count;
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        check([NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES
                                                    attributes:nil error:nil], @"fixture directory");
        NSString *path = makeMP4(directory);
        NSUInteger beforeCount = 0;
        NSUInteger afterCount = 0;
        double beforeDrift = 0;
        double afterDrift = 0;
        __weak id releasedContext;
        __weak AVPlayer *releasedPlayer;
        __weak AVPlayerItem *releasedItem;
        @autoreleasepool {
            void *ctx = glow_media_create((__bridge void *)parent, path.UTF8String, true);
            check(ctx != NULL, @"video context");
            glow_media_frame(ctx, 0, 0, 640, 400);
            // KVC is used only by this native test; no production ABI is added.
            id context = (__bridge id)ctx;
            AVPlayer *player = [context valueForKey:@"player"];
            AVPlayerItem *item = [context valueForKey:@"item"];
            AVPlayerView *view = [context valueForKey:@"playerView"];
            releasedContext = context;
            releasedPlayer = player;
            releasedItem = item;
            check(view.player == player && view.superview.superview == parent && !view.hidden,
                  @"actual AVPlayerView is embedded and attached to the same player");
            AVPlayerItemVideoOutput *output = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{
                (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)
            }];
            output.suppressesPlayerRendering = NO;
            [item addOutput:output];
            check(waitFor(12, ^BOOL {
                return ![status(ctx)[@"state"] isEqualToString:@"loading"];
            }), @"video asynchronous preparation");
            check([status(ctx)[@"state"] isEqualToString:@"ready"],
                  [NSString stringWithFormat:@"MP4 ready: %@", status(ctx)]);
            checkEnabledTracks(item);
            // Muting the player avoids disturbing the user; the AAC track stays enabled.
            glow_media_command(ctx, "volume", 0);
            glow_media_command(ctx, "play", 0);
            check(waitFor(5, ^BOOL {
                return player.timeControlStatus == AVPlayerTimeControlStatusPlaying && view.isReadyForDisplay;
            }), @"native video first frame ready while playing");
            beforeDrift = samplePlayback(player, output, 1.5, &beforeCount);
            check(beforeCount >= 20, @"at least 20 decoded frames before seek");
            glow_media_command(ctx, "pause", 0);
            glow_media_command(ctx, "seek", 4.25);
            check(waitFor(4, ^BOOL {
                return fabs(CMTimeGetSeconds(player.currentTime) - 4.25) < 0.05;
            }), @"paused video seek reaches 4.25 seconds");
            check(waitFor(3, ^BOOL {
                CMTime display = kCMTimeInvalid;
                CVPixelBufferRef pixel = [output copyPixelBufferForItemTime:player.currentTime itemTimeForDisplay:&display];
                if (!pixel) return NO;
                CVPixelBufferRelease(pixel);
                return fabs(CMTimeGetSeconds(display) - 4.25) < 0.05;
            }), @"decoded frame follows seek target");
            glow_media_command(ctx, "play", 0);
            check(waitFor(3, ^BOOL { return player.timeControlStatus == AVPlayerTimeControlStatusPlaying; }),
                  @"video resumes after seek");
            afterDrift = samplePlayback(player, output, 1.5, &afterCount);
            check(afterCount >= 20, @"at least 20 decoded frames after seek");
            checkEnabledTracks(item);
            [item removeOutput:output];
            glow_media_destroy(ctx);
            check(parent.subviews.count == baseline && player.rate == 0 && !player.currentItem && !view.player,
                  @"destroy stops player, detaches item/view and removes native child");
        }
        check(waitFor(3, ^BOOL { return !releasedContext && !releasedPlayer && !releasedItem; }),
              @"context, player and item are released after close");
        check([NSFileManager.defaultManager removeItemAtPath:directory error:nil], @"fixture cleanup");
        printf("PASS native video H.264 + AAC: enabled audio/video tracks, native first frame, decoded frames %lu + %lu; max frame/shared-clock drift %.4f s / %.4f s (< 0.1200 s); seek 4.25 s; close stops/detaches/releases\n",
               (unsigned long)beforeCount, (unsigned long)afterCount, beforeDrift, afterDrift);
        puts("LIMIT: measures decoded frame timestamps against the same AVPlayer media clock; does not measure external speaker/display latency or human-perceived lip sync.");
    }
    return 0;
}
