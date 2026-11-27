// SPDX-License-Identifier: GPL-2.0-or-later
// NXForge's Dolphin bridge (wii/README.md): Dolphin built as one library (nxdolphin.dylib) that draws into a view of the
// Wii player's window with Metal and takes its input from the player. Started from RetroReplay's DolphinBridge.mm
// (RetroReplay c526a993, same author, GPL-2.0-or-later like Dolphin); NXForge adds save states to a file, live picture
// settings, screenshots, a frame count and the Wii Remote held sideways.
// All ABI calls run on the macOS main thread. Emulation callbacks only touch atomics.
#import <AppKit/AppKit.h>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <memory>
#include <thread>
#include <mutex>
#include <string>
#include "Common/Config/Config.h"
#include "Common/FileUtil.h"
#include "Common/MathUtil.h"
#include "Common/MsgHandler.h"
#include "Common/WindowSystemInfo.h"
#include "Core/Boot/Boot.h"
#include "Core/BootManager.h"
#include "Core/Config/MainSettings.h"
#include "Core/Config/GraphicsSettings.h"
#include "Core/Core.h"
#include "Core/State.h"
#include "Core/ConfigManager.h"
#include "Core/Host.h"
#include "Core/System.h"
#include "Core/HW/GCPad.h"
#include "Core/HW/GCPadEmu.h"
#include "Core/HW/SI/SI_Device.h"
#include "Core/HW/Wiimote.h"
#include "Core/HW/WiimoteEmu/Extension/Nunchuk.h"
#include "Core/HW/WiimoteEmu/ExtensionPort.h"
#include "Core/HW/WiimoteEmu/WiimoteEmu.h"
#include "Core/Config/WiimoteSettings.h"
#include "InputCommon/ControllerEmu/ControlGroup/Attachments.h"
#include "InputCommon/ControllerEmu/StickGate.h"
#include "InputCommon/InputConfig.h"
#include "UICommon/UICommon.h"
#include "VideoCommon/Present.h"
#include "VideoCommon/VideoBackendBase.h"
#include "VideoCommon/VideoConfig.h"
#include "VideoCommon/VideoEvents.h"
#include "VideoCommon/FrameDumper.h"

