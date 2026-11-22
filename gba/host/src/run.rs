//! nxgba-run: a GBA game run with no window, for the converter's trial run and for tests.
//!
//!   nxgba-run <rom.gba> [--lib game.dylib] [--frames N] [--demo] [--input script] [--sav file]
//!             [--png out.png] [--sheet out.png [--every K] [--cols C]] [--color raw|lcd]
//!             [--wav out.wav [--original]] [--state-check] [--misses file] [--json]
//!
//! Without --lib the interpreter runs the game (the reference the recompiled run is compared with: --json prints the
//! last frame's hash either way). --demo taps Start and A now and then, as gba-recomp's build profile does; --input
//! is a gba-recomp input script ("gba-input v1", then "<frame> <hex mask of buttons up>" lines).
//! --state-check saves a state half way, runs on, loads it and runs the same frames again: the two runs must end on
//! the same picture. --wav renders the sound as the player would (Enhanced unless --original) at 48 kHz.

use nxgba::NxGba;

fn crc32(data: &[u8], mut c: u32) -> u32 {
    c = !c;
    for &b in data {
        c ^= b as u32;
        for _ in 0..8 {
            c = if c & 1 != 0 { 0xEDB8_8320 ^ (c >> 1) } else { c >> 1 };
        }
    }
    !c
}

/// A PNG with stored (uncompressed) data: no dependency, and the pictures are small.
fn write_png(path: &str, w: u32, h: u32, rgba: &[u8]) -> Result<(), String> {
    let mut raw = Vec::with_capacity((w as usize * 4 + 1) * h as usize);
    for row in rgba.chunks_exact(w as usize * 4) {
        raw.push(0);
        raw.extend_from_slice(row);
    }
    let mut z = vec![0x78, 0x01];
    let (mut a, mut b) = (1u32, 0u32);
    for &x in &raw {
        a = (a + x as u32) % 65521;
        b = (b + a) % 65521;
    }
    let mut chunks = raw.chunks(65535).peekable();
    while let Some(c) = chunks.next() {
        z.push(chunks.peek().is_none() as u8);
        z.extend_from_slice(&(c.len() as u16).to_le_bytes());
        z.extend_from_slice(&(!(c.len() as u16)).to_le_bytes());
        z.extend_from_slice(c);
    }
    z.extend_from_slice(&(b << 16 | a).to_be_bytes());
    let mut out = b"\x89PNG\r\n\x1a\n".to_vec();
    let mut chunk = |tag: &[u8; 4], data: &[u8]| {
        out.extend_from_slice(&(data.len() as u32).to_be_bytes());
        out.extend_from_slice(tag);
        out.extend_from_slice(data);
        out.extend_from_slice(&crc32(data, crc32(tag, 0)).to_be_bytes());
    };
    let mut ihdr = Vec::new();
    ihdr.extend_from_slice(&w.to_be_bytes());
    ihdr.extend_from_slice(&h.to_be_bytes());
    ihdr.extend_from_slice(&[8, 6, 0, 0, 0]);
    chunk(b"IHDR", &ihdr);
    chunk(b"IDAT", &z);
    chunk(b"IEND", &[]);
    std::fs::write(path, out).map_err(|e| format!("{path}: {e}"))
}

fn write_wav(path: &str, samples: &[f32], rate: u32) -> Result<(), String> {
    let n = (samples.len() * 2) as u32;
    let mut w = Vec::with_capacity(44 + n as usize);
    w.extend_from_slice(b"RIFF");
    w.extend_from_slice(&(36 + n).to_le_bytes());
    w.extend_from_slice(b"WAVEfmt ");
    w.extend_from_slice(&16u32.to_le_bytes());
    w.extend_from_slice(&1u16.to_le_bytes());
    w.extend_from_slice(&2u16.to_le_bytes());
    w.extend_from_slice(&rate.to_le_bytes());
    w.extend_from_slice(&(rate * 4).to_le_bytes());
    w.extend_from_slice(&4u16.to_le_bytes());
    w.extend_from_slice(&16u16.to_le_bytes());
    w.extend_from_slice(b"data");
    w.extend_from_slice(&n.to_le_bytes());
    for s in samples {
        w.extend_from_slice(&((s.clamp(-1.0, 1.0) * 32767.0) as i16).to_le_bytes());
    }
    std::fs::write(path, w).map_err(|e| format!("{path}: {e}"))
}

