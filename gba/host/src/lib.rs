//! NXForge's Game Boy Advance host: a game's recompiled code (the library gba-recomp's `recomp build` makes) run on
//! gba-recomp's machine model, behind the C interface in nxgba.h. The Mac player (gba_front_mac.m) and the headless
//! test tool (run.rs) are the two callers.
//!
//! The dispatch loop and the block table are gba-recomp's (crates/recomp/src/main.rs: BlockTable, run_frame_native;
//! MIT OR Apache-2.0, JRickey and contributors), moved here because they live in its command-line program. With no
//! BIOS image the machine starts at the cartridge's entry point with gba-recomp's high-level system calls, so there
//! is no boot logo.

pub mod audio;
pub mod cheats;

use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr, CString};
use std::sync::{Arc, Mutex};

use gba_core::capi::{RcgBlock, RtApi, RT_API};
use gba_core::{Machine, StepEvent};
use recomp_core::labels;

const ROM_BASE: u32 = 0x0800_0000;
const IWRAM_BASE: u32 = 0x0300_0000;
const EWRAM_BASE: u32 = 0x0200_0000;
const FRAME_STEP_GUARD: u64 = 200_000_000;
pub const SLOTS: usize = 10;

type BlockFn = extern "C" fn(*const RtApi, *mut c_void) -> u32;

struct BlockTable {
    rom: Vec<Option<BlockFn>>,
    iwram: Vec<Option<BlockFn>>,
    ewram: Vec<Option<BlockFn>>,
    other: HashMap<u32, BlockFn>,
    len: usize,
}

impl BlockTable {
    fn load(path: &str) -> Result<BlockTable, String> {
        let c = CString::new(path).map_err(|e| e.to_string())?;
        // The library stays loaded for the life of the process: the table holds pointers into it.
        let h = unsafe { libc::dlopen(c.as_ptr(), libc::RTLD_NOW | libc::RTLD_LOCAL) };
        if h.is_null() {
            let e = unsafe { libc::dlerror() };
            let why = if e.is_null() { "dlopen failed".to_string() } else { unsafe { CStr::from_ptr(e) }.to_string_lossy().into_owned() };
            return Err(format!("{path}: {why}"));
        }
        let sym = |name: &[u8]| -> Result<*mut c_void, String> {
            let p = unsafe { libc::dlsym(h, name.as_ptr() as *const c_char) };
            if p.is_null() {
                Err(format!("{path}: no {} (not a gba-recomp translation)", String::from_utf8_lossy(&name[..name.len() - 1])))
            } else {
                Ok(p)
            }
        };
        let blocks: &[RcgBlock] = unsafe {
            let b = sym(b"rcg_blocks\0")? as *const RcgBlock;
            let n = *(sym(b"rcg_block_count\0")? as *const u64);
            std::slice::from_raw_parts(b, n as usize)
        };
        let mut rom_max = 0usize;
        for b in blocks {
            let r = b.key.wrapping_sub(ROM_BASE) as usize;
            if r < 0x0200_0000 {
                rom_max = rom_max.max(r + 1);
            }
        }
        let any_ewram = blocks.iter().any(|b| (b.key.wrapping_sub(EWRAM_BASE) as usize) < 0x4_0000);
        let mut t = BlockTable {
            rom: vec![None; rom_max],
            iwram: vec![None; 0x8000],
            ewram: vec![None; if any_ewram { 0x4_0000 } else { 0 }],
            other: HashMap::new(),
            len: blocks.len(),
        };
        for b in blocks {
            let r = b.key.wrapping_sub(ROM_BASE) as usize;
            let w = b.key.wrapping_sub(IWRAM_BASE) as usize;
            let e = b.key.wrapping_sub(EWRAM_BASE) as usize;
            if r < t.rom.len() {
                t.rom[r] = Some(b.func);
            } else if w < t.iwram.len() {
                t.iwram[w] = Some(b.func);
            } else if e < t.ewram.len() {
                t.ewram[e] = Some(b.func);
            } else {
                t.other.insert(b.key, b.func);
            }
        }
        Ok(t)
    }

