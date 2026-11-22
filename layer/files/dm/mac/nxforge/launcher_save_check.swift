// NXForge: the game app has no settings window. Its settings come from NXForge.app (Play options, the in-game sidebar), saved as launcher.<VAR> in the app's
// preferences, and launcher.c starts straight into the game with them. Before it does, this runs upstream's cloud save check (SaveCheck in dm/mac/Launcher.swift,
// linked for it and for the microphone consent; its window is never opened): nothing is shown unless the cloud's file is slow to come or the two saves need the player's pick.
import Foundation

/// 2: start the game, 0: the player quit
@_cdecl("dm_mac_save_check")
public func dmMacSaveCheck() -> Int32 {
    fputs("launcher: no settings window (NXForge.app sets the choices); cloud save check\n", stderr)
    return SaveCheck.withoutWindow() ? 2 : 0
}
