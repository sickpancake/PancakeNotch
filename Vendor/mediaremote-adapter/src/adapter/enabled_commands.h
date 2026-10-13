// PancakeNotch patch (not part of upstream mediaremote-adapter, see VERSION).
// This file is licensed under the BSD 3-Clause License, like the rest of the adapter.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_ENABLED_COMMANDS_H
#define MEDIAREMOTEADAPTER_ADAPTER_ENABLED_COMMANDS_H

#import <Foundation/Foundation.h>

// Payload key: the MediaRemote command numbers the now playing app accepts
// right now, sorted (e.g. 4 = next track, 5 = previous track, 24 = change the
// playback position). Missing when unknown. During an ad, some players turn
// off skipping and seeking here even though they don't flag the ad.
extern NSString *kMRAEnabledCommands;

// The notifications MediaRemote posts when an app's commands change.
NSArray<NSString *> *enabledCommandsChangeNotifications(void);

// Asks MediaRemote which commands the now playing app accepts right now and
// calls `completion` on `queue` with their numbers, sorted. The array is nil
// when that's unknown (nothing registered, or the functions are missing).
void requestEnabledCommands(dispatch_queue_t queue,
                            void (^completion)(NSArray<NSNumber *> *enabled));

#endif // MEDIAREMOTEADAPTER_ADAPTER_ENABLED_COMMANDS_H
