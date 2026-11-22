//! The game's sound, rendered for the Mac's output device.
//!
//! Two renderings of the same music run side by side, and a short crossfade moves between them when the Enhanced
//! audio switch changes, so the switch applies while the game runs:
//!
//! - Original: the hardware mix (Direct Sound FIFOs plus the four PSG channels), held sample by sample at its own
//!   rate. Bit-exact with the console up to the device's sample rate conversion.
//! - Enhanced: mixed at the device's rate. The two Direct Sound channels are rendered as band-limited steps at their
//!   own timer rates, the PSG channels through a windowed-sinc resampler, the sum through a soft knee instead of the
//!   hardware's hard clip. Where gba-recomp's shadow mixer has proven itself against the hardware stream (M4A/MP2K,
//!   GAX and one in-house driver), its floating-point re-render of the music replaces the Direct Sound channels.
//!   NXForge adds two optional touches on top, each with its own switch: a gentle bass lift and stereo widening.
//!
//! The resamplers, the band-limited step renderer, the soft knee and the crossfade are gba-recomp's
//! (crates/recomp/src/main.rs, MIT OR Apache-2.0, JRickey and contributors), moved here because they live in its
//! command-line program rather than a library. The bass lift, the widening and the volume are NXForge's.

use std::collections::VecDeque;

pub const SINC_TAPS: usize = 24;
pub const SINC_PHASES: usize = 128;
/// Ring fill the rate control steers toward (~62 ms at the 65536 Hz tap).
pub const RING_TARGET: usize = 4096;
/// Hardware clip rail in the float mix domain (±0x200 units = ±0.5).
const RAIL: f32 = 0.5;
/// Output gain calibrating the rail toward device full scale.
const OUT_GAIN: f32 = 1.6;

#[derive(Default)]
pub struct AudioStreams {
    pub mixed: VecDeque<i16>,
    pub psg: VecDeque<f32>,
    pub fifo: [VecDeque<(i8, u32)>; 2],
    pub enhanced_on: bool,
    pub hle: VecDeque<f32>,
    pub hle_on: bool,
    pub route: [u8; 2],
    pub vol_half: [bool; 2],
    pub drops: u64,
    pub holds: u64,
    pub clipped: u64,
    pub consumed: u64,
    /// NXForge: the bass lift and the stereo widening (heard only while Enhanced audio is on), the host volume
    /// (0 to 1), and whether anything is rendering (false: the producer drops its samples instead of queueing them).
    pub bass: bool,
    pub wide: bool,
    pub volume: f32,
    pub consumer: bool,
}

fn soft_clip(x: f32) -> f32 {
    let a = x.abs();
    if a <= RAIL {
        return x;
    }
    let h = 1.0 / OUT_GAIN - RAIL;
    (RAIL + h * ((a - RAIL) / h).tanh()).copysign(x)
}

fn build_sinc_table(fc: f64) -> Vec<f32> {
    use std::f64::consts::PI;
    let center = (SINC_TAPS / 2 - 1) as f64;
    let half = SINC_TAPS as f64 / 2.0;
    let mut table = Vec::with_capacity((SINC_PHASES + 1) * SINC_TAPS);
    for p in 0..=SINC_PHASES {
        let phi = p as f64 / SINC_PHASES as f64;
        let mut row = [0.0f64; SINC_TAPS];
        let mut sum = 0.0;
        for (k, c) in row.iter_mut().enumerate() {
            let t = k as f64 - center - phi;
            let sinc = if t.abs() < 1e-9 { 2.0 * fc } else { (2.0 * PI * fc * t).sin() / (PI * t) };
            let win = if t.abs() < half { 0.5 * (1.0 + (PI * t / half).cos()) } else { 0.0 };
            *c = sinc * win;
            sum += *c;
        }
        table.extend(row.iter().map(|c| (c / sum) as f32));
    }
    table
}

struct DcBlock {
    r: f32,
    x1: f32,
    y1: f32,
}

