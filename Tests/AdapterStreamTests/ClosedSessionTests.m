// Runs the production adapter stream against a fake MediaRemote source, without touching playback.
#import <AppKit/AppKit.h>
#import <ImageIO/ImageIO.h>
#import "adapter/globals.h"
#import "adapter/enabled_commands.h"
#import "adapter/keys.h"
#import "adapter/now_playing.h"

static NSMutableArray<NSDictionary *> *reports;
static NSDictionary *latestFullReport;
static NSDictionary *metadata;
static BOOL playing = YES;
static int playerPID;
static BOOL holdInfo;
static void (^heldInfo)(NSDictionary *);
static void (^supersededInfo)(NSDictionary *);
static BOOL holdStartup;
static void (^heldPID)(int);
static void (^heldPlaying)(bool);
static void (^heldClient)(id);
static NSUInteger conversions;
static NSUInteger closedReportCount;
static NSUInteger thumbnailDecodes;
static NSMutableDictionary *trackConversion(NSDictionary *info, bool micros, bool now, bool noArt) {
    ++conversions;
    return convertNowPlayingInformation(info, micros, now, noArt);
}

static void captureOutput(NSString *line) {
    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    [reports addObject:message[@"payload"]];
    if (![message[@"diff"] boolValue]) latestFullReport = message[@"payload"];
}

static CGImageRef countThumbnail(CGImageSourceRef source, size_t index, CFDictionaryRef options) {
    ++thumbnailDecodes;
    return CGImageSourceCreateThumbnailAtIndex(source, index, options);
}
@interface FakeApplication : NSObject
@end
@implementation FakeApplication
- (NSString *)bundleIdentifier { return @"test.browser"; }
- (pid_t)processIdentifier { return playerPID; }
@end
static bool fakeAppForPID(int pid, void (^block)(NSRunningApplication *)) {
    if (pid <= 0) return false;
    block((NSRunningApplication *)[FakeApplication new]);
    return true;
}
#define appForPID fakeAppForPID
#define printOutUnique captureOutput
#define convertNowPlayingInformation trackConversion
#define CGImageSourceCreateThumbnailAtIndex countThumbnail
#ifndef ADAPTER_STREAM_SOURCE
#define ADAPTER_STREAM_SOURCE "adapter/stream.m"
#endif
#include ADAPTER_STREAM_SOURCE
#undef CGImageSourceCreateThumbnailAtIndex
#undef convertNowPlayingInformation
#undef printOutUnique
#undef appForPID

MediaRemote *g_mediaRemote;
dispatch_queue_t g_serialdispatchQueue;
NSString *kMRAEnabledCommands = @"enabledCommands";
NSArray *enabledCommandsChangeNotifications(void) { return @[]; }
void requestEnabledCommands(dispatch_queue_t queue, void (^completion)(NSArray *)) { completion(@[]); }

