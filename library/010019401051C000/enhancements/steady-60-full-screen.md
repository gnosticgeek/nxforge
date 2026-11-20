---
nxforge_enhancement: 1
name: "Steady 60 in full screen"
title_id: "010019401051C000"
on: false
source: "NXForge"
---
# Steady 60 in full screen

Runs a ProMotion screen at a fixed 60 Hz while the game is in full screen, so no frame stays up a refresh too long (fewer 57-59 fps dips in matches).

In full screen on a 120 Hz ProMotion screen, macOS shows about 1 to 3 frames in 100 one 120 Hz refresh late during matches (25 ms
instead of 16.7 ms), although the game has plenty of headroom (GPU about 5 ms a frame). A window does not do this. A fixed 60 Hz
mode paces every frame on a refresh. Best started in full screen (Display mode: Fullscreen): switching the screen's mode mid-game
can cost a hitch. Turn it off if the screen flickers when it switches.

```env
DM_SCREEN_MATCH=1
```