fn demo_keys(frame: u64) -> u16 {
    let mut keys = 0x3FFu16;
    let phase = frame % 180;
    if frame >= 240 {
        if phase < 10 {
            keys &= !(1 << 3);
        } else if (60..70).contains(&phase) {
            keys &= !(1 << 0);
        }
    }
    keys
}

fn load_input(path: &str) -> Result<Vec<(u64, u16)>, String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{path}: {e}"))?;
    let mut lines = text.lines();
    if lines.next().map(str::trim) != Some("gba-input v1") {
        return Err(format!("{path}: not a gba-input v1 file"));
    }
    let mut v = Vec::new();
    for l in lines.map(str::trim).filter(|l| !l.is_empty()) {
        let (f, k) = l.split_once(' ').ok_or_else(|| format!("{path}: bad line {l:?}"))?;
        v.push((f.parse().map_err(|_| format!("{path}: bad frame in {l:?}"))?, u16::from_str_radix(k, 16).map_err(|_| format!("{path}: bad mask in {l:?}"))?));
    }
    v.sort();
    Ok(v)
}

fn fb_hash(px: &[u16]) -> u64 {
    let mut h = 0xcbf2_9ce4_8422_2325u64;
    for p in px {
        for b in p.to_le_bytes() {
            h ^= b as u64;
            h = h.wrapping_mul(0x1_0000_01b3);
        }
    }
    h
}

fn main() {
    if let Err(e) = real_main() {
        eprintln!("nxgba-run: {e}");
        std::process::exit(1);
    }
}