static void fakePID(dispatch_queue_t queue, void (^done)(int)) {
    if (holdStartup) heldPID = [done copy]; else done(playerPID);
}
static void fakeClient(dispatch_queue_t queue, void (^done)(id)) {
    if (holdStartup) heldClient = [done copy]; else done(nil);
}
static void fakePlaying(dispatch_queue_t queue, void (^done)(bool)) {
    if (holdStartup) heldPlaying = [done copy]; else done(playing);
}
static void fakeInfo(dispatch_queue_t queue, void (^done)(NSDictionary *)) {
    if (holdInfo) { heldInfo = [done copy]; holdInfo = NO; } else { done(metadata); }
}
static void fakeUnregister(void) {}
static void check(BOOL condition, NSString *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static void post(NSString *name, NSDictionary *info) {
    [[NSNotificationCenter defaultCenter] postNotificationName:name object:nil userInfo:info];
}
static void next(dispatch_block_t block) { dispatch_async(g_serialdispatchQueue, block); }
static void postPlayback(void) {
    post(kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification,
         @{kMRMediaRemoteNowPlayingApplicationPIDUserInfoKey: @(playerPID),
           kMRMediaRemoteNowPlayingApplicationIsPlayingUserInfoKey: @(playing)});
}
static NSArray *steps;
static void runStep(NSUInteger index) {
    if (index == steps.count) {
        fprintf(stderr, "Adapter stream regressions passed\n");
        CFRunLoopStop(CFRunLoopGetMain());
        return;
    }
    ((dispatch_block_t)steps[index])();
    // Events posted by this step enter the serial queue before the next assertion.
    next(^{ runStep(index + 1); });
}

static NSData *artworkFixture(size_t width, size_t height) {
    NSMutableData *pixels = [NSMutableData dataWithLength:width * height * 4];
    uint32_t state = 1;
    uint32_t *values = pixels.mutableBytes;
    for (size_t i = 0; i < width * height; ++i) {
        state ^= state << 13;
        state ^= state >> 17;
        state ^= state << 5;
        values[i] = state;
    }
    CGDataProviderRef provider = CGDataProviderCreateWithCFData((__bridge CFDataRef)pixels);
    CGColorSpaceRef color = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGImageRef image = CGImageCreate(width, height, 8, 32, width * 4, color,
        kCGImageAlphaLast | kCGBitmapByteOrder32Big, provider, NULL, false, kCGRenderingIntentDefault);
    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData(
        (__bridge CFMutableDataRef)data, CFSTR("public.png"), 1, NULL);
    CGImageDestinationAddImage(destination, image, NULL);
    check(CGImageDestinationFinalize(destination), @"PNG fixture encoded");
    CFRelease(destination);
    CGImageRelease(image);
    CGColorSpaceRelease(color);
    CGDataProviderRelease(provider);
    return data;
}

static void postQueueChange(void) {
    post(kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification, nil);
}

static NSArray *artworkSteps(void) {
    NSData *large = metadata[kMRMediaRemoteNowPlayingInfoArtworkData];
    NSData *invalid = [NSMutableData dataWithLength:600 * 1024];
    NSData *small = artworkFixture(32, 16);
    return @[
        ^{
            NSString *encoded = latestFullReport[kMRAArtworkData];
            check(encoded != nil && [latestFullReport[kMRAArtworkMimeType] isEqual:@"image/png"], @"full snapshot has PNG artwork");
            NSData *preview = [[NSData alloc] initWithBase64EncodedString:encoded options:0];
            check(preview.length > 0 && preview.length < large.length, @"preview is smaller than the original");
            CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)preview, NULL);
            check(source != NULL, @"preview format is supported");
            CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
            check(image != NULL && CGImageGetWidth(image) == 256 && CGImageGetHeight(image) == 128,
                  @"preview keeps aspect ratio");
            check(CGImageGetAlphaInfo(image) != kCGImageAlphaNone &&
                  CGImageGetAlphaInfo(image) != kCGImageAlphaNoneSkipLast &&
                  CGImageGetAlphaInfo(image) != kCGImageAlphaNoneSkipFirst, @"preview keeps alpha");
            CGImageRelease(image);
            CFRelease(source);
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video A", kMRMediaRemoteNowPlayingInfoElapsedTime: @1,
                kMRMediaRemoteNowPlayingInfoArtworkData: [NSData dataWithBytes:large.bytes length:large.length]};
            postQueueChange();
        },
        ^{
            check([reports.lastObject[@"elapsedTime"] isEqual:@1] && reports.lastObject[kMRAArtworkData] == nil &&
                  thumbnailDecodes == 1, @"byte-identical artwork is reused and omitted in the diff");
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video A", kMRMediaRemoteNowPlayingInfoElapsedTime: @2};
            postQueueChange();
        },
        ^{
            check([reports.lastObject[@"elapsedTime"] isEqual:@2] && reports.lastObject[kMRAArtworkData] == nil &&
                  thumbnailDecodes == 1, @"temporarily missing artwork for the same item is retained");
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video A", kMRMediaRemoteNowPlayingInfoArtworkData: invalid,
                         kMRMediaRemoteNowPlayingInfoArtworkMIMEType: @"image/example"};
            postQueueChange();
        },
        ^{
            check([reports.lastObject[kMRAArtworkData] isEqual:[invalid base64EncodedStringWithOptions:0]] &&
                  [reports.lastObject[kMRAArtworkMimeType] isEqual:@"image/example"], @"unsupported artwork passes through");
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video A", kMRMediaRemoteNowPlayingInfoArtworkData: [NSNull null]};
            postQueueChange();
        },
        ^{
            check(reports.lastObject[kMRAArtworkData] == [NSNull null], @"explicit artwork removal stays a null diff");
            holdInfo = YES;
            postQueueChange();
        },
        ^{
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video B"};
            postQueueChange();
        },
        ^{
            check([latestFullReport[kMRATitle] isEqual:@"Video B"] && latestFullReport[kMRAArtworkData] == nil,
                  @"track change publishes a complete snapshot without the old image");
            check(heldInfo != nil, @"previous artwork request is pending");
            heldInfo(@{kMRMediaRemoteNowPlayingInfoTitle: @"Video A", kMRMediaRemoteNowPlayingInfoArtworkData: large});
            check([latestFullReport[kMRATitle] isEqual:@"Video B"] && thumbnailDecodes == 1,
                  @"late artwork for the previous track is ignored");
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video B", kMRMediaRemoteNowPlayingInfoArtworkData: small};
            postQueueChange();
        },
        ^{
            check([reports.lastObject[kMRAArtworkData] isEqual:[small base64EncodedStringWithOptions:0]] &&
                  thumbnailDecodes == 1, @"small artwork passes through");
            metadata = @{};
            postPlayback();
        },
        ^{
            check(latestFullReport.count == 0, @"browser tab closure clears title and artwork");
        }
    ];
}