impl DcBlock {
    fn new(out_hz: f64) -> DcBlock {
        DcBlock { r: 1.0 - (2.0 * std::f64::consts::PI * 10.0 / out_hz) as f32, x1: 0.0, y1: 0.0 }
    }
    fn next(&mut self, x: f32) -> f32 {
        let y = x - self.x1 + self.r * self.y1;
        self.x1 = x;
        self.y1 = y;
        y
    }
}

struct SincResampler {
    table: Vec<f32>,
    hist: [[f32; SINC_TAPS]; 2],
    ratio: f64,
    frac: f64,
}

impl SincResampler {
    fn new(src_hz: f64, out_hz: f64) -> SincResampler {
        SincResampler {
            table: build_sinc_table(0.45 * (out_hz / src_hz).min(1.0)),
            hist: [[0.0; SINC_TAPS]; 2],
            ratio: src_hz / out_hz,
            frac: 0.0,
        }
    }

    fn next(&mut self, q: &mut VecDeque<f32>) -> (f32, f32) {
        let pairs = (q.len() / 2) as f64;
        let err = (pairs - RING_TARGET as f64) / RING_TARGET as f64;
        self.frac += self.ratio * (1.0 + 0.02 * err.clamp(-1.0, 1.0));
        while self.frac >= 1.0 {
            self.frac -= 1.0;
            let (l, r) = match (q.pop_front(), q.pop_front()) {
                (Some(l), Some(r)) => (l, r),
                _ => (self.hist[0][SINC_TAPS - 1], self.hist[1][SINC_TAPS - 1]),
            };
            for (h, s) in self.hist.iter_mut().zip([l, r]) {
                h.copy_within(1.., 0);
                h[SINC_TAPS - 1] = s;
            }
        }
        let row = &self.table[(self.frac * SINC_PHASES as f64) as usize * SINC_TAPS..][..SINC_TAPS];
        (
            row.iter().zip(self.hist[0].iter()).map(|(c, s)| c * s).sum(),
            row.iter().zip(self.hist[1].iter()).map(|(c, s)| c * s).sum(),
        )
    }
}

struct FifoInterp {
    table: Vec<f32>,
    fut: [f32; SINC_TAPS * 2],
    pos: usize,
    y: f32,
    level: f32,
    t_next: f64,
    period: f64,
    out_step: f64,
}

impl FifoInterp {
    fn new(out_hz: f64) -> FifoInterp {
        FifoInterp {
            table: build_sinc_table(0.45),
            fut: [0.0; SINC_TAPS * 2],
            pos: 0,
            y: 0.0,
            level: 0.0,
            t_next: 512.0,
            period: 512.0,
            out_step: (1u64 << 24) as f64 / out_hz,
        }
    }

    fn next(&mut self, q: &mut VecDeque<(i8, u32)>) -> f32 {
        let target = ((1u64 << 24) as f64 / self.period / 16.0).max(64.0);
        let err = (q.len() as f64 - target) / target;
        let stepc = self.out_step * (1.0 + 0.02 * err.clamp(-1.0, 1.0));
        self.t_next -= stepc;
        while self.t_next <= 0.0 {
            let phi = (1.0 + self.t_next / stepc).clamp(0.0, 1.0);
            let new_level = match q.pop_front() {
                Some((s, p)) => {
                    self.period = (p as f64).max(1.0);
                    s as f32 * (64.0 / 32768.0)
                }
                None => self.level,
            };
            let delta = new_level - self.level;
            self.level = new_level;
            if delta != 0.0 {
                let row = &self.table[(phi * SINC_PHASES as f64) as usize * SINC_TAPS..][..SINC_TAPS];
                for (k, c) in row.iter().enumerate() {
                    self.fut[(self.pos + k) % (SINC_TAPS * 2)] += delta * c;
                }
            }
            self.t_next += self.period;
        }
        self.y = self.y * 0.9999 + self.fut[self.pos];
        self.fut[self.pos] = 0.0;
        self.pos = (self.pos + 1) % (SINC_TAPS * 2);
        self.y
    }
}

