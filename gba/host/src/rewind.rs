//! Rewind (mGBA's feature): the last seconds of play kept as snapshots of the machine, taken every few frames while the
//! game runs, so holding the rewind button steps back through them.
//!
//! A snapshot is the CPU and the bus with its memories (work RAM, video RAM, palette, OAM, I/O, the cartridge save, the
//! picture) taken out and stored apart as a delta: XOR against the newest key snapshot, with the zero runs (memory that
//! did not change) left out. A key is taken every `KEY_EVERY` snapshots and stored the same way (against zeros). The
//! cartridge and the BIOS never change, so they are never copied: the live machine's stay where they are. The decode
//! cache is content-keyed, so the live one stays good across a step back and is not copied either.
//!
//! Memory: Minish Cap takes about 20 KB a snapshot, so 30 seconds at one snapshot every four frames is about 10 MB.

use std::collections::VecDeque;

use gba_core::{Cpu, Machine, MemMap};

const KEY_EVERY: usize = 64;

struct Entry {
    cpu: Cpu,
    bus: MemMap,
    delta: Vec<u8>,
    key: u64,
}

/// The memories taken out of a bus while it is copied: the large buffers that go into the delta, and the two that are shared.
#[derive(Default)]
struct Big {
    ewram: Vec<u8>,
    iwram: Vec<u8>,
    io: Vec<u8>,
    palette: Vec<u8>,
    vram: Vec<u8>,
    oam: Vec<u8>,
    sram: Vec<u8>,
    flash: Vec<u8>,
    eeprom: Vec<u8>,
    framebuffer: Vec<u16>,
    rom: Vec<u8>,
    bios: Vec<u8>,
}

fn take(bus: &mut MemMap) -> Big {
    use std::mem::take as t;
    Big {
        ewram: t(&mut bus.ewram),
        iwram: t(&mut bus.iwram),
        io: t(&mut bus.io),
        palette: t(&mut bus.palette),
        vram: t(&mut bus.vram),
        oam: t(&mut bus.oam),
        sram: t(&mut bus.sram),
        flash: bus.flash.as_mut().map(|f| t(&mut f.data)).unwrap_or_default(),
        eeprom: bus.eeprom.as_mut().map(|e| t(&mut e.data)).unwrap_or_default(),
        framebuffer: t(&mut bus.framebuffer),
        rom: t(&mut bus.rom),
        bios: t(&mut bus.bios),
    }
}

fn put(bus: &mut MemMap, b: Big) {
    bus.ewram = b.ewram;
    bus.iwram = b.iwram;
    bus.io = b.io;
    bus.palette = b.palette;
    bus.vram = b.vram;
    bus.oam = b.oam;
    bus.sram = b.sram;
    if let Some(f) = bus.flash.as_mut() {
        f.data = b.flash;
    }
    if let Some(e) = bus.eeprom.as_mut() {
        e.data = b.eeprom;
    }
    bus.framebuffer = b.framebuffer;
    bus.rom = b.rom;
    bus.bios = b.bios;
}

impl Big {
    /// The delta's buffers in a fixed order (the picture as its bytes)
    fn parts(&mut self) -> [&mut [u8]; 10] {
        let fb = &mut self.framebuffer[..];
        // SAFETY: u16 has no invalid bit patterns and u8's alignment is 1
        let fb = unsafe { std::slice::from_raw_parts_mut(fb.as_mut_ptr() as *mut u8, fb.len() * 2) };
        [&mut self.ewram, &mut self.iwram, &mut self.io, &mut self.palette, &mut self.vram, &mut self.oam, &mut self.sram, &mut self.flash, &mut self.eeprom, fb]
    }
    fn gather(&mut self, out: &mut Vec<u8>) {
        out.clear();
        for p in self.parts() {
            out.extend_from_slice(p);
        }
    }
    fn scatter(&mut self, from: &[u8]) {
        let mut at = 0;
        for p in self.parts() {
            let n = p.len().min(from.len().saturating_sub(at));
            p[..n].copy_from_slice(&from[at..at + n]);
            at += p.len();
        }
    }
}

