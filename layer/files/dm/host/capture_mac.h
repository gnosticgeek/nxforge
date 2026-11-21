// Screenshots and video of the game as it is presented (capture_mac.m; the Mac front end's Quick settings and Capture menu). Main thread; done comes on the main thread with the saved
// file's path, or with nil and a reason
#pragma once
#import <Foundation/Foundation.h>
void capture_screenshot(const char *game, void (^done)(NSString *path, NSString *err));
void capture_picture_to(NSString *path, size_t height, void (^done)(NSString *path, NSString *err));   // the next frame as a picture height pixels tall (16:9) at path: .png, or .jpg
void capture_record_start(const char *game, void (^done)(NSString *path, NSString *err));   // done: when the recording could not start, or when it ends (capture_record_stop)
void capture_record_stop(void);
int capture_recording(void);
NSString *capture_folder(int video);     // where the next screenshot (0) or recording (1) goes
void capture_folder_set(NSString *dir);  // a folder the player chose for both, nil for the default (Screenshots / Recordings in the game folder)
// Instant replay (NXForge): while on, the last 30 s of the game as presented stay in memory, encoded; save writes them to a movie in the Recordings folder (done as above)
int capture_replay_set(int on);   // what it is now (0 when it could not be set up)
int capture_replay_on(void);
void capture_replay_save(const char *game, void (^done)(NSString *path, NSString *err));