    #[inline(always)]
    fn get(&self, key: u32) -> Option<BlockFn> {
        let r = key.wrapping_sub(ROM_BASE) as usize;
        if r < self.rom.len() {
            return self.rom[r];
        }
        let w = key.wrapping_sub(IWRAM_BASE) as usize;
        if w < self.iwram.len() {
            return self.iwram[w];
        }
        let e = key.wrapping_sub(EWRAM_BASE) as usize;
        if e < self.ewram.len() {
            return self.ewram[e];
        }
        if self.other.is_empty() {
            None
        } else {
            self.other.get(&key).copied()
        }
    }
}

/// What the host reports about a run (nxgba.h nxgba_info).
#[repr(C)]
#[derive(Default, Clone, Copy)]
pub struct Info {
    pub frames: u64,
    pub native_blocks: u64,
    pub fallback_steps: u64,
    /// distinct entry points that ran in the interpreter this run (ROM, then RAM)
    pub misses_rom: u32,
    pub misses_ram: u32,
    pub blocks: u32,
    /// 0 none, 1 SRAM, 2 Flash 64K, 3 Flash 128K, 4 EEPROM
    pub save_kind: u32,
    pub save_bytes: u32,
    pub rom_bytes: u32,
    pub has_rtc: u32,
    /// 1 while the Enhanced path plays the engine's floating-point re-render
    pub hle_live: u32,
}

pub struct NxGba {
    machine: Box<Machine>,
    table: Option<BlockTable>,
    pub streams: Arc<Mutex<audio::AudioStreams>>,
    renderer: Mutex<Option<audio::Renderer>>,
    sav_path: Option<String>,
    sav_seen: Option<u64>,
    slots: Vec<Option<Box<Machine>>>,
    native: u64,
    fallback: u64,
    /// entry points that missed the block table: key (address | thumb) -> hits
    misses: HashMap<u32, u64>,
    iwram_cap: Option<Box<labels::Blob>>,
    record: bool,
    sha256: String,
    sha1: String,
    title: CString,
    code: CString,
    engine: CString,
    pub cheats: cheats::Cheats,
    scratch: CString,
}

fn hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// The cartridge header's title (12 characters at 0xA0) and game code (4 at 0xAC), printable ASCII only.
pub fn header(rom: &[u8]) -> (String, String) {
    let clean = |b: &[u8]| -> String {
        b.iter().take_while(|&&c| c != 0).map(|&c| if (0x20..0x7F).contains(&c) { c as char } else { '?' }).collect::<String>().trim().to_string()
    };
    if rom.len() < 0xC0 {
        return (String::new(), String::new());
    }
    (clean(&rom[0xA0..0xAC]), clean(&rom[0xAC..0xB0]))
}

impl NxGba {
    pub fn open(rom_path: &str, translation: Option<&str>, sav_path: Option<&str>) -> Result<NxGba, String> {
        use sha2::Digest;
        let rom = std::fs::read(rom_path).map_err(|e| format!("{rom_path}: {e}"))?;
        if rom.len() < 0xC0 || rom.len() > 32 << 20 {
            return Err(format!("{rom_path}: not a Game Boy Advance cartridge image ({} bytes)", rom.len()));
        }
        let sha256 = hex(&sha2::Sha256::digest(&rom));
        let sha1 = hex(&sha1::Sha1::digest(&rom));
        let (title, code) = header(&rom);
        let table = match translation {
            Some(p) => Some(BlockTable::load(p)?),
            None => None,
        };
        let mut machine = Box::new(Machine::new(rom));
        if let Some(p) = sav_path {
            if let Ok(sav) = std::fs::read(p) {
                machine.bus.load_save_data(&sav);
            }
        }
        machine.bus.tap_channels = true;
        let engine = audio::arm_engine(&mut machine);
        let sav_seen = machine.bus.save_data().map(recomp_core::fnv64);
        let streams = audio::AudioStreams { volume: 1.0, enhanced_on: true, ..Default::default() };
        Ok(NxGba {
            machine,
            table,
            streams: Arc::new(Mutex::new(streams)),
            renderer: Mutex::new(None),
            sav_path: sav_path.map(str::to_string),
            sav_seen,
            slots: (0..SLOTS).map(|_| None).collect(),
            native: 0,
            fallback: 0,
            misses: HashMap::new(),
            iwram_cap: None,
            record: true,
            sha256,
            sha1,
            title: CString::new(title).unwrap_or_default(),
            code: CString::new(code).unwrap_or_default(),
            engine: CString::new(engine).unwrap_or_default(),
            cheats: cheats::Cheats::default(),
            scratch: CString::default(),
        })
    }