namespace {
bool initialized = false;
std::atomic<bool> stop_requested{false};
std::atomic<uint64_t> frames{0};
// 0-17 are GameCube controls; 18 Select, 19 L3 and 20 R3 only reach the Wii Remote.
constexpr int CONTROLS = 21;
std::array<std::array<std::atomic<double>, CONTROLS>, 2> inputs{};
// Wii pointer, -1...1 with +y up. The right stick moves it relatively; the mouse sets it.
std::array<std::atomic<double>, 2> pointer_x{}, pointer_y{};
std::array<std::atomic<bool>, 2> mouse_button{};  // Left and right click over the game, port 1.
// How the Wii Remote is held (nxdolphin_set NXD_REMOTE): 0 upright with a Nunchuk, 1 sideways, 2 upright alone.
std::atomic<int> remote_style{0};
// Where the game's saves go (nxdolphin_save_root): the Wii's NAND in Wii/, the GameCube's memory cards in GC/; "" is Dolphin's own place in the user folder.
std::string save_root;
std::chrono::steady_clock::time_point last_tick;
void* render_view = nullptr;
NSPoint last_mouse{NAN, NAN};
Common::EventHook frame_hook;
std::mutex error_mutex;
std::string last_error;
void Error(const std::string& message) {
  std::lock_guard lock(error_mutex);
  last_error = message;
}
bool Alert(const char*, const char* text, bool, Common::MsgType type) {
  // Decline questions rather than silently accepting destructive emulation operations.
  if (type == Common::MsgType::Critical || type == Common::MsgType::Warning)
    Error(text);
  fprintf(stderr, "Dolphin: %s\n", text);
  return false;
}
std::optional<double> Input(int port, std::string_view group, std::string_view name) {
  int id = -1;
  if (group == GCPad::BUTTONS_GROUP) {
    constexpr std::array names{"A", "B", "X", "Y", "Z", "Start"};
    for (int i = 0; i < 6; ++i) if (name == names[i]) id = i;
  } else if (group == GCPad::DPAD_GROUP) {
    constexpr std::array names{"Up", "Down", "Left", "Right"};
    for (int i = 0; i < 4; ++i) if (name == names[i]) id = i + 6;
  } else if (group == GCPad::TRIGGERS_GROUP) {
    constexpr std::array names{"L", "R", "L-Analog", "R-Analog"};
    for (int i = 0; i < 4; ++i) if (name == names[i]) id = i + 10;
  } else if (group == GCPad::MAIN_STICK_GROUP) {
    if (name == "X") id = 14;
    if (name == "Y") id = 15;
  } else if (group == GCPad::C_STICK_GROUP) {
    if (name == "X") id = 16;
    if (name == "Y") id = 17;
  }
  // Suppress Dolphin's default keyboard bindings: the player owns input routing.
  return id < 0 ? 0.0 : inputs[port][id].load();
}
bool Held(int port, int id) { return inputs[port][id].load() > 0.5; }
// Shake is not overridable in Dolphin, so a held shake replaces the accelerometer with a swing
// along X. Unheld, the emulated motion (gravity at rest) is left untouched.
std::optional<double> Shake(int port, std::string_view name) {
  if (!Held(port, 4)) return std::nullopt;
  if (name != ControllerEmu::ReshapableInput::X_INPUT_OVERRIDE) return std::nullopt;
  const double t = std::chrono::duration<double>(
      std::chrono::steady_clock::now().time_since_epoch()).count();
  return std::sin(t * 2 * M_PI * 8) * 3 * MathUtil::GRAVITY_ACCELERATION;
}
// RetroPad layout on a Wii Remote held upright with a Nunchuk: A/B/X/Y are A/B/1/2,
// Start +, Select -, L3 Home, R shakes, L Nunchuk Z, R2 Nunchuk C, left stick the Nunchuk
// stick and right stick the pointer (R3 recentres it).
std::optional<double> WiimoteInput(int port, std::string_view group, std::string_view name) {
  using W = WiimoteEmu::Wiimote;
  if (remote_style == 1) {
    // Held sideways (the NES-pad grip): the pad's right-hand buttons are 2 and 1, its D-pad turns a quarter.
    if (group == W::BUTTONS_GROUP) {
      if (name == W::TWO_BUTTON) return Held(port, 0) || (port == 0 && mouse_button[0]) ? 1.0 : 0.0;
      if (name == W::ONE_BUTTON) return Held(port, 1) || (port == 0 && mouse_button[1]) ? 1.0 : 0.0;
      if (name == W::A_BUTTON) return inputs[port][2].load();
      if (name == W::B_BUTTON) return std::max(inputs[port][3].load(), inputs[port][10].load());
      if (name == W::PLUS_BUTTON) return inputs[port][5].load();
      if (name == W::MINUS_BUTTON) return inputs[port][18].load();
      if (name == W::HOME_BUTTON) return inputs[port][19].load();
      return 0.0;
    }
    if (group == W::DPAD_GROUP) {
      // screen up/down/left/right are the remote's right/left/up/down; the left stick works as a D-pad too
      const double sx = inputs[port][14].load(), sy = inputs[port][15].load();
      const bool up = Held(port, 6) || sy > 0.5, down = Held(port, 7) || sy < -0.5;
      const bool left = Held(port, 8) || sx < -0.5, right = Held(port, 9) || sx > 0.5;
      if (name == "Up") return left ? 1.0 : 0.0;
      if (name == "Down") return right ? 1.0 : 0.0;
      if (name == "Left") return down ? 1.0 : 0.0;
      if (name == "Right") return up ? 1.0 : 0.0;
      return 0.0;
    }
  }
  if (group == W::BUTTONS_GROUP) {
    if (name == W::A_BUTTON) return Held(port, 0) || (port == 0 && mouse_button[0]) ? 1.0 : 0.0;
    if (name == W::B_BUTTON) return Held(port, 1) || (port == 0 && mouse_button[1]) ? 1.0 : 0.0;
    if (name == W::ONE_BUTTON) return inputs[port][2].load();
    if (name == W::TWO_BUTTON) return inputs[port][3].load();
    if (name == W::PLUS_BUTTON) return inputs[port][5].load();
    if (name == W::MINUS_BUTTON) return inputs[port][18].load();
    if (name == W::HOME_BUTTON) return inputs[port][19].load();
    return 0.0;
  }
  if (group == W::DPAD_GROUP) {
    constexpr std::array names{"Up", "Down", "Left", "Right"};
    for (int i = 0; i < 4; ++i) if (name == names[i]) return inputs[port][i + 6].load();
    return 0.0;
  }
  if (group == W::IR_GROUP) {
    if (name == ControllerEmu::ReshapableInput::X_INPUT_OVERRIDE) return pointer_x[port].load();
    if (name == ControllerEmu::ReshapableInput::Y_INPUT_OVERRIDE) return pointer_y[port].load();
    return std::nullopt;
  }
  if (group == W::ACCELEROMETER_GROUP) return Shake(port, name);
  return std::nullopt;
}
std::optional<double> NunchukInput(int port, std::string_view group, std::string_view name) {
  using N = WiimoteEmu::Nunchuk;
  if (group == N::BUTTONS_GROUP) {
    if (name == N::Z_BUTTON) return inputs[port][10].load();
    if (name == N::C_BUTTON) return inputs[port][11].load();
    return 0.0;
  }
  if (group == N::STICK_GROUP) {
    if (name == ControllerEmu::ReshapableInput::X_INPUT_OVERRIDE) return inputs[port][14].load();
    if (name == ControllerEmu::ReshapableInput::Y_INPUT_OVERRIDE) return inputs[port][15].load();
    return std::nullopt;
  }
  if (group == N::ACCELEROMETER_GROUP) return Shake(port, name);
  return std::nullopt;
}
void ConfigureWiimotes() {
  for (int port = 0; port < 4; ++port)
    Config::SetCurrent(Config::GetInfoForWiimoteSource(port),
                       port < 2 ? WiimoteSource::Emulated : WiimoteSource::None);
  Config::SetCurrent(Config::WIIMOTE_BB_SOURCE, WiimoteSource::None);
  for (int port = 0; port < 2; ++port) {
    auto* wiimote = static_cast<WiimoteEmu::Wiimote*>(Wiimote::GetConfig()->GetController(port));
    wiimote->SetInputOverrideFunction([port](std::string_view group, std::string_view name, double) {
      return WiimoteInput(port, group, name);
    });
    auto* attachments = static_cast<ControllerEmu::Attachments*>(
        wiimote->GetWiimoteGroup(WiimoteEmu::WiimoteGroup::Attachments));
    attachments->SetSelectedAttachment(remote_style == 0 ? WiimoteEmu::ExtensionNumber::NUNCHUK
                                                         : WiimoteEmu::ExtensionNumber::NONE);
    attachments->GetAttachmentList()[WiimoteEmu::ExtensionNumber::NUNCHUK]
        ->SetInputOverrideFunction([port](std::string_view group, std::string_view name, double) {
          return NunchukInput(port, group, name);
        });
  }
}
// Main thread: integrate the right stick and sample the mouse over the game view.
void UpdatePointer(bool running) {
  const auto now = std::chrono::steady_clock::now();
  const double dt = std::min(std::chrono::duration<double>(now - last_tick).count(), 0.1);
  last_tick = now;
  for (int port = 0; port < 2; ++port) {
    if (Held(port, 20)) {
      pointer_x[port] = 0;
      pointer_y[port] = 0;
      continue;
    }
    // A full deflection crosses the screen in about a second.
    const double x = inputs[port][16].load(), y = inputs[port][17].load();
    if (std::hypot(x, y) < 0.15) continue;
    pointer_x[port] = std::clamp(pointer_x[port].load() + x * dt * 2, -1.0, 1.0);
    pointer_y[port] = std::clamp(pointer_y[port].load() + y * dt * 2, -1.0, 1.0);
  }
  NSView* view = (__bridge NSView*)render_view;
  const bool focused = running && view.window.isKeyWindow;
  NSPoint point = focused ? [view convertPoint:view.window.mouseLocationOutsideOfEventStream
                                      fromView:nil] : NSPoint{NAN, NAN};
  const bool inside = focused && NSPointInRect(point, view.bounds);
  const NSUInteger pressed = inside ? [NSEvent pressedMouseButtons] : 0;
  mouse_button[0] = pressed & 1;
  mouse_button[1] = pressed & 2;
  // Only a moved mouse takes the pointer, so an idle cursor never fights the stick.
  if (inside && (point.x != last_mouse.x || point.y != last_mouse.y) && !std::isnan(last_mouse.x)) {
    const NSRect bounds = view.bounds;
    const double y = point.y / bounds.size.height * 2 - 1;
    pointer_x[0] = point.x / bounds.size.width * 2 - 1;
    pointer_y[0] = view.isFlipped ? -y : y;
  }
  last_mouse = inside ? point : NSPoint{NAN, NAN};
}
}