static void fakeRegister(dispatch_queue_t queue) {
    if (getenv("ADAPTER_TEST_ARTWORK") != NULL) {
        steps = artworkSteps();
        next(^{ runStep(0); });
        return;
    }
    if (holdStartup) {
        steps = @[
            ^{
                check(heldPID && heldPlaying && heldClient && heldInfo, @"all startup reads are pending");
                supersededInfo = heldInfo;
                holdInfo = YES;
                post(kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification, nil);
            },
            ^{
                supersededInfo(@{kMRMediaRemoteNowPlayingInfoTitle: @"Older pending video"});
                check(conversions == 0, @"superseded metadata reply ignored while newest read is pending");
                // This notification takes resetAll + handle without starting a new info read.
                post(kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification, nil);
            },
            ^{
                closedReportCount = reports.count;
                check(reports.lastObject.count == 0, @"closed session publishes nothing playing");
                heldInfo(@{kMRMediaRemoteNowPlayingInfoTitle: @"Closed video"});
                check(conversions == 0, @"retired metadata must not be accepted into the cache");
            },
            ^{
                heldPID(playerPID);
                check(reports.count == closedReportCount, @"retired PID callback must be ignored");
            },
            ^{
                heldPlaying(YES);
                check(reports.count == closedReportCount, @"retired playback callback must be ignored");
            },
            ^{
                heldClient(nil);
                check(reports.count == closedReportCount, @"retired parent callback must be ignored");
                check(reports.lastObject.count == 0, @"closed video cannot return after late startup callbacks");
            }
        ];
        next(^{ runStep(0); });
        return;
    }
    steps = @[
        ^{
            check([reports.lastObject[@"title"] isEqual:@"Video A"], @"initial video");
            playing = NO;
            postPlayback();
        },
        ^{
            check([reports.lastObject[@"title"] isEqual:@"Video A"], @"pause retains loaded video");
            check([reports.lastObject[@"playing"] isEqual:@NO], @"pause stops playback");
            // The browser stays alive; only its loaded media disappears.
            metadata = @{};
            postPlayback();
        },
        ^{
            check(reports.lastObject.count == 0, @"playback event rechecks cached title");
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video B"};
            playing = YES;
            post(kMRMediaRemoteNowPlayingApplicationDidChangeNotification, nil);
        },
        ^{
            check([reports.lastObject[@"title"] isEqual:@"Video B"], @"new session is shown");
            metadata = @{};
            post(kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification, nil);
        },
        ^{
            check(reports.lastObject.count == 0, @"queue removal clears cached title");
            holdInfo = YES;
            post(kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification, nil);
        },
        ^{
            check(heldInfo != nil, @"old metadata read is in flight");
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video C"};
            post(kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification, nil);
        },
        ^{
            check([reports.lastObject[@"title"] isEqual:@"Video C"], @"another tab takes over");
            heldInfo(@{kMRMediaRemoteNowPlayingInfoTitle: @"Video B"});
            check([reports.lastObject[@"title"] isEqual:@"Video C"], @"older metadata cannot overwrite newer reply");
            holdInfo = YES;
            post(kMRMediaRemoteNowPlayingPlaybackQueueDidChangeNotification, nil);
        },
        ^{
            metadata = @{}; playerPID = 0; playing = NO;
            post(kMRMediaRemoteNowPlayingApplicationDidChangeNotification, nil);
        },
        ^{
            check(reports.lastObject.count == 0, @"session removal clears title without browser quit");
            heldInfo(@{kMRMediaRemoteNowPlayingInfoTitle: @"Video C"});
            check(reports.lastObject.count == 0, @"late callback cannot resurrect closed video");
        }
    ];
    next(^{ runStep(0); });
}
@interface FakeRemote : NSObject
@end
@implementation FakeRemote
- (MRMediaRemoteGetNowPlayingApplicationPID_t)getNowPlayingApplicationPID { return fakePID; }
- (MRMediaRemoteGetNowPlayingClient_t)getNowPlayingClient { return fakeClient; }
- (MRMediaRemoteGetNowPlayingApplicationIsPlaying_t)getNowPlayingApplicationIsPlaying { return fakePlaying; }
- (MRMediaRemoteGetNowPlayingInfo_t)getNowPlayingInfo { return fakeInfo; }
- (MRMediaRemoteRegisterForNowPlayingNotifications_t)registerForNowPlayingNotifications { return fakeRegister; }
- (MRMediaRemoteUnregisterForNowPlayingNotifications_t)unregisterForNowPlayingNotifications { return fakeUnregister; }
@end
int main(void) {
    @autoreleasepool {
        reports = [NSMutableArray array];
        if (getenv("ADAPTER_TEST_ARTWORK") != NULL) {
            NSData *artwork = artworkFixture(768, 384);
            check(artwork.length >= 512 * 1024 && artwork.length <= 3 * 1024 * 1024, @"fixture crosses the byte threshold");
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video A", kMRMediaRemoteNowPlayingInfoArtworkData: artwork};
        } else {
            metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video A"};
        }
        playerPID = getpid();
        holdStartup = getenv("ADAPTER_TEST_RETIRED_FIELDS") != NULL;
        holdInfo = holdStartup;
        g_serialdispatchQueue = dispatch_queue_create("adapter-test", DISPATCH_QUEUE_SERIAL);
        g_mediaRemote = (MediaRemote *)[FakeRemote new];
        // A timeout turns a missing notification handler into a failure, rather than a hanging test.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC), dispatch_get_global_queue(0, 0), ^{ exit(2); });
        adapter_stream();
    }
    return 0;
}