    /// One frame: translated blocks where there are any, the interpreter elsewhere, interrupts at block edges.
    /// False when the frame did not finish (the stall guard).
    pub fn run_frame(&mut self) -> bool {
        let before = self.machine.bus.frames;
        self.cheats.apply(&mut self.machine.bus);
        let mptr = &mut *self.machine as *mut Machine as *mut c_void;
        let m = &mut *self.machine;
        match &self.table {
            None => m.run_frame(5_000_000),
            Some(table) => {
                m.bus.frame_ready = false;
                let mut steps = 0u64;
                let mut fb_prev_end = u32::MAX;
                while !m.bus.frame_ready && steps < FRAME_STEP_GUARD {
                    steps += 1;
                    if m.bus.halted
                        || (m.cpu.regs[15] == gba_core::machine::IRQ_RETURN_ADDR && m.cpu.mode() == gba_core::Mode::Irq)
                        || (m.bus.irq_pending() && !m.cpu.flag(gba_core::cpu::FLAG_I))
                    {
                        m.step();
                        continue;
                    }
                    let key = m.cpu.regs[15] | m.cpu.thumb() as u32;
                    if let Some(h) = m.bus.mp2k.as_deref() {
                        if h.active && h.hook_match(key) {
                            m.bus.mp2k_frame_hook(key);
                        }
                    }
                    if let Some(g) = m.bus.gax.as_deref() {
                        if g.hook_match(key) {
                            let r0 = m.cpu.regs[0];
                            m.bus.gax_frame_hook(key, r0);
                        }
                    }
                    if let Some(rr) = m.bus.rdrv.as_deref() {
                        if rr.hook_match(key) {
                            m.bus.rdrv_frame_hook(key);
                        }
                    }
                    match table.get(key) {
                        Some(f) => {
                            f(&RT_API, mptr);
                            self.native += 1;
                            fb_prev_end = u32::MAX;
                        }
                        None => {
                            // an entry (not the straight-line continuation of the last interpreted instruction) is what
                            // the next build wants as a label
                            if self.record && key & !1 != fb_prev_end {
                                let n = self.misses.entry(key).or_insert(0);
                                *n += 1;
                                if *n == 1 && key >> 24 == 3 {
                                    capture_iwram(&mut self.iwram_cap, &m.bus.iwram, key);
                                }
                            }
                            fb_prev_end = match m.step() {
                                StepEvent::Instr(i) => i.addr.wrapping_add(i.size()),
                                StepEvent::Idle => u32::MAX,
                            };
                            self.fallback += 1;
                        }
                    }
                }
            }
        }
        let mut st = self.streams.lock().unwrap();
        audio::handoff(&mut self.machine.bus, &mut st);
        drop(st);
        if self.machine.bus.frames % 300 == 0 {
            self.save_flush();
        }
        self.machine.bus.frames != before
    }

    /// The cartridge save to its file when it changed since the last write (temp file, then rename). True when written.
    pub fn save_flush(&mut self) -> bool {
        let Some(path) = self.sav_path.as_deref() else { return false };
        let Some(data) = self.machine.bus.save_data() else { return false };
        let h = recomp_core::fnv64(data);
        if self.sav_seen == Some(h) {
            return false;
        }
        let tmp = format!("{path}.tmp");
        if let Some(dir) = std::path::Path::new(path).parent() {
            let _ = std::fs::create_dir_all(dir);
        }
        if std::fs::write(&tmp, data).is_ok() && std::fs::rename(&tmp, path).is_ok() {
            self.sav_seen = Some(h);
            return true;
        }
        false
    }

