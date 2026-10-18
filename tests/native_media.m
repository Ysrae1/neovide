// Native backend smoke check; uses a silent generated WAV and never opens a GUI.
// xcrun clang -fobjc-arc -fmodules -Wall -Wextra -Werror -mmacosx-version-min=11.0 \
//   tests/native_media.m src/native_preview/media.m -framework AppKit \
//   -framework AVKit -framework AVFoundation -framework QuartzCore -framework CoreMedia \
//   -o /tmp/neovide-glow-media-test && /tmp/neovide-glow-media-test
#import <AppKit/AppKit.h>
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
    check([result isKindOfClass:NSDictionary.class], @"valid JSON status");
    return result;
}

static BOOL waitFor(NSTimeInterval timeout, BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    do {
        if (condition()) return YES;
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    } while (deadline.timeIntervalSinceNow > 0);
    return condition();
}

static void little16(NSMutableData *data, uint16_t value) {
    uint16_t encoded = CFSwapInt16HostToLittle(value);
    [data appendBytes:&encoded length:2];
}

static void little32(NSMutableData *data, uint32_t value) {
    uint32_t encoded = CFSwapInt32HostToLittle(value);
    [data appendBytes:&encoded length:4];
}

static NSString *makeWAV(NSString *directory) {
    const uint32_t samples = 8000 * 3;
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:"RIFF" length:4];
    little32(data, 36 + samples * 2);
    [data appendBytes:"WAVEfmt " length:8];
    little32(data, 16);
    little16(data, 1);
    little16(data, 1);
    little32(data, 8000);
    little32(data, 16000);
    little16(data, 2);
    little16(data, 16);
    [data appendBytes:"data" length:4];
    little32(data, samples * 2);
    [data increaseLengthBy:samples * 2];
    NSString *path = [directory stringByAppendingPathComponent:@"silence.wav"];
    check([data writeToFile:path atomically:YES], @"write silent WAV fixture");
    return path;
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
        check([NSFileManager.defaultManager createDirectoryAtPath:directory
                                     withIntermediateDirectories:YES attributes:nil error:nil], @"fixture directory");
        NSString *path = makeWAV(directory);
        void *ctx = glow_media_create((__bridge void *)parent, path.UTF8String, false);
        check(ctx != NULL, @"audio context");
        check(parent.subviews.count == baseline + 1 && parent.subviews.lastObject.hidden, @"initially hidden child");
        glow_media_frame(ctx, 10, 20, 260, 180);
        NSView *child = parent.subviews.lastObject;
        check(!child.hidden && NSEqualRects(child.frame, NSMakeRect(10, 200, 260, 180)), @"top-left to AppKit frame conversion");
        glow_media_frame(ctx, NAN, 0, 260, 180);
        check(child.hidden, @"invalid frame hides view");
        glow_media_frame(ctx, 10, 20, 260, 180);
        check(waitFor(12, ^BOOL {
            return ![status(ctx)[@"state"] isEqualToString:@"loading"];
        }), @"asynchronous preparation finishes");
        check([status(ctx)[@"state"] isEqualToString:@"ready"], [NSString stringWithFormat:@"WAV ready: %@", status(ctx)]);
        check(fabs([status(ctx)[@"duration"] doubleValue] - 3) < 0.05, @"loaded duration");
        glow_media_command(ctx, "volume", -1);
        check([status(ctx)[@"volume"] doubleValue] == 0, @"volume lower clamp");
        glow_media_command(ctx, "volume", 2);
        check([status(ctx)[@"volume"] doubleValue] == 1, @"volume upper clamp");
        glow_media_command(ctx, "volume", NAN);
        check([status(ctx)[@"volume"] doubleValue] == 1, @"non-finite volume rejected");
        glow_media_command(ctx, "play", 0);
        check(waitFor(5, ^BOOL {
            return [status(ctx)[@"state"] isEqualToString:@"playing"]
                && [status(ctx)[@"position"] doubleValue] > 0.1;
        }), [NSString stringWithFormat:@"playback clock advances: %@", status(ctx)]);
        glow_media_command(ctx, "pause", 0);
        check([status(ctx)[@"state"] isEqualToString:@"paused"], @"pause state");
        glow_media_command(ctx, "seek", 1.25);
        check(waitFor(3, ^BOOL {
            return fabs([status(ctx)[@"position"] doubleValue] - 1.25) < 0.05;
        }), @"absolute paused seek");
        glow_media_command(ctx, "seek", -3);
        check(waitFor(3, ^BOOL {
            return [status(ctx)[@"position"] doubleValue] < 0.05;
        }), @"seek lower clamp");
        glow_media_command(ctx, "seek", 2.85);
        glow_media_command(ctx, "toggle", 0);
        check(waitFor(5, ^BOOL {
            return [status(ctx)[@"state"] isEqualToString:@"ended"];
        }), @"end notification");
        glow_media_command(ctx, "play", 0);
        check(waitFor(3, ^BOOL {
            return [status(ctx)[@"state"] isEqualToString:@"playing"]
                && [status(ctx)[@"position"] doubleValue] < 2;
        }), @"replay after end");
        glow_media_destroy(ctx);
        check(parent.subviews.count == baseline, @"destroy removes view");

        ctx = glow_media_create((__bridge void *)parent, "relative.wav", false);
        check([status(ctx)[@"state"] isEqualToString:@"error"], @"invalid path reports error");
        glow_media_destroy(ctx);
        NSString *missing = [directory stringByAppendingPathComponent:@"missing.mp4"];
        ctx = glow_media_create((__bridge void *)parent, missing.UTF8String, true);
        check(waitFor(12, ^BOOL {
            return [status(ctx)[@"state"] isEqualToString:@"error"];
        }), @"missing media asynchronous failure");
        check([status(ctx)[@"kind"] isEqualToString:@"video"], @"video context status kind");
        glow_media_destroy(ctx);
        for (int i = 0; i < 3; i++) {
            ctx = glow_media_create((__bridge void *)parent, path.UTF8String, false);
            glow_media_command(ctx, "play", 0);
            glow_media_destroy(ctx);
        }
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.3]];
        check(parent.subviews.count == baseline, @"loading cancellation does not resurrect view");
        check([NSFileManager.defaultManager removeItemAtPath:directory error:nil], @"fixture cleanup");
        puts("PASS native media: async WAV prepare, play/pause/seek/replay, volume bounds, frame conversion, errors, destroy during load");
    }
    return 0;
}
