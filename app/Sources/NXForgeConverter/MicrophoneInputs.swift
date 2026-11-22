// The microphone input a game listens to, as a Play options row: the game's own settings window had this picker (launcher.DM_MIC_DEVICE,
// which dm/mac/launcher.c reads at launch), and NXForge's games have no such window from NXForge 0.55.1 on. It shows under Microphone
// while that is on; System Default stores nothing, so the game follows macOS's input.
import CoreAudio
import Foundation

extension LaunchSetting {
    init(env: String, kind: String, label: String, note: String, def: String, section: String?, needs: String?, level: String?, options: [[String]]?) {
        self.env = env; self.kind = kind; self.label = label; self.note = note; self.def = def
        self.section = section; self.needs = needs; self.level = level; self.options = options
        min = nil; max = nil; step = nil; on = nil; off = nil
    }
}

enum MicrophoneInputs {
    static let env = "DM_MIC_DEVICE"

    /// The input picker for a game whose list has Microphone (DM_MIC); `saved`: the game's stored choice, kept as a row while its device is away
    static func setting(saved: String?) -> LaunchSetting {
        var options = [["default", "System Default"]] + devices().map { [$0.uid, $0.name] }
        if let saved, saved != "default", !options.contains(where: { $0[0] == saved }) { options.append([saved, "Selected device unavailable"]) }
        return LaunchSetting(env: env, kind: "choice", label: "Microphone input", note: "", def: "default", section: "Controls",
                             needs: "DM_MIC=1", level: "basic", options: options)
    }

    static func devices() -> [(uid: String, name: String)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr,
              size >= UInt32(MemoryLayout<AudioDeviceID>.size) else { return [] }
        var ids = [AudioDeviceID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioDeviceID>.stride)
        let status = ids.withUnsafeMutableBytes { AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { return [] }
        return ids.compactMap { device -> (uid: String, name: String)? in
            guard hasInput(device), let uid = string(device, kAudioDevicePropertyDeviceUID), let name = string(device, kAudioObjectPropertyName), !uid.isEmpty else { return nil }
            return (uid, name)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func hasInput(_ device: AudioDeviceID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration, mScope: kAudioDevicePropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr, size >= UInt32(MemoryLayout<AudioBufferList>.size) else { return false }
        let data = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { data.deallocate() }
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, data) == noErr else { return false }
        return UnsafeMutableAudioBufferListPointer(data.assumingMemoryBound(to: AudioBufferList.self)).contains { $0.mNumberChannels > 0 }
    }

    private static func string(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(device, &address, 0, nil, &size, UnsafeMutableRawPointer($0)) }
        guard status == noErr, let value else { return nil }
        return value as String
    }
}
