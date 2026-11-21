// PancakeNotch patch (not part of upstream mediaremote-adapter, see VERSION).
// This file is licensed under the BSD 3-Clause License, like the rest of the adapter.

#import "adapter/enabled_commands.h"

#import <dlfcn.h>

NSString *kMRAEnabledCommands = @"enabledCommands";

typedef void *MROriginRef;
typedef MROriginRef (*MRMediaRemoteGetLocalOrigin_t)(void);
typedef void (*MRMediaRemoteGetSupportedCommandsForOrigin_t)(
    MROriginRef origin, dispatch_queue_t queue, void (^completion)(NSArray *));
typedef int (*MRMediaRemoteCommandInfoGetCommand_t)(id info);
typedef Boolean (*MRMediaRemoteCommandInfoGetEnabled_t)(id info);

static MRMediaRemoteGetLocalOrigin_t getLocalOrigin = NULL;
static MRMediaRemoteGetSupportedCommandsForOrigin_t getSupportedCommands = NULL;
static MRMediaRemoteCommandInfoGetCommand_t getCommand = NULL;
static MRMediaRemoteCommandInfoGetEnabled_t getEnabled = NULL;

static void loadFunctions(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      void *handle = dlopen("/System/Library/PrivateFrameworks/"
                            "MediaRemote.framework/MediaRemote",
                            RTLD_LAZY);
      if (handle == NULL) {
          return;
      }
      getLocalOrigin = dlsym(handle, "MRMediaRemoteGetLocalOrigin");
      getSupportedCommands =
          dlsym(handle, "MRMediaRemoteGetSupportedCommandsForOrigin");
      getCommand = dlsym(handle, "MRMediaRemoteCommandInfoGetCommand");
      getEnabled = dlsym(handle, "MRMediaRemoteCommandInfoGetEnabled");
    });
}

NSArray<NSString *> *enabledCommandsChangeNotifications(void) {
    return @[
        @"kMRMediaRemoteSupportedCommandsDidChangeNotification",
        @"kMRMediaRemotePlayerSupportedCommandsDidChangeNotification",
        @"kMRMediaRemoteOriginSupportedCommandsDidChangeNotification",
    ];
}

void requestEnabledCommands(dispatch_queue_t queue,
                            void (^completion)(NSArray<NSNumber *> *enabled)) {
    loadFunctions();
    if (!getLocalOrigin || !getSupportedCommands || !getCommand ||
        !getEnabled) {
        dispatch_async(queue, ^{
          completion(nil);
        });
        return;
    }
    getSupportedCommands(getLocalOrigin(), queue, ^(NSArray *commands) {
      if (commands.count == 0) {
          completion(nil);
          return;
      }
      NSMutableArray<NSNumber *> *enabled = [NSMutableArray array];
      for (id info in commands) {
          if (getEnabled(info)) {
              [enabled addObject:@(getCommand(info))];
          }
      }
      [enabled sortUsingSelector:@selector(compare:)];
      completion([enabled copy]);
    });
}