    pub fn state_save(&mut self, slot: usize) -> bool {
        if slot >= SLOTS {
            return false;
        }
        self.slots[slot] = Some(Box::new((*self.machine).clone()));
        true
    }

    pub fn state_load(&mut self, slot: usize) -> bool {
        let Some(Some(s)) = self.slots.get(slot) else { return false };
        // into the same allocation: the translated code's machine pointer stays good
        *self.machine = (**s).clone();
        let mut st = self.streams.lock().unwrap();
        st.mixed.clear();
        st.psg.clear();
        st.hle.clear();
        st.fifo[0].clear();
        st.fifo[1].clear();
        true
    }

    pub fn reset(&mut self) {
        let rom = std::mem::take(&mut self.machine.bus.rom);
        let sav = self.machine.bus.save_data().map(|d| d.to_vec());
        *self.machine = Machine::new(rom);
        if let Some(s) = sav {
            self.machine.bus.load_save_data(&s);
        }
        self.machine.bus.tap_channels = true;
        audio::arm_engine(&mut self.machine);
    }

    pub fn info(&self) -> Info {
        use gba_core::backup::BackupKind as K;
        let b = &self.machine.bus;
        Info {
            frames: b.frames,
            native_blocks: self.native,
            fallback_steps: self.fallback,
            misses_rom: self.misses.keys().filter(|k| (0x08..=0x0D).contains(&(*k >> 24))).count() as u32,
            misses_ram: self.misses.keys().filter(|k| !(0x08..=0x0D).contains(&(*k >> 24))).count() as u32,
            blocks: self.table.as_ref().map_or(0, |t| t.len as u32),
            save_kind: match b.backup {
                K::None => 0,
                K::Sram => 1,
                K::Flash64 => 2,
                K::Flash128 => 3,
                K::Eeprom => 4,
            },
            save_bytes: b.save_data().map_or(0, |d| d.len() as u32),
            rom_bytes: b.rom.len() as u32,
            has_rtc: b.rtc.is_some() as u32,
            hle_live: (b.mp2k.as_deref().is_some_and(|h| h.live())
                || b.gax.as_deref().is_some_and(|g| g.live())
                || b.rdrv.as_deref().is_some_and(|r| r.live())) as u32,
        }
    }

    /// This run's misses into gba-recomp's own per-image label accumulator (and the IWRAM snapshot beside it), which
    /// the next `recomp build` of the image reads by itself; also written to `also` (a file in the game's build
    /// folder, for the converter's Port details). Returns how many entries the accumulator gained.
    pub fn misses_write(&mut self, also: Option<&str>) -> Result<usize, String> {
        if self.misses.is_empty() {
            return Ok(0);
        }
        let rom_len = self.machine.bus.rom.len();
        let mut new = labels::Labels::default();
        for &key in self.misses.keys() {
            match key >> 24 {
                0x08..=0x0D if ((key & !1 & 0x01FF_FFFF) as usize) < rom_len => {
                    new.rom.insert(key);
                }
                0x03 => {
                    new.iwram.insert(key);
                }
                _ => {}
            }
        }
        let path = labels::config_path(&self.sha256);
        let mut all = if path.is_file() { labels::Labels::load(&path, &self.sha256, rom_len).unwrap_or_default() } else { labels::Labels::default() };
        let before = all.rom.len() + all.iwram.len();
        all.merge(new);
        all.save(&path, &self.sha256)?;
        if let Some(cap) = self.iwram_cap.take() {
            let bp = labels::blob_path(&self.sha256);
            let mut blob = labels::Blob::load(&bp).unwrap_or_else(labels::Blob::new);
            for i in 0..labels::IWRAM_LEN {
                if cap.mask[i] != 0 {
                    blob.img[i] = cap.img[i];
                    blob.mask[i] = 1;
                }
            }
            blob.save(&bp)?;
        }
        if let Some(p) = also {
            let mut v: Vec<(u32, u64)> = self.misses.iter().map(|(&k, &n)| (k, n)).collect();
            v.sort_by_key(|&(k, n)| (std::cmp::Reverse(n), k));
            let mut s = String::from("# entry points that ran in the interpreter, most hits first: address mode hits\n");
            for (k, n) in v {
                s += &format!("{:08x} {} {}\n", k & !1, if k & 1 != 0 { "thumb" } else { "arm" }, n);
            }
            std::fs::write(p, s).map_err(|e| format!("{p}: {e}"))?;
        }
        Ok(all.rom.len() + all.iwram.len() - before)
    }