/// `cur` XOR `base` (zeros where there is no base), as runs: [zero bytes u32][literal bytes u32][the literals], in
/// eight-byte words so a run of unchanged memory costs eight bytes however long it is.
pub fn encode(cur: &[u8], base: Option<&[u8]>, out: &mut Vec<u8>) {
    out.clear();
    let word = |i: usize| -> u64 {
        let a = u64::from_le_bytes(cur[i..i + 8].try_into().unwrap());
        match base {
            Some(b) if b.len() >= i + 8 => a ^ u64::from_le_bytes(b[i..i + 8].try_into().unwrap()),
            _ => a,
        }
    };
    let n = cur.len();
    let whole = n & !7;
    let mut i = 0;
    while i < n {
        let z0 = i;
        while i < whole && word(i) == 0 {
            i += 8;
        }
        let zeros = i - z0;
        let l0 = i;
        // literals until two zero words in a row (one alone costs less as a literal than as a new run); the last few
        // bytes that do not make a word are literals
        loop {
            if i >= whole {
                i = n;
                break;
            }
            if word(i) == 0 && (i + 8 >= whole || word(i + 8) == 0) {
                break;
            }
            i += 8;
        }
        let lits = i - l0;
        out.extend_from_slice(&(zeros as u32).to_le_bytes());
        out.extend_from_slice(&(lits as u32).to_le_bytes());
        for (k, c) in cur.iter().enumerate().take(i).skip(l0) {
            out.push(c ^ base.and_then(|b| b.get(k)).copied().unwrap_or(0));
        }
    }
}

/// The bytes `encode` was given, into `out` (`len` of them), against the same base
pub fn decode(enc: &[u8], base: Option<&[u8]>, len: usize, out: &mut Vec<u8>) {
    out.clear();
    if let Some(b) = base {
        out.extend_from_slice(&b[..len.min(b.len())]);
    }
    out.resize(len, 0);
    let (mut at, mut i) = (0usize, 0usize);
    while i + 8 <= enc.len() {
        let zeros = u32::from_le_bytes(enc[i..i + 4].try_into().unwrap()) as usize;
        let lits = u32::from_le_bytes(enc[i + 4..i + 8].try_into().unwrap()) as usize;
        i += 8;
        at += zeros;
        for k in 0..lits {
            if at + k < len {
                out[at + k] ^= enc[i + k];
            }
        }
        at += lits;
        i += lits;
    }
}

pub struct Rewind {
    /// a snapshot every this many frames
    pub every: u32,
    cap: usize,
    tick: u32,
    entries: VecDeque<Entry>,
    keys: VecDeque<(u64, Vec<u8>)>,
    /// the key the next snapshot is taken against: its id and its bytes; None makes the next snapshot a key
    base: Option<(u64, Vec<u8>)>,
    next_key: u64,
    since_key: usize,
    raw: Vec<u8>,
    tmp: Vec<u8>,
    /// what is kept, in bytes (the deltas and the keys; each snapshot's CPU and bus besides are a few KB)
    pub bytes: usize,
    pub push_ns: u64,
    pub pushes: u64,
}

impl Rewind {
    pub fn new(seconds: u32, every: u32) -> Rewind {
        let every = every.max(1);
        Rewind {
            every,
            cap: ((seconds as f64 * 59.7275 / every as f64).ceil() as usize).max(1),
            tick: 0,
            entries: VecDeque::new(),
            keys: VecDeque::new(),
            base: None,
            next_key: 0,
            since_key: 0,
            raw: Vec::new(),
            tmp: Vec::new(),
            bytes: 0,
            push_ns: 0,
            pushes: 0,
        }
    }

