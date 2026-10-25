// Screenshots and video of the game as it is presented (capture_mac.m; the Mac front end's Quick settings and Capture menu). Main thread; done comes on the main thread with the saved
// file's path, or with nil and a reason
#pragma once
#import <Foundation/Foundation.h>
void capture_screenshot(const char *game, void (^done)(NSString *path, NSString *err));
void capture_record_start(const char *game, void (^done)(NSString *path, NSString *err));   // done: when the recording could not start, or when it ends (capture_record_stop)
void capture_record_stop(void);
int capture_recording(void);