    pub fn machine(&mut self) -> &mut Machine {
        &mut self.machine
    }
    pub fn sha256(&self) -> &str {
        &self.sha256
    }
    pub fn sha1(&self) -> &str {
        &self.sha1
    }
}

fn capture_iwram(cap: &mut Option<Box<labels::Blob>>, iwram: &[u8], entry: u32) {
    let blob = cap.get_or_insert_with(|| Box::new(labels::Blob::new()));
    let n = iwram.len().min(labels::IWRAM_LEN);
    for i in 0..n {
        if blob.mask[i] == 0 {
            blob.img[i] = iwram[i];
            blob.mask[i] = 1;
        }
    }
    let at = (entry & !1) as usize & (labels::IWRAM_LEN - 1);
    let (lo, hi) = (at.saturating_sub(64), (at + 2048).min(n));
    blob.img[lo..hi].copy_from_slice(&iwram[lo..hi]);
    blob.mask[lo..hi].fill(1);
}

/// 15-bit GBA colour to RGBA8. mode 0: the raw colour, as emulators showed it for years (oversaturated on a modern
/// screen); 1: corrected for the GBA's LCD (the panel's channel mixing and its darker response, after the public-domain
/// "gba-color" shader's matrix), which is what the art was drawn for.
pub fn rgba(px: &[u16], out: &mut [u8], mode: u32) {
    static LUT: std::sync::OnceLock<Vec<[u8; 3]>> = std::sync::OnceLock::new();
    if mode == 0 {
        for (p, o) in px.iter().zip(out.chunks_exact_mut(4)) {
            let (r, g, b) = (p & 31, (p >> 5) & 31, (p >> 10) & 31);
            o[0] = (r << 3 | r >> 2) as u8;
            o[1] = (g << 3 | g >> 2) as u8;
            o[2] = (b << 3 | b >> 2) as u8;
            o[3] = 255;
        }
        return;
    }
    let lut = LUT.get_or_init(|| {
        let mut t = Vec::with_capacity(32768);
        for i in 0..32768u32 {
            let lin = |c: u32| ((c & 31) as f64 / 31.0).powf(2.4);
            let (r, g, b) = (lin(i), lin(i >> 5), lin(i >> 10));
            let mix = |x: f64| (x.clamp(0.0, 1.0).powf(1.0 / 2.2) * 255.0 * 0.94 + 0.5) as u8;
            t.push([
                mix(0.82 * r + 0.125 * g + 0.195 * b),
                mix(0.24 * r + 0.665 * g + 0.075 * b),
                mix(-0.06 * r + 0.21 * g + 0.73 * b),
            ]);
        }
        t
    });
    for (p, o) in px.iter().zip(out.chunks_exact_mut(4)) {
        let c = lut[(*p & 0x7FFF) as usize];
        o[0] = c[0];
        o[1] = c[1];
        o[2] = c[2];
        o[3] = 255;
    }
}

// ---- C interface (nxgba.h) ----

fn cstr(p: *const c_char) -> Option<String> {
    if p.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(p) }.to_string_lossy().into_owned()).filter(|s| !s.is_empty())
    }
}