/// NXForge's bass lift: a low shelf (RBJ cookbook), +5 dB below about 160 Hz. The GBA's speaker had no bass to speak
/// of and games were mixed thin for it; on headphones a little warmth below the melody reads as fuller, not boomy.
struct LowShelf {
    b: [f32; 3],
    a: [f32; 2],
    z: [[f32; 2]; 2],
}

impl LowShelf {
    fn new(rate: f64, hz: f64, db: f64) -> LowShelf {
        use std::f64::consts::PI;
        let a = 10f64.powf(db / 40.0);
        let w0 = 2.0 * PI * hz / rate;
        let (sn, cs) = (w0.sin(), w0.cos());
        let alpha = sn / 2.0 * std::f64::consts::SQRT_2; // shelf slope 1
        let sq = 2.0 * a.sqrt() * alpha;
        let b0 = a * ((a + 1.0) - (a - 1.0) * cs + sq);
        let b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cs);
        let b2 = a * ((a + 1.0) - (a - 1.0) * cs - sq);
        let a0 = (a + 1.0) + (a - 1.0) * cs + sq;
        let a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cs);
        let a2 = (a + 1.0) + (a - 1.0) * cs - sq;
        LowShelf {
            b: [(b0 / a0) as f32, (b1 / a0) as f32, (b2 / a0) as f32],
            a: [(a1 / a0) as f32, (a2 / a0) as f32],
            z: [[0.0; 2]; 2],
        }
    }

    fn next(&mut self, ch: usize, x: f32) -> f32 {
        // transposed direct form II
        let z = &mut self.z[ch];
        let y = self.b[0] * x + z[0];
        z[0] = self.b[1] * x - self.a[0] * y + z[1];
        z[1] = self.b[2] * x - self.a[1] * y;
        y
    }
}

/// The consumer's state: made for one output rate, and made again when the device's rate changes.
pub struct Renderer {
    rate: f64,
    psg: SincResampler,
    fifo: [FifoInterp; 2],
    hle: SincResampler,
    xfade: f32,
    xfade_k: f32,
    dc: [DcBlock; 2],
    faithful_dc: [DcBlock; 2],
    mode_x: f32,
    mode_k: f32,
    step: f64,
    frac: f64,
    last: (i16, i16),
    shelf: LowShelf,
    /// how far the bass lift and the widening are in (each slews like the mode crossfade, so a switch does not click)
    bass_x: f32,
    wide_x: f32,
    /// the widening's side-signal low cut, so bass stays in the middle
    side_lp: f32,
    side_k: f32,
}

impl Renderer {
    pub fn new(rate: f64, enhanced: bool) -> Renderer {
        let src = gba_core::mem::AUDIO_RATE_HZ as f64;
        Renderer {
            rate,
            psg: SincResampler::new(src, rate),
            fifo: [FifoInterp::new(rate), FifoInterp::new(rate)],
            hle: SincResampler::new(src, rate),
            xfade: 0.0,
            xfade_k: (1.0 / (0.040 * rate)) as f32,
            dc: [DcBlock::new(rate), DcBlock::new(rate)],
            faithful_dc: [DcBlock::new(rate), DcBlock::new(rate)],
            mode_x: if enhanced { 1.0 } else { 0.0 },
            mode_k: (1.0 / (0.040 * rate)) as f32,
            step: src / rate,
            frac: 0.0,
            last: (0, 0),
            shelf: LowShelf::new(rate, 160.0, 5.0),
            bass_x: 0.0,
            wide_x: 0.0,
            side_lp: 0.0,
            side_k: (2.0 * std::f64::consts::PI * 250.0 / rate) as f32,
        }
    }

    pub fn rate(&self) -> f64 {
        self.rate
    }