fn real_main() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (mut rom, mut lib, mut sav, mut png, mut sheet, mut wav, mut input, mut misses) = (None, None, None, None, None, None, None, None);
    let (mut frames, mut every, mut cols, mut color) = (600u64, 0u64, 6usize, 1u32);
    let (mut demo, mut original, mut state_check, mut json) = (false, false, false, false);
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let mut val = |name: &str| it.next().cloned().ok_or(format!("{name} needs a value"));
        match a.as_str() {
            "--lib" => lib = Some(val("--lib")?),
            "--frames" => frames = val("--frames")?.parse().map_err(|_| "bad --frames")?,
            "--every" => every = val("--every")?.parse().map_err(|_| "bad --every")?,
            "--cols" => cols = val("--cols")?.parse().map_err(|_| "bad --cols")?,
            "--sav" => sav = Some(val("--sav")?),
            "--png" => png = Some(val("--png")?),
            "--sheet" => sheet = Some(val("--sheet")?),
            "--wav" => wav = Some(val("--wav")?),
            "--input" => input = Some(load_input(&val("--input")?)?),
            "--misses" => misses = Some(val("--misses")?),
            "--color" => color = (val("--color")? != "raw") as u32,
            "--demo" => demo = true,
            "--original" => original = true,
            "--state-check" => state_check = true,
            "--json" => json = true,
            other if rom.is_none() && !other.starts_with("--") => rom = Some(other.to_string()),
            other => return Err(format!("unexpected argument {other:?}")),
        }
    }
    let rom = rom.ok_or("usage: nxgba-run <rom.gba> [--lib game.dylib] [--frames N] [--demo] [--png out.png] [--sheet out.png] [--wav out.wav] [--json]")?;
    let mut g = NxGba::open(&rom, lib.as_deref(), sav.as_deref())?;
    let t0 = std::time::Instant::now();
    let keys_at = |f: u64| -> u16 {
        if let Some(s) = &input {
            match s.partition_point(|&(sf, _)| sf <= f) {
                0 => 0x3FF,
                n => s[n - 1].1,
            }
        } else if demo {
            demo_keys(f)
        } else {
            0x3FF
        }
    };
    if sheet.is_some() && every == 0 {
        every = (frames / 24).max(1);
    }
    let mut shots: Vec<Vec<u8>> = Vec::new();
    let mut audio: Vec<f32> = Vec::new();
    if wav.is_some() {
        let mut st = g.streams.lock().unwrap();
        st.consumer = true;
        st.enhanced_on = !original;
    }
    let mut renderer = nxgba::audio::Renderer::new(48000.0, !original);
    let mut wanted = 0f64;
    let mut state_hash: Option<(u64, u64)> = None; // (frame the state was taken at, hash at the end of the first pass)
    let mut f = 0u64;
    while f < frames {
        g.machine().bus.keys = keys_at(f);
        if !g.run_frame() {
            return Err(format!("the game stopped making frames at frame {f} (stall guard)"));
        }
        f += 1;
        if wav.is_some() {
            // as much sound as one frame lasts (59.7275 frames a second)
            wanted += 48000.0 / 59.7275;
            let n = wanted as usize;
            wanted -= n as f64;
            let mut buf = vec![0f32; n * 2];
            renderer.render(&mut g.streams.lock().unwrap(), &mut buf);
            audio.extend_from_slice(&buf);
        }
        if every > 0 && f % every == 0 && sheet.is_some() {
            let mut px = vec![0u8; 240 * 160 * 4];
            nxgba::rgba(&g.machine().bus.framebuffer, &mut px, color);
            shots.push(px);
        }
        if state_check && state_hash.is_none() && f == frames / 2 {
            g.state_save(1);
            state_hash = Some((f, 0));
        } else if state_check && f == frames {
            match state_hash {
                Some((at, 0)) => {
                    // first pass done: back to the state, and the same frames again
                    state_hash = Some((at, fb_hash(&g.machine().bus.framebuffer) | 1));
                    g.state_load(1);
                    f = at;
                    shots.truncate((at / every.max(1)) as usize);
                }
                Some((_, h)) => {
                    let again = fb_hash(&g.machine().bus.framebuffer) | 1;
                    if again != h {
                        return Err(format!("state check failed: the run after loading the state ended on a different picture ({again:016x} against {h:016x})"));
                    }
                    eprintln!("state check passed: saved at frame {}, loaded, and the run ended on the same picture", frames / 2);
                }
                None => {}
            }
        }
    }
    let secs = t0.elapsed().as_secs_f64();
    let mut px = vec![0u8; 240 * 160 * 4];
    nxgba::rgba(&g.machine().bus.framebuffer, &mut px, color);
    if let Some(p) = &png {
        write_png(p, 240, 160, &px)?;
    }
    if let Some(p) = &sheet {
        let cols = cols.max(1).min(shots.len().max(1));
        let rows = shots.len().div_ceil(cols).max(1);
        let (w, h) = (cols * 244 + 4, rows * 164 + 4);
        let mut img = vec![24u8; w * h * 4];
        for a in img.chunks_exact_mut(4) {
            a[3] = 255;
        }
        for (i, s) in shots.iter().enumerate() {
            let (cx, cy) = (4 + (i % cols) * 244, 4 + (i / cols) * 164);
            for y in 0..160 {
                let d = ((cy + y) * w + cx) * 4;
                img[d..d + 960].copy_from_slice(&s[y * 960..y * 960 + 960]);
            }
        }
        write_png(p, w as u32, h as u32, &img)?;
    }
    if let Some(p) = &wav {
        write_wav(p, &audio, 48000)?;
    }
    let hash = fb_hash(&g.machine().bus.framebuffer);
    let added = g.misses_write(misses.as_deref())?;
    let i = g.info();
    let total = i.native_blocks + i.fallback_steps;
    if json {
        let (title, code) = nxgba::header(&g.machine().bus.rom);
        println!(
            "{{\"frames\": {}, \"hash\": \"{hash:016x}\", \"seconds\": {secs:.3}, \"fps\": {:.1}, \"blocks\": {}, \"native_blocks\": {}, \"fallback_steps\": {}, \"native_share\": {:.4}, \"misses_rom\": {}, \"misses_ram\": {}, \"labels_added\": {added}, \"save_kind\": {}, \"save_bytes\": {}, \"rtc\": {}, \"hle_live\": {}, \"title\": \"{}\", \"code\": \"{}\", \"sha1\": \"{}\", \"sha256\": \"{}\"}}",
            i.frames,
            i.frames as f64 / secs.max(1e-9),
            i.blocks,
            i.native_blocks,
            i.fallback_steps,
            if total == 0 { 0.0 } else { i.native_blocks as f64 / total as f64 },
            i.misses_rom,
            i.misses_ram,
            i.save_kind,
            i.save_bytes,
            i.has_rtc,
            i.hle_live,
            title.replace(['"', '\\'], ""),
            code.replace(['"', '\\'], ""),
            g.sha1(),
            g.sha256(),
        );
    } else {
        println!("frames: {} hash: {hash:016x} native_blocks: {} fallback_steps: {} ({:.0} fps)", i.frames, i.native_blocks, i.fallback_steps, i.frames as f64 / secs.max(1e-9));
    }
    Ok(())
}