/// # Safety
/// Pointers are C strings or null; `err` has room for `cap` bytes.
#[no_mangle]
pub unsafe extern "C" fn nxgba_open(rom: *const c_char, translation: *const c_char, sav: *const c_char, err: *mut c_char, cap: i32) -> *mut NxGba {
    let Some(rom) = cstr(rom) else { return std::ptr::null_mut() };
    match NxGba::open(&rom, cstr(translation).as_deref(), cstr(sav).as_deref()) {
        Ok(g) => Box::into_raw(Box::new(g)),
        Err(e) => {
            if !err.is_null() && cap > 0 {
                let b = e.as_bytes();
                let n = b.len().min(cap as usize - 1);
                std::ptr::copy_nonoverlapping(b.as_ptr(), err as *mut u8, n);
                *err.add(n) = 0;
            }
            std::ptr::null_mut()
        }
    }
}

macro_rules! g {
    ($p:ident) => {
        unsafe { &mut *$p }
    };
}

#[no_mangle]
pub extern "C" fn nxgba_close(p: *mut NxGba) {
    if p.is_null() {
        return;
    }
    let mut b = unsafe { Box::from_raw(p) };
    b.save_flush();
    let _ = b.misses_write(None);
}

/// Buttons held, one bit each: 0 A, 1 B, 2 Select, 3 Start, 4 Right, 5 Left, 6 Up, 7 Down, 8 R, 9 L.
#[no_mangle]
pub extern "C" fn nxgba_keys(p: *mut NxGba, down: u32) {
    g!(p).machine.bus.keys = !(down as u16) & 0x3FF;
}

#[no_mangle]
pub extern "C" fn nxgba_run_frame(p: *mut NxGba) -> i32 {
    g!(p).run_frame() as i32
}

#[no_mangle]
pub extern "C" fn nxgba_pixels(p: *mut NxGba) -> *const u16 {
    g!(p).machine.bus.framebuffer.as_ptr()
}

/// # Safety
/// `out` has room for 240 * 160 * 4 bytes.
#[no_mangle]
pub unsafe extern "C" fn nxgba_rgba(p: *mut NxGba, out: *mut u8, mode: u32) {
    rgba(&g!(p).machine.bus.framebuffer, std::slice::from_raw_parts_mut(out, 240 * 160 * 4), mode);
}

/// # Safety
/// `out` has room for `frames` stereo pairs. Any thread (the device's render callback).
#[no_mangle]
pub unsafe extern "C" fn nxgba_audio_render(p: *mut NxGba, out: *mut f32, frames: i32, rate: f64) {
    let g = &*p;
    let out = std::slice::from_raw_parts_mut(out, frames as usize * 2);
    let mut r = g.renderer.lock().unwrap();
    let mut st = g.streams.lock().unwrap();
    if r.as_ref().map_or(true, |r| r.rate() != rate) {
        *r = Some(audio::Renderer::new(rate, st.enhanced_on));
    }
    st.consumer = true;
    r.as_mut().unwrap().render(&mut st, out);
}

/// Sample pairs waiting in the emptier of the two rings: the caller runs frames while this is under nxgba_audio_target.
#[no_mangle]
pub extern "C" fn nxgba_audio_fill(p: *mut NxGba) -> i32 {
    let st = g!(p).streams.lock().unwrap();
    (st.mixed.len() / 2).min(st.psg.len() / 2) as i32
}

#[no_mangle]
pub extern "C" fn nxgba_audio_target() -> i32 {
    audio::RING_TARGET as i32
}

/// on 0: nothing renders the sound (the producer drops it); 1: a device does
#[no_mangle]
pub extern "C" fn nxgba_audio_consumer(p: *mut NxGba, on: i32) {
    let mut st = g!(p).streams.lock().unwrap();
    st.consumer = on != 0;
    if on == 0 {
        st.mixed.clear();
        st.psg.clear();
        st.hle.clear();
        st.fifo[0].clear();
        st.fifo[1].clear();
    }
}