    /// Fill `out` (interleaved stereo) from the rings.
    pub fn render(&mut self, st: &mut AudioStreams, out: &mut [f32]) {
        st.consumed += (out.len() / 2) as u64;
        for frame in out.chunks_exact_mut(2) {
            // Enhanced (always computed, so its rings stay drained and the switch is seamless)
            let (pl, pr) = self.psg.next(&mut st.psg);
            let a = self.fifo[0].next(&mut st.fifo[0]) * if st.vol_half[0] { 0.5 } else { 1.0 };
            let b = self.fifo[1].next(&mut st.fifo[1]) * if st.vol_half[1] { 0.5 } else { 1.0 };
            let (hl, hr) = self.hle.next(&mut st.hle);
            let hr = hr * if st.vol_half[0] { 0.5 } else { 1.0 };
            let hl = hl * if st.vol_half[1] { 0.5 } else { 1.0 };
            let target = if st.hle_on { 1.0 } else { 0.0 };
            self.xfade += (target - self.xfade) * self.xfade_k;
            let xf = self.xfade;
            let (mut fl, mut fr) = (0.0, 0.0);
            if st.route[0] & 2 != 0 {
                fl += a;
            }
            if st.route[0] & 1 != 0 {
                fr += a;
            }
            if st.route[1] & 2 != 0 {
                fl += b;
            }
            if st.route[1] & 1 != 0 {
                fr += b;
            }
            let (mut gl, mut gr) = (0.0, 0.0);
            if st.route[0] & 2 != 0 || st.route[1] & 2 != 0 {
                gl = hl;
            }
            if st.route[0] & 1 != 0 || st.route[1] & 1 != 0 {
                gr = hr;
            }
            let l = pl + fl * (1.0 - xf) + gl * xf;
            let r = pr + fr * (1.0 - xf) + gr * xf;
            if l.abs() > RAIL || r.abs() > RAIL {
                st.clipped += 1;
            }
            let (mut el, mut er) = (self.dc[0].next(soft_clip(l)), self.dc[1].next(soft_clip(r)));
            // NXForge: the bass lift, then the widening (mid/side, with the side's lows left in the middle)
            self.bass_x += ((st.bass as u8 as f32) - self.bass_x) * self.mode_k;
            let (sl, sr) = (self.shelf.next(0, el), self.shelf.next(1, er));
            el += (sl - el) * self.bass_x;
            er += (sr - er) * self.bass_x;
            self.wide_x += ((st.wide as u8 as f32) - self.wide_x) * self.mode_k;
            let side = (el - er) * 0.5;
            self.side_lp += (side - self.side_lp) * self.side_k;
            let extra = (side - self.side_lp) * 0.6 * self.wide_x;
            el += extra;
            er -= extra;

            // Original (also always computed, also drained)
            let pairs = (st.mixed.len() / 2) as f64;
            let err = (pairs - RING_TARGET as f64) / RING_TARGET as f64;
            self.frac += self.step * (1.0 + 0.02 * err.clamp(-1.0, 1.0));
            while self.frac >= 1.0 {
                self.frac -= 1.0;
                match (st.mixed.pop_front(), st.mixed.pop_front()) {
                    (Some(l), Some(r)) => self.last = (l, r),
                    _ => st.holds += 1,
                }
            }
            let ol = self.faithful_dc[0].next(self.last.0 as f32 / 32768.0);
            let or = self.faithful_dc[1].next(self.last.1 as f32 / 32768.0);

            let target = if st.enhanced_on { 1.0 } else { 0.0 };
            self.mode_x += (target - self.mode_x) * self.mode_k;
            let l = ol + (el - ol) * self.mode_x;
            let r = or + (er - or) * self.mode_x;
            frame[0] = (l * OUT_GAIN).clamp(-1.0, 1.0) * st.volume;
            frame[1] = (r * OUT_GAIN).clamp(-1.0, 1.0) * st.volume;
        }
    }
}