extern "C" {
int nxdolphin_abi() { return 1; }
// Sys assets must be bundled in the app's Contents/Resources/Sys.
int nxdolphin_start(void* view, const char* rom, const char* user) {
  if (initialized || !view || !rom || !user) return 0;
  frames = 0;
  stop_requested = false;
  Error("");
  Common::RegisterMsgAlertHandler(Alert);
  UICommon::SetUserDirectory(user);
  UICommon::Init();
  if (!save_root.empty()) {
    File::SetUserPath(D_WIIROOT_IDX, save_root + "/Wii");
    File::SetUserPath(D_GCUSER_IDX, save_root + "/GC");
  }
  UICommon::CreateDirectories();
  initialized = true;
  Config::SetCurrent(Config::MAIN_GFX_BACKEND, std::string("Metal"));
  Config::SetCurrent(Config::MAIN_ENABLE_SAVESTATES, true);
  Config::SetCurrent(Config::GFX_HACK_SKIP_DUPLICATE_XFBS, false);
  // 3x native (about 1080p) on Apple Silicon. Ubershaders hide shader-compile stutter.
  Config::SetCurrent(Config::GFX_EFB_SCALE, 3);
  Config::SetCurrent(Config::GFX_SHADER_COMPILATION_MODE,
                     ShaderCompilationMode::AsynchronousUberShaders);
  Config::SetCurrent(Config::GFX_WAIT_FOR_SHADERS_BEFORE_STARTING, true);
  // The NXForge sidebar has its own frame counter (nxdolphin_frames); Dolphin's is a setting.
  Config::SetCurrent(Config::GFX_SHOW_FPS, false);
  Config::SetCurrent(Config::GFX_SHOW_SPEED, false);
  Config::SetCurrent(Config::MAIN_WIIMOTE_CONTINUOUS_SCANNING, false);
  for (int port = 0; port < 2; ++port)
    Config::SetCurrent(Config::GetInfoForSIDevice(port), SerialInterface::SIDEVICE_GC_CONTROLLER);
  VideoBackendBase::ActivateBackend("Metal");
  WindowSystemInfo wsi(WindowSystemType::MacOS, nullptr, view, view);
  wsi.render_surface_scale = [(__bridge NSView*)view window].backingScaleFactor;
  UICommon::InitControllers(wsi);
  render_view = view;
  last_tick = std::chrono::steady_clock::now();
  last_mouse = {NAN, NAN};
  for (int port = 0; port < 2; ++port) {
    for (auto& input : inputs[port]) input = 0;
    pointer_x[port] = 0;
    pointer_y[port] = 0;
    mouse_button[port] = false;
    Pad::GetConfig()->GetController(port)->SetInputOverrideFunction(
        [port](std::string_view group, std::string_view name, double) {
          return Input(port, group, name);
        });
  }
  ConfigureWiimotes();
  frame_hook = GetVideoEvents().after_present_event.Register([](PresentInfo& info) {
    frames.store(info.frame_count + 1);   // the game's own new frames, not repeats: what the FPS counter shows
  });
  auto boot = BootParameters::GenerateFromFile(rom);
  if (!boot || !BootManager::BootCore(Core::System::GetInstance(), std::move(boot), wsi)) {
    Error("Dolphin could not boot this game. Check the game file and session log.");
    return 0;
  }
  return 1;
}
// 0 loading, 1 playing (a real frame presented), 2 paused, 3 stopped.
int nxdolphin_tick() {
  if (!initialized) return 3;
  auto& system = Core::System::GetInstance();
  Core::HostDispatchJobs(system);
  if (stop_requested) return 3;
  auto state = Core::GetState(system);
  UpdatePointer(state == Core::State::Running);
  if (state == Core::State::Uninitialized || state == Core::State::Stopping) return 3;
  if (state == Core::State::Paused) return 2;
  return frames > 0 && state == Core::State::Running ? 1 : 0;
}
void nxdolphin_pause(int paused) {
  if (!initialized) return;
  for (auto& port : inputs) for (auto& input : port) input = 0;
  for (auto& button : mouse_button) button = false;
  auto& system = Core::System::GetInstance();
  if (Core::IsRunning(system))
    Core::SetState(system, paused ? Core::State::Paused : Core::State::Running);
}
void nxdolphin_input(int port, int control, double value) {
  if (port >= 0 && port < 2 && control >= 0 && control < CONTROLS && std::isfinite(value))
    inputs[port][control] = std::clamp(value, -1.0, 1.0);
}
void nxdolphin_resize() {
  if (g_presenter) g_presenter->ResizeSurface();
}
void nxdolphin_volume(int value) {
  if (initialized) Config::SetCurrent(Config::MAIN_AUDIO_VOLUME, std::clamp(value, 0, 100));
}
void nxdolphin_stop() {
  if (!initialized) return;
  auto& system = Core::System::GetInstance();
  // This process is the isolation boundary. A wedged core must not leave the player waiting forever.
  struct ShutdownWatch { std::mutex mutex; std::condition_variable condition; bool done = false; };
  auto watch = std::make_shared<ShutdownWatch>();
  std::thread([watch] {
    std::unique_lock lock(watch->mutex);
    if (!watch->condition.wait_for(lock, std::chrono::seconds(20), [&] { return watch->done; })) {
      fprintf(stderr, "Dolphin shutdown timed out; save flushing could not be confirmed.\n");
      std::_Exit(70);
    }
  }).detach();
  Core::Stop(system);
  Core::Shutdown(system);
  frame_hook.reset();
  UICommon::ShutdownControllers();
  UICommon::Shutdown();
  render_view = nullptr;
  initialized = false;
  { std::lock_guard lock(watch->mutex); watch->done = true; }
  watch->condition.notify_one();
}
const char* nxdolphin_error() {
  static thread_local std::string copy;
  std::lock_guard lock(error_mutex);
  copy = last_error;
  return copy.c_str();
}

// Settings the player changes while the game runs (the sidebar). Picture settings take effect at the next frame.
enum { NXD_SCALE, NXD_SHOW_FPS, NXD_MSAA, NXD_WIDESCREEN, NXD_ASPECT, NXD_VSYNC, NXD_ANISO, NXD_SPEED, NXD_REMOTE };
void nxdolphin_set(int key, int value) {
  switch (key) {
  case NXD_SCALE: Config::SetCurrent(Config::GFX_EFB_SCALE, std::clamp(value, 1, 8)); break;
  case NXD_SHOW_FPS: Config::SetCurrent(Config::GFX_SHOW_FPS, value != 0); break;
  case NXD_MSAA: Config::SetCurrent(Config::GFX_MSAA, static_cast<u32>(std::clamp(value, 1, 8))); break;
  case NXD_WIDESCREEN: Config::SetCurrent(Config::GFX_WIDESCREEN_HACK, value != 0); break;
  case NXD_ASPECT: Config::SetCurrent(Config::GFX_ASPECT_RATIO, static_cast<AspectMode>(std::clamp(value, 0, 3))); break;
  case NXD_VSYNC: Config::SetCurrent(Config::GFX_VSYNC, value != 0); break;
  case NXD_ANISO:
    Config::SetCurrent(Config::GFX_ENHANCE_MAX_ANISOTROPY,
                       static_cast<AnisotropicFilteringMode>(std::clamp(value, -1, 4)));
    break;
  case NXD_SPEED: Config::SetCurrent(Config::MAIN_EMULATION_SPEED, std::max(value, 0) / 100.0f); break;
  case NXD_REMOTE:
    // set before nxdolphin_start; later, the attachment changes as if plugged in while playing
    remote_style = std::clamp(value, 0, 2);
    if (initialized) ConfigureWiimotes();
    break;
  }
}
// The folder the game's saves go in, apart from Dolphin's caches and settings, so NXForge's save backups and snapshots take just them. Before nxdolphin_start
void nxdolphin_save_root(const char* path) { save_root = path ? path : ""; }
// New frames the game has drawn since it started, repeats left out (the sidebar's frame counter reads it).
uint64_t nxdolphin_frames() { return frames.load(); }
// The running game's own ID (RTZE08); "" before it has booted.
const char* nxdolphin_game_id() {
  static thread_local std::string copy;
  copy = initialized ? SConfig::GetInstance().GetGameID() : "";
  return copy.c_str();
}
// The whole machine to a file and back (Dolphin's save states). They finish on the CPU thread a moment later.
int nxdolphin_state_save(const char* path) {
  auto& system = Core::System::GetInstance();
  if (!initialized || !path || !Core::IsRunning(system)) return 0;
  State::SaveAs(system, path);
  return 1;
}
int nxdolphin_state_load(const char* path) {
  auto& system = Core::System::GetInstance();
  if (!initialized || !path || !Core::IsRunning(system)) return 0;
  State::LoadAs(system, path);
  return 1;
}
// The next frame Dolphin draws, at the internal resolution, as a PNG.
int nxdolphin_screenshot(const char* path) {
  auto& system = Core::System::GetInstance();
  if (!initialized || !path || !Core::IsRunning(system) || !g_frame_dumper) return 0;
  const Core::CPUThreadGuard guard(system);
  g_frame_dumper->SaveScreenshot(path);
  return 1;
}
}

std::vector<std::string> Host_GetPreferredLocales() { return {}; }
bool Host_UIBlocksControllerState() { return false; }
bool Host_RendererHasFocus() { return true; }
bool Host_RendererHasFullFocus() { return true; }
bool Host_RendererIsFullscreen() { return false; }
bool Host_TASInputHasFocus() { return false; }
void Host_Message(HostMessageID id) { if (id == HostMessageID::WMUserStop) stop_requested = true; }
void Host_PPCSymbolsChanged() {}
void Host_PPCBreakpointsChanged() {}
void Host_RequestRenderWindowSize(int, int) {}
void Host_UpdateDisasmDialog() {}
void Host_JitCacheInvalidation() {}
void Host_JitProfileDataWiped() {}
void Host_UpdateTitle(const std::string&) {}
void Host_YieldToUI() {}
void Host_TitleChanged() {}
void Host_UpdateDiscordClientID(const std::string&) {}
bool Host_UpdateDiscordPresenceRaw(const std::string&, const std::string&, const std::string&,
    const std::string&, const std::string&, const std::string&, int64_t, int64_t, int, int) { return false; }
std::unique_ptr<GBAHostInterface> Host_CreateGBAHost(std::weak_ptr<HW::GBA::Core>) { return nullptr; }