#[no_mangle]
pub extern "C" fn nxgba_audio_set(p: *mut NxGba, enhanced: i32, bass: i32, wide: i32, volume: f32) {
    let mut st = g!(p).streams.lock().unwrap();
    st.enhanced_on = enhanced != 0;
    st.bass = bass != 0;
    st.wide = wide != 0;
    st.volume = volume.clamp(0.0, 1.0);
}

#[no_mangle]
pub extern "C" fn nxgba_save_flush(p: *mut NxGba) -> i32 {
    g!(p).save_flush() as i32
}

#[no_mangle]
pub extern "C" fn nxgba_state_save(p: *mut NxGba, slot: i32) -> i32 {
    g!(p).state_save(slot.max(0) as usize) as i32
}

#[no_mangle]
pub extern "C" fn nxgba_state_load(p: *mut NxGba, slot: i32) -> i32 {
    g!(p).state_load(slot.max(0) as usize) as i32
}

#[no_mangle]
pub extern "C" fn nxgba_state_has(p: *mut NxGba, slot: i32) -> i32 {
    g!(p).slots.get(slot.max(0) as usize).is_some_and(|s| s.is_some()) as i32
}

#[no_mangle]
pub extern "C" fn nxgba_reset(p: *mut NxGba) {
    g!(p).reset()
}

/// # Safety
/// `out` points at an nxgba_info.
#[no_mangle]
pub unsafe extern "C" fn nxgba_get_info(p: *mut NxGba, out: *mut Info) {
    *out = g!(p).info();
}

/// which 0: the header's title, 1: the game code, 2: the ROM's SHA-1, 3: its SHA-256, 4: what Enhanced audio does for this game
#[no_mangle]
pub extern "C" fn nxgba_text(p: *mut NxGba, which: i32) -> *const c_char {
    let g = g!(p);
    match which {
        0 => g.title.as_ptr(),
        1 => g.code.as_ptr(),
        2 | 3 => {
            g.scratch = CString::new(if which == 2 { g.sha1.clone() } else { g.sha256.clone() }).unwrap_or_default();
            g.scratch.as_ptr()
        }
        _ => g.engine.as_ptr(),
    }
}

/// # Safety
/// `also` is a C string or null.
#[no_mangle]
pub unsafe extern "C" fn nxgba_misses_write(p: *mut NxGba, also: *const c_char) -> i32 {
    match g!(p).misses_write(cstr(also).as_deref()) {
        Ok(n) => n as i32,
        Err(e) => {
            eprintln!("nxgba: misses not written: {e}");
            -1
        }
    }
}

// Cheats (cheats.rs): the file's text in, then a switch per cheat.

/// # Safety
/// `text` is a C string.
#[no_mangle]
pub unsafe extern "C" fn nxgba_cheats_load(p: *mut NxGba, text: *const c_char) -> i32 {
    let g = g!(p);
    g.cheats = cheats::Cheats::parse(&cstr(text).unwrap_or_default());
    g.cheats.list.len() as i32
}

#[no_mangle]
pub extern "C" fn nxgba_cheat_count(p: *mut NxGba) -> i32 {
    g!(p).cheats.list.len() as i32
}

/// what 0: the name, 1: why it cannot be applied ("" when it can)
#[no_mangle]
pub extern "C" fn nxgba_cheat_text(p: *mut NxGba, i: i32, what: i32) -> *const c_char {
    let g = g!(p);
    let s = g.cheats.list.get(i.max(0) as usize).map(|c| if what == 0 { c.name.clone() } else { c.unsupported.clone() }).unwrap_or_default();
    g.scratch = CString::new(s).unwrap_or_default();
    g.scratch.as_ptr()
}

#[no_mangle]
pub extern "C" fn nxgba_cheat_on(p: *mut NxGba, i: i32) -> i32 {
    g!(p).cheats.list.get(i.max(0) as usize).is_some_and(|c| c.on) as i32
}

#[no_mangle]
pub extern "C" fn nxgba_cheat_set(p: *mut NxGba, i: i32, on: i32) {
    if let Some(c) = g!(p).cheats.list.get_mut(i.max(0) as usize) {
        c.on = on != 0 && c.unsupported.is_empty();
    }
}
