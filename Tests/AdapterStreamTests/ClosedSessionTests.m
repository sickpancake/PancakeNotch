// Runs the production adapter stream against a fake MediaRemote source, without touching playback.
#import <AppKit/AppKit.h>
#import "adapter/globals.h"
#import "adapter/enabled_commands.h"
#import "adapter/keys.h"
#import "adapter/now_playing.h"

static NSMutableArray<NSDictionary *> *reports;
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
static NSMutableDictionary *trackConversion(NSDictionary *info, bool micros, bool now, bool noArt) {
    ++conversions;
    return convertNowPlayingInformation(info, micros, now, noArt);
}

static void captureOutput(NSString *line) {
    NSDictionary *message = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    [reports addObject:message[@"payload"]];
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
#ifndef ADAPTER_STREAM_SOURCE
#define ADAPTER_STREAM_SOURCE "adapter/stream.m"
#endif
#include ADAPTER_STREAM_SOURCE
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
        fprintf(stderr, "Adapter closed-session regressions passed\n");
        CFRunLoopStop(CFRunLoopGetMain());
        return;
    }
    ((dispatch_block_t)steps[index])();
    // Events posted by this step enter the serial queue before the next assertion.
    next(^{ runStep(index + 1); });
}
static void fakeRegister(dispatch_queue_t queue) {
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
        metadata = @{kMRMediaRemoteNowPlayingInfoTitle: @"Video A"};
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