/// The producer's side, once per emulated frame: this frame's samples from the machine's taps into the rings
/// (gba-recomp's play loop, handoff_audio).
pub fn handoff(bus: &mut gba_core::MemMap, st: &mut AudioStreams) {
    use gba_core::Bus as _;
    if !st.consumer {
        bus.audio_buf.clear();
        bus.psg_tap.clear();
        bus.hle_tap.clear();
        bus.fifo_tap[0].clear();
        bus.fifo_tap[1].clear();
        return;
    }
    let cnt_h = bus.read16(0x0400_0082);
    st.route = [(cnt_h >> 8 & 3) as u8, (cnt_h >> 12 & 3) as u8];
    st.vol_half = [cnt_h & 4 == 0, cnt_h & 8 == 0];
    for pair in bus.audio_buf.chunks_exact(2) {
        if st.mixed.len() < 65536 {
            st.mixed.push_back(pair[0]);
            st.mixed.push_back(pair[1]);
        } else {
            st.drops += 1;
        }
    }
    bus.audio_buf.clear();
    for pair in bus.psg_tap.chunks_exact(2) {
        if st.psg.len() < 65536 {
            st.psg.push_back(pair[0] as f32 / 32768.0);
            st.psg.push_back(pair[1] as f32 / 32768.0);
        } else {
            st.drops += 1;
        }
    }
    bus.psg_tap.clear();
    let live = bus.mp2k.as_deref().is_some_and(|h| h.live())
        || bus.gax.as_deref().is_some_and(|g| g.live())
        || bus.rdrv.as_deref().is_some_and(|r| r.live());
    if let Some(h) = bus.mp2k.as_deref_mut() {
        h.vf.reverted.take();
    } else if let Some(g) = bus.gax.as_deref_mut() {
        g.vf.reverted.take();
    } else if let Some(r) = bus.rdrv.as_deref_mut() {
        r.vf.reverted.take();
    }
    if live {
        for pair in bus.hle_tap.chunks_exact(2) {
            if st.hle.len() < 65536 {
                st.hle.push_back(pair[0]);
                st.hle.push_back(pair[1]);
            } else {
                st.drops += 1;
            }
        }
    } else {
        st.hle.clear();
    }
    bus.hle_tap.clear();
    if !live {
        st.hle_on = false;
    } else if st.hle.len() / 2 >= RING_TARGET / 2 {
        st.hle_on = true;
    }
    for f in 0..2 {
        let events = std::mem::take(&mut bus.fifo_tap[f]);
        for e in events {
            if st.fifo[f].len() < 32768 {
                st.fifo[f].push_back(e);
            } else {
                st.drops += 1;
            }
        }
    }
}

/// The audio engine a game links, and what the Enhanced path does with it (gba-recomp's arm_audio_hle).
pub fn arm_engine(m: &mut gba_core::Machine) -> String {
    match gba_core::engine::classify(&m.bus.rom) {
        gba_core::engine::Engine::M4a(sigs) => {
            m.bus.mp2k = Some(Box::new(gba_core::mp2k::Mp2kHle::new(&sigs)));
            "M4A/MP2K: music re-rendered in floating point once it matches the hardware stream".into()
        }
        gba_core::engine::Engine::Gax(ver) => {
            if let Some(sig) = gba_core::gax::detect_v1(&m.bus.rom) {
                m.bus.gax = Some(Box::new(gba_core::gax::GaxHle::new(sig)));
                "GAX: music re-rendered in floating point once it matches the hardware stream".into()
            } else if ver.is_some() {
                m.bus.gax = Some(Box::new(gba_core::gax::GaxHle::new_v3()));
                "GAX: music re-rendered in floating point once it matches the hardware stream".into()
            } else {
                "GAX (early revision): each channel band-limited at the Mac's rate".into()
            }
        }
        gba_core::engine::Engine::Rdiag => {
            if let Some(sig) = gba_core::rdrv::detect(&m.bus.rom) {
                m.bus.rdrv = Some(Box::new(gba_core::rdrv::RdrvHle::new(sig)));
                "in-house driver: music re-rendered in floating point once it matches the hardware stream".into()
            } else {
                "in-house driver: each channel band-limited at the Mac's rate".into()
            }
        }
        other => format!("{}: each channel band-limited at the Mac's rate", other.describe()),
    }
}
