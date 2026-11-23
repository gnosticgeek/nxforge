// Open NXForge at login (Settings › Theatre): the app registers itself as a login item with the system, which keeps the
// list (System Settings › General › Login Items), so nothing is saved in NXForge's own settings.
import ServiceManagement

enum LoginItem {
    static var on: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            FileHandle.standardError.write(Data("login item: \(error.localizedDescription)\n".utf8))
        }
    }
}