    /// Seconds of play held now
    pub fn seconds(&self) -> f64 {
        self.entries.len() as f64 * self.every as f64 / 59.7275
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    /// After a frame: a snapshot when one is due
    pub fn frame(&mut self, m: &mut Machine) {
        self.tick += 1;
        if self.tick >= self.every {
            self.tick = 0;
            self.push(m);
        }
    }

    pub fn push(&mut self, m: &mut Machine) {
        let t0 = std::time::Instant::now();
        let mut big = take(&mut m.bus);
        let bus = m.bus.clone();
        big.gather(&mut self.raw);
        put(&mut m.bus, big);
        if self.base.is_none() || self.since_key >= KEY_EVERY {
            let id = self.next_key;
            self.next_key += 1;
            let mut enc = Vec::new();
            encode(&self.raw, None, &mut enc);
            enc.shrink_to_fit();
            self.bytes += enc.len();
            self.keys.push_back((id, enc));
            self.base = Some((id, self.raw.clone()));
            self.since_key = 0;
        }
        let (id, base) = self.base.as_ref().unwrap();
        let mut delta = Vec::new();
        encode(&self.raw, Some(base), &mut delta);
        delta.shrink_to_fit();
        self.bytes += delta.len();
        self.entries.push_back(Entry { cpu: m.cpu.clone(), bus, delta, key: *id });
        self.since_key += 1;
        while self.entries.len() > self.cap {
            let e = self.entries.pop_front().unwrap();
            self.bytes -= e.delta.len();
            let oldest = self.entries.front().map_or(u64::MAX, |e| e.key);
            while self.keys.front().is_some_and(|k| k.0 < oldest) {
                self.bytes -= self.keys.pop_front().unwrap().1.len();
            }
        }
        self.push_ns += t0.elapsed().as_nanos() as u64;
        self.pushes += 1;
    }

    /// Back to the newest snapshot (and it is used up): false when none is left
    pub fn step(&mut self, m: &mut Machine) -> bool {
        let Some(e) = self.entries.pop_back() else { return false };
        self.bytes -= e.delta.len();
        let len = {
            let mut big = take(&mut m.bus);
            big.gather(&mut self.raw);
            put(&mut m.bus, big);
            self.raw.len()
        };
        // the key it was taken against, as bytes
        if self.base.as_ref().map(|b| b.0) != Some(e.key) {
            let Some(k) = self.keys.iter().find(|k| k.0 == e.key) else { return false };
            let mut kb = Vec::new();
            decode(&k.1, None, len, &mut kb);
            self.base = Some((e.key, kb));
        }
        let base = &self.base.as_ref().unwrap().1;
        decode(&e.delta, Some(base), len, &mut self.tmp);
        // the snapshot's bus, with the live machine's buffers moved into it and filled from the delta
        let mut live = take(&mut m.bus);
        live.scatter(&self.tmp);
        let mut bus = e.bus;
        put(&mut bus, live);
        m.bus = bus;
        m.cpu = e.cpu;
        // keys newer than the snapshot left are no use now; and the next snapshot taken is a key (it must not be taken
        // against a key that is not the newest one kept)
        let newest = self.entries.back().map_or(0, |e| e.key);
        while self.keys.back().is_some_and(|k| k.0 > newest) {
            self.bytes -= self.keys.pop_back().unwrap().1.len();
        }
        if self.entries.is_empty() {
            self.bytes -= self.keys.drain(..).map(|k| k.1.len()).sum::<usize>();
        }
        self.since_key = KEY_EVERY;
        self.tick = 0;
        true
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let mut base = vec![0u8; 4096 + 5];
        for (i, b) in base.iter_mut().enumerate() {
            *b = (i * 7 % 251) as u8;
        }
        let mut cur = base.clone();
        cur[3] ^= 1;
        cur[100] = 9;
        cur[101] = 9;
        cur[2000..2100].fill(0x55);
        cur[4099] ^= 0xFF;
        cur[4100] ^= 0x10;
        for b in [Some(&base[..]), None] {
            let (mut enc, mut out) = (Vec::new(), Vec::new());
            encode(&cur, b, &mut enc);
            decode(&enc, b, cur.len(), &mut out);
            assert_eq!(out, cur);
            if b.is_some() {
                assert!(enc.len() < 400, "{}", enc.len());
            }
        }
        let zeros = vec![0u8; 1 << 16];
        let mut enc = Vec::new();
        encode(&zeros, None, &mut enc);
        assert_eq!(enc.len(), 8);
    }

    #[test]
    fn steps_back() {
        let mut rom = vec![0u8; 0x400];
        rom[0xB2] = 0x96;
        let mut m = Box::new(Machine::new(rom));
        let mut r = Rewind::new(2, 1);
        for i in 0..200u32 {
            m.bus.ewram[(i as usize * 13) % 0x4_0000] = i as u8;
            m.bus.framebuffer[i as usize] = i as u16;
            m.bus.clock = i as u64;
            r.frame(&mut m);
        }
        assert_eq!(r.len(), 120);
        // the newest snapshot was taken after frame 199
        assert!(r.step(&mut m));
        assert_eq!(m.bus.clock, 199);
        assert!(r.step(&mut m));
        assert_eq!(m.bus.clock, 198);
        assert_eq!(m.bus.framebuffer[199], 0, "the picture is the snapshot's");
        assert_eq!(m.bus.framebuffer[198], 198);
        assert_eq!(m.bus.rom.len(), 0x400, "the cartridge stays");
        // on again from there, and back once more past a new key
        for i in 0..70u32 {
            m.bus.clock = 1000 + i as u64;
            r.frame(&mut m);
        }
        let mut n = 0;
        while r.step(&mut m) {
            n += 1;
        }
        assert_eq!(n, 120);
        assert_eq!(r.bytes, 0);
    }
}
