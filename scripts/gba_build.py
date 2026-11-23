#!/usr/bin/env python3
"""Convert a Game Boy Advance game into a Mac app (gba/README.md).

  scripts/gba_build.py <game.gba | game.zip> [--home DIR] [-o <Name>.app] [--work-dir DIR] [--progress json]
                       [--name NAME] [--fresh] [--trial-frames N] [--info]

The game's code is translated to C by gba-recomp (gba/ENGINE, assembled by scripts/gba_engine.py), compiled and linked into
game.dylib, and packaged with NXForge's GBA player (gba/host). Stages, in order:

  Read ROM, Check profile, Capture RAM code, Find code, Write C, Compile, Link, Trial run, Package

With --progress json every line on stdout is one JSON event, the ones the Converter app reads from the Switch build
script: stage / step / progress / stage_end / say, the last "say" being "done: <path>.app".

A conversion can be paused at any moment (the app stops and continues the processes) and picked up after being
stopped: every stage leaves its result in the work folder and is skipped when its inputs have not changed, and Compile
keeps each unit's object file, so it continues at the unit it had reached. --fresh starts over.

--info prints what the app needs to list the game (title, code, title ID, SHA-1) as one JSON line and stops.
"""
import argparse
import hashlib
import json
import os
import plistlib
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor, as_completed

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import gba_engine as gba  # noqa: E402

STAGES = ["Read ROM", "Check profile", "Capture RAM code", "Find code", "Write C", "Compile", "Link", "Trial run", "Package"]
SAVE_KINDS = ["None", "SRAM", "Flash 64K", "Flash 128K", "EEPROM"]
UNIT_BYTES = 2 << 20


# Bump when the link step's flags change, so a kept build links again.
LINK_FLAGS_VERSION = "exports-only 1"
PACKED_MAGIC = b"NXGBAZ1\0"   # gba/host/src/lib.rs read_rom


def pack_rom(src, dst) -> bool:
    """The cartridge packed for the app: PACKED_MAGIC, its size (u64 little-endian), one LZFSE stream (Apple's
    libcompression: about half the bytes, unpacked in a few milliseconds when the game starts). False when it cannot
    be packed here (not a Mac), and the plain image goes in instead."""
    if sys.platform != "darwin":
        return False
    import ctypes
    try:
        lib = ctypes.CDLL("/usr/lib/libcompression.dylib")
    except OSError:
        return False
    enc = lib.compression_encode_buffer
    enc.restype = ctypes.c_size_t
    enc.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_uint32]
    dec = lib.compression_decode_buffer
    dec.restype, dec.argtypes = enc.restype, enc.argtypes
    with open(src, "rb") as f:
        rom = f.read()
    out = ctypes.create_string_buffer(len(rom) + 4096)
    n = enc(out, len(out), rom, len(rom), None, 0x801)
    if not n or n >= len(rom):
        return False
    packed = bytes(out.raw[:n])
    back = ctypes.create_string_buffer(len(rom))
    if dec(back, len(rom), packed, n, None, 0x801) != len(rom) or back.raw != rom:   # never ship a cartridge that does not unpack to itself
        return False
    with open(dst, "wb") as f:
        f.write(PACKED_MAGIC + struct.pack("<Q", len(rom)) + packed)
    return True


class Stop(Exception):
    pass


class Progress:
    def __init__(self, as_json):
        self.json = as_json
        self.k = 0
        self.t0 = time.time()

    def emit(self, **ev):
        if self.json:
            print(json.dumps(ev), flush=True)

    def stage(self, name, step=""):
        self.k = STAGES.index(name) + 1
        self.t0 = time.time()
        self.name = name
        self.emit(ev="stage", k=self.k, n=len(STAGES), name=name, step=step)
        if not self.json:
            print(f"[{self.k}/{len(STAGES)}] {name}", flush=True)

    def step(self, text):
        self.emit(ev="step", step=text)
        if not self.json:
            print(f"      {text}", flush=True)

    def progress(self, step, done, total, unit="", eta=None):
        ev = dict(ev="progress", step=step, frac=(done / total if total else 0), done=done, total=total, unit=unit)
        if eta is not None:
            ev["eta"] = eta
        self.emit(**ev)

    def end(self, summary, ok=True):
        el = time.time() - self.t0
        self.emit(ev="stage_end", ok=ok, elapsed=round(el, 1), summary=summary)
        if not self.json:
            print(f"      {summary} ({el:.1f} s)", flush=True)
        return el

    def say(self, msg):
        self.emit(ev="say", msg=msg)
        if not self.json:
            print(msg, flush=True)


def read_rom(path):
    """The ROM's bytes and its file name: a .gba, or the one .gba inside a .zip."""
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            names = [n for n in z.namelist() if n.lower().endswith((".gba", ".agb", ".bin"))]
            if not names:
                raise Stop(f"{os.path.basename(path)} holds no .gba file")
            return z.read(names[0]), os.path.basename(names[0])
    with open(path, "rb") as f:
        return f.read(), os.path.basename(path)


def header(rom):
    def text(b):
        return "".join(chr(c) for c in b if 32 <= c < 127).strip()
    if len(rom) < 0xC0:
        raise Stop("not a Game Boy Advance ROM: shorter than its header")
    comp = (-(sum(rom[0xA0:0xBD]) + 0x19)) & 0xFF
    return dict(title=text(rom[0xA0:0xAC]), code=text(rom[0xAC:0xB0]), maker=text(rom[0xB0:0xB2]), version=rom[0xBC],
                checksum_ok=comp == rom[0xBD], fixed_ok=rom[0xB2] == 0x96)


def title_id(h):
    """NXForge keeps every game under a 16-digit title ID. A GBA game's: 0BA0, the game code's four characters as
    hex, the header's version byte, 00. Read from the cartridge header alone, so the app can list a game without
    hashing it."""
    code = (h["code"] or "????")[:4].ljust(4, "?")
    return "0BA0" + code.encode("ascii", "replace").hex().upper() + f"{h['version']:02X}00"


def clean_name(file_name):
    """"Legend of Zelda, The - The Minish Cap (Europe) (En,Fr,De,Es,It).gba" -> "The Legend of Zelda - The Minish Cap"."""
    n = os.path.splitext(file_name)[0]
    n = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", n).strip()
    m = re.match(r"^(.*?), (The|A|An)( - .*)?$", n)
    if m:
        n = f"{m.group(2)} {m.group(1)}{m.group(3) or ''}"
    return n or "Game"


def profile_for(code, sha1):
    """library/gba/<CODE>-<first 8 of the SHA-1>.md, else <CODE>.md: a tested game's notes, and beside it an optional
    .labels file of entry points found by play (added to this Mac's own before the build)."""
    d = os.path.join(ROOT, "library", "gba")
    for stem in (f"{code}-{sha1[:8]}", code):
        p = os.path.join(d, stem + ".md")
        if os.path.exists(p):
            meta = {}
            with open(p) as f:
                lines = f.read().split("\n")
            if lines and lines[0].strip() == "---":
                for line in lines[1:]:
                    if line.strip() == "---":
                        break
                    if ":" in line:
                        k, v = line.split(":", 1)
                        meta[k.strip()] = v.strip()
            labels = os.path.join(d, stem + ".labels")
            return p, meta, labels if os.path.exists(labels) else None
    return None, {}, None


def labels_dir():
    base = os.environ.get("XDG_CONFIG_HOME") or (os.path.expanduser("~/Library/Application Support") if sys.platform == "darwin" else os.path.expanduser("~/.config"))
    return os.path.join(base, "gba-recomp", "labels")


def merge_labels(src, sha256):
    """Add a profile's entry points to this Mac's label file for the ROM (gba-recomp's line format: a two-line
    header, then "rom|iwram|ewram <hex address> a|t" lines). Returns how many were new."""
    dst = os.path.join(labels_dir(), sha256 + ".labels")
    with open(src) as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    if not any(ln == f"rom-sha256 {sha256}" for ln in lines):
        return 0   # a label file for another ROM
    entries = [ln for ln in lines if ln.split(" ")[0] in ("rom", "iwram", "ewram")]
    have = set()
    if os.path.exists(dst):
        with open(dst) as f:
            have = {ln.strip() for ln in f}
    new = [ln for ln in entries if ln not in have]
    if new:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "a") as f:
            if not have:
                f.write(f"gba-labels v1\nrom-sha256 {sha256}\n")
            f.write("".join(n + "\n" for n in new))
    return len(new)


def file_sha(path):
    h = hashlib.sha1()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()


class Build:
    def __init__(self, a):
        self.a = a
        self.p = Progress(a.progress == "json")
        self.env = gba.env()
        self.tools = gba.where()
        self.times = {}
        self.report = {}

    # -- the work folder's record of what is done --
    def load_state(self):
        try:
            with open(os.path.join(self.work, "state.json")) as f:
                self.state = json.load(f)
        except (OSError, ValueError):
            self.state = {}
        if self.state.get("key") != self.key:
            self.state = {"key": self.key}

    def keep(self, **kv):
        self.state.update(kv)
        tmp = os.path.join(self.work, "state.json.tmp")
        with open(tmp, "w") as f:
            json.dump(self.state, f, indent=1)
        os.replace(tmp, os.path.join(self.work, "state.json"))

    def end(self, summary, reused=False):
        name = self.p.name
        self.times[name] = self.p.end(summary + (", reused" if reused else ""))

    def run(self):
        a, p = self.a, self.p
        # 1 Read ROM
        if not a.info:
            p.stage("Read ROM", os.path.basename(a.rom))
        rom, rom_name = read_rom(a.rom)
        h = header(rom)
        if not h["fixed_ok"]:
            raise Stop("not a Game Boy Advance ROM: the header's fixed byte is wrong")
        sha1, sha256 = hashlib.sha1(rom).hexdigest(), hashlib.sha256(rom).hexdigest()
        tid = title_id(h)
        name = a.name or clean_name(os.path.basename(a.rom))
        info = dict(title=h["title"], code=h["code"], maker=h["maker"], version=h["version"], titleID=tid, sha1=sha1, sha256=sha256, bytes=len(rom), name=name,
                    checksumOK=h["checksum_ok"])
        if a.info:
            print(json.dumps(info), flush=True)
            return None
        home = os.path.abspath(a.home) if a.home else None
        safe = name.replace(":", " - ").replace("/", " - ")
        out = os.path.abspath(a.out or os.path.join(home or os.path.dirname(os.path.abspath(a.rom)), safe + ".app"))
        self.work = os.path.abspath(a.work_dir or os.path.join(home or os.path.dirname(out), tid + "_build"))
        if a.fresh and os.path.isdir(self.work):
            shutil.rmtree(self.work)
        os.makedirs(self.work, exist_ok=True)
        self.key = f"{sha1} {self.tools['commit']} {hashlib.sha1(gba.stamp().encode()).hexdigest()[:8]} unit{UNIT_BYTES}"
        self.load_state()
        rom_path = os.path.join(self.work, "game.gba")
        if not os.path.exists(rom_path) or os.path.getsize(rom_path) != len(rom):
            with open(rom_path, "wb") as f:
                f.write(rom)
        self.end(f"{h['title'] or name} ({h['code']}), {len(rom) / (1 << 20):.0f} MB" + ("" if h["checksum_ok"] else ", header checksum wrong"))

        # 2 Check profile
        p.stage("Check profile", f"{h['code']}-{sha1[:8]}")
        prof, meta, labels = profile_for(h["code"], sha1)
        added = merge_labels(labels, sha256) if labels else 0
        player = self.tools["player"]
        if gba.stale():
            # the first conversion on this Mac, or the first after an engine update: fetch gba-recomp and build it and the player
            if not shutil.which("cargo", path=self.env["PATH"]):
                raise Stop("Game Boy Advance games need Rust to build their engine once: install it from rustup.rs, then convert again")
            p.step("Building the Game Boy Advance engine (once, a few minutes)")
            r = subprocess.run([sys.executable, os.path.join(ROOT, "scripts", "gba_engine.py"), "build"], env=self.env, capture_output=True, text=True)
            if r.returncode != 0:
                tail = (r.stderr or r.stdout).strip().splitlines()[-6:]
                for line in tail:
                    p.say(line)
                raise Stop("the Game Boy Advance engine did not build: " + (tail[-1] if tail else f"exit {r.returncode}"))
        self.report["profile"] = dict(file=os.path.relpath(prof, ROOT) if prof else None, status=meta.get("status"), labelsAdded=added)
        self.end((f"tested profile: {meta.get('status', 'listed')}" if prof else "no profile yet: converted from the cartridge alone")
                 + (f", {added} entry points from it" if added else ""))

        # 3-5 Capture RAM code, Find code, Write C: one run of the recompiler, which reports as it goes
        units = self.translate(rom_path)

        # 6 Compile
        objs = self.compile(units)

        # 7 Link
        lib = self.link(objs)

        # 8 Trial run (and a second pass over what it found)
        trial = self.trial(rom_path, lib, sha256)
        if trial["missesRom"] + trial["missesRam"] > 0 and not self.state.get("second_pass") and not a.one_pass:
            p.step(f"Second pass: {trial['missesRom'] + trial['missesRam']} entry points the trial run found")
            self.keep(second_pass=True, emitted=None, linked=None, trial=None)
            first = dict(trial)
            units = self.translate(rom_path, second=True)
            objs = self.compile(units, second=True)
            lib = self.link(objs, second=True)
            trial = self.trial(rom_path, lib, sha256, second=True)
            trial["firstPass"] = dict(blocks=first["blocks"], missesRom=first["missesRom"], missesRam=first["missesRam"], nativeShare=first["nativeShare"])
        self.end(f"{trial['frames']:,} frames at {trial['fps']:.0f} fps, {trial['nativeShare'] * 100:.1f}% of the game's code steps translated, "
                 f"{trial['missesRom'] + trial['missesRam']} entry points left for the interpreter")

        # 9 Package
        p.stage("Package", os.path.basename(out))
        self.package(out, name, tid, info, rom_path, lib, trial, player, meta)
        self.end(f"{os.path.basename(out)}, {self.size(out) / (1 << 20):.0f} MB")
        if a.cleanup:
            for n in os.listdir(self.work):
                if n.endswith((".c", ".o")) or n == "game.gba":
                    os.remove(os.path.join(self.work, n))
        p.say(f"done: {out}")
        return out

    def translate(self, rom_path, second=False):
        p = self.p
        stem = os.path.join(self.work, "game")
        tag = "Second pass: " if second else ""
        if self.state.get("emitted"):
            units = self.state["emitted"]
            if all(os.path.exists(os.path.join(self.work, u)) for u in units):
                for s in ("Capture RAM code", "Find code", "Write C"):
                    p.stage(s)
                    self.end({"Capture RAM code": "kept from the last run", "Find code": f"{self.state.get('blocks', 0):,} blocks", "Write C": f"{len(units)} units"}[s], reused=True)
                return units
        for n in os.listdir(self.work):
            if re.match(r"game\.\d+\.c$", n):
                os.remove(os.path.join(self.work, n))
        env = dict(self.env, RECOMP_EMIT_ONLY="1", RECOMP_UNIT_BYTES=str(UNIT_BYTES), RECOMP_PROGRESS="lines", RECOMP_KEEP_C="1")
        if not second:
            p.stage("Capture RAM code", "Running the game to see the code it copies into memory")
        cmd = [self.tools["recomp"], "build", rom_path, "--ram", "--out", stem + ".dylib"]
        proc = subprocess.Popen(cmd, cwd=self.work, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
        self.child = proc
        phase, seeds, blocks, log = 0, 0, 0, []
        for line in proc.stdout or []:
            line = line.rstrip()
            log.append(line)
            m = re.match(r"PROGRESS (\d+) (.*)", line)
            if m:
                pct, msg = int(m.group(1)), m.group(2)
                if phase == 0 and "charting" in msg:
                    phase = 1
                    if not second:
                        self.end(f"{seeds:,} entry points seen running")
                        p.stage("Find code", "Following every path the code can take")
                    else:
                        p.step(tag + "Find code")
                elif phase == 1 and "translating to C" in msg:
                    phase = 2
                    if not second:
                        self.end(f"{blocks:,} blocks" if blocks else "charted")
                        p.stage("Write C", msg)
                    else:
                        p.step(tag + "Write C")
                p.progress((tag + msg) if second else msg, pct, 100, "%")
                continue
            m = re.match(r"profiled (\d+) RAM entry points", line)
            if m:
                seeds = int(m.group(1))
            m = re.match(r"blocks: (\d+)", line)
            if m:
                blocks = int(m.group(1))
            if line:
                p.say(line)
        rc = proc.wait()
        self.child = None
        if rc != 0:
            raise Stop("the recompiler stopped: " + (log[-1] if log else f"exit {rc}"))
        units = sorted((n for n in os.listdir(self.work) if re.match(r"game\.\d+\.c$", n)), key=lambda n: int(n.split(".")[1]))
        if not units:
            raise Stop("the recompiler wrote no code")
        if not second:
            if phase == 0:
                self.end(f"{seeds:,} entry points seen running")
                p.stage("Find code")
                phase = 1
            if phase == 1:
                self.end(f"{blocks:,} blocks" if blocks else "charted")
                p.stage("Write C")
            self.end(f"{len(units)} units, {sum(os.path.getsize(os.path.join(self.work, u)) for u in units) / (1 << 20):.0f} MB of C")
        self.keep(emitted=units, blocks=blocks, seeds=seeds)
        self.report.update(blocks=blocks, ramEntryPoints=seeds, units=len(units))
        return units

    def compile(self, units, second=False):
        p = self.p
        tag = "Second pass: " if second else ""
        if not second:
            p.stage("Compile", f"0 of {len(units)}")
        cc = os.environ.get("GBA_RECOMP_CC") or shutil.which("cc", path=self.env["PATH"]) or "cc"
        jobs = max(1, min(len(units), (os.cpu_count() or 4) - 2))
        todo, done, reused = [], 0, 0
        for u in units:
            c, o = os.path.join(self.work, u), os.path.join(self.work, u[:-2] + ".o")
            sha = file_sha(c)
            if os.path.exists(o) and os.path.exists(o + ".sha") and open(o + ".sha").read() == sha:
                done += 1
                reused += 1
            else:
                todo.append((c, o, sha))
        t0 = time.time()

        def one(c, o, sha):
            r = subprocess.run([cc, "-O1", "-fPIC", "-c", "-o", o + ".tmp", c], env=self.env, capture_output=True, text=True)
            if r.returncode != 0:
                raise Stop(f"{os.path.basename(c)} did not compile: {r.stderr.strip().splitlines()[-1] if r.stderr.strip() else r.returncode}")
            os.replace(o + ".tmp", o)
            with open(o + ".sha", "w") as f:
                f.write(sha)

        p.progress(f"{tag}Compile {done} of {len(units)}", done, len(units), "units")
        with ThreadPoolExecutor(max_workers=jobs) as ex:
            futs = [ex.submit(one, *t) for t in todo]
            for f in as_completed(futs):
                f.result()
                done += 1
                n = done - reused
                eta = (time.time() - t0) / n * (len(todo) - n) if n else None
                p.progress(f"{tag}Compile {done} of {len(units)}", done, len(units), "units", eta)
        if not second:
            self.end(f"{len(units)} units" + (f", {reused} kept from before" if reused and todo else ""), reused=not todo)
        return [os.path.join(self.work, u[:-2] + ".o") for u in units]

    def link(self, objs, second=False):
        p = self.p
        lib = os.path.join(self.work, "game.dylib")
        if not second:
            p.stage("Link", "game.dylib")
        else:
            p.step("Second pass: Link")
        sig = hashlib.sha1(("".join(open(o + ".sha").read() for o in objs) + LINK_FLAGS_VERSION).encode()).hexdigest()
        if self.state.get("linked") == sig and os.path.exists(lib):
            if not second:
                self.end(f"{os.path.getsize(lib) / (1 << 20):.0f} MB", reused=True)
            return lib
        cc = os.environ.get("GBA_RECOMP_CC") or "cc"
        # the host looks up only rcg_blocks and rcg_block_count: the thousands of block functions stay inside the library,
        # so their names (about 0.8 MB) can go. The code itself is the same, so it runs at the same speed.
        flags = ["-Wl,-dead_strip", "-Wl,-exported_symbol,_rcg_blocks", "-Wl,-exported_symbol,_rcg_block_count"] if sys.platform == "darwin" else []
        r = subprocess.run([cc, "-shared", *flags, "-o", lib + ".tmp", *objs], env=self.env, capture_output=True, text=True)
        if r.returncode != 0:
            raise Stop("the link failed: " + (r.stderr.strip().splitlines()[-1] if r.stderr.strip() else str(r.returncode)))
        if sys.platform == "darwin":
            subprocess.run(["strip", "-x", lib + ".tmp"], capture_output=True)
        os.replace(lib + ".tmp", lib)
        self.keep(linked=sig, trial=None)
        if not second:
            self.end(f"{os.path.getsize(lib) / (1 << 20):.0f} MB")
        return lib

    def trial(self, rom_path, lib, sha256, second=False) -> dict:
        p = self.p
        if not second:
            p.stage("Trial run", "Playing the converted game without a window")
        else:
            p.step("Second pass: Trial run")
        sheet, shot = os.path.join(self.work, "trial.png"), os.path.join(self.work, "title.png")
        kept = self.state.get("trial")
        if isinstance(kept, dict) and os.path.exists(sheet):
            return kept
        frames = self.a.trial_frames
        sav = os.path.join(self.work, "trial.sav")
        if os.path.exists(sav):
            os.remove(sav)
        cmd = [self.tools["run"], rom_path, "--lib", lib, "--frames", str(frames), "--demo", "--sav", sav, "--sheet", sheet, "--every", str(max(frames // 12, 1)), "--cols", "4",
               "--state-check", "--json"]
        r = subprocess.run(cmd, env=self.env, capture_output=True, text=True)
        line = next((ln for ln in reversed(r.stdout.splitlines()) if ln.startswith("{")), None)
        if r.returncode != 0 or not line:
            raise Stop("the trial run stopped: " + ((r.stderr or r.stdout).strip().splitlines() or [f"exit {r.returncode}"])[-1])
        j = json.loads(line)
        # the title picture (the app's icon): a second, short run with no buttons pressed, to the frame most games have their
        # title up at (ten seconds in: past the makers' logos, before an attract mode starts)
        subprocess.run([self.tools["run"], rom_path, "--lib", lib, "--frames", "600", "--png", shot], env=self.env, capture_output=True)
        trial: dict = dict(frames=j["frames"], fps=j["fps"], blocks=j["blocks"], nativeBlocks=j["native_blocks"], fallbackSteps=j["fallback_steps"], nativeShare=j["native_share"],
                     missesRom=j["misses_rom"], missesRam=j["misses_ram"], labelsAdded=j.get("labels_added", 0), saveKind=SAVE_KINDS[min(j["save_kind"], 4)], saveBytes=j["save_bytes"],
                     rtc=bool(j["rtc"]), enhancedAudio=bool(j["hle_live"]), stateCheck="state check passed" in r.stdout + r.stderr, hash=j["hash"])
        self.keep(trial=trial)
        return trial

    def size(self, path):
        return sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(path) for f in fs)

    def package(self, out, name, tid, info, rom_path, lib, trial, player, meta):
        tmp = out + ".making"
        if os.path.exists(tmp):
            shutil.rmtree(tmp)
        res = os.path.join(tmp, "Contents", "Resources", "gba")
        os.makedirs(res)
        os.makedirs(os.path.join(tmp, "Contents", "MacOS"))
        exe = os.path.join(tmp, "Contents", "MacOS", "nxnative")   # the name the Converter's check looks for
        shutil.copy2(player, exe)
        os.chmod(exe, 0o755)
        if not pack_rom(rom_path, os.path.join(res, "game.gba.lzfse")):
            shutil.copy2(rom_path, os.path.join(res, "game.gba"))
        shutil.copy2(lib, os.path.join(res, "game.dylib"))
        for pic in ("trial.png", "title.png"):
            if os.path.exists(os.path.join(self.work, pic)):
                shutil.copy2(os.path.join(self.work, pic), os.path.join(res, pic))
                # nxgba-run writes its pictures uncompressed: sips writes the same pixels in about a tenth of the bytes
                if sys.platform == "darwin":
                    subprocess.run(["sips", "-s", "format", "png", os.path.join(res, pic)], capture_output=True)
        icon = self.icon(os.path.join(self.work, "title.png"), os.path.join(tmp, "Contents", "Resources"))
        port = dict(platform="gba", **info, engine=dict(name="gba-recomp", commit=self.tools["commit"]), built=int(time.time()),
                    stages=[dict(name=s, seconds=round(self.times.get(s, 0), 1)) for s in STAGES[:-1]], trial=trial, status=meta.get("status"), **self.report)
        with open(os.path.join(res, "port.json"), "w") as f:
            json.dump(port, f, indent=1)
        plist = dict(CFBundleName=name, CFBundleDisplayName=name, CFBundleIdentifier="com.nxforge.gba." + tid.lower(), CFBundleExecutable="nxnative", CFBundlePackageType="APPL",
                     CFBundleShortVersionString="1.0", CFBundleVersion=str(int(time.time())), LSMinimumSystemVersion="26.0", NSHighResolutionCapable=True,
                     LSApplicationCategoryType="public.app-category.games", NXForgeTitleID=tid, NXForgePlatform="gba", NXForgeGameCode=info["code"], NXForgeROMSHA1=info["sha1"],
                     GCSupportsControllerUserInteraction=True)
        if icon:
            plist["CFBundleIconFile"] = "AppIcon"
        with open(os.path.join(tmp, "Contents", "Info.plist"), "wb") as f:
            plistlib.dump(plist, f)
        if sys.platform == "darwin":
            for target in (os.path.join(res, "game.dylib"), tmp):
                r = subprocess.run(["codesign", "--force", "-s", "-", target], capture_output=True, text=True)
                if r.returncode != 0:
                    raise Stop("signing failed: " + r.stderr.strip())
        old = out + ".old"
        if os.path.exists(old):
            shutil.rmtree(old)
        if os.path.exists(out):
            os.rename(out, old)
        os.rename(tmp, out)
        if os.path.exists(old):
            shutil.rmtree(old)

    def icon(self, shot, res_dir):
        """The app's icon from the title picture (macOS's sips and iconutil); None when it cannot be made."""
        if sys.platform != "darwin" or not os.path.exists(shot):
            return None
        try:
            iconset = os.path.join(self.work, "AppIcon.iconset")
            shutil.rmtree(iconset, ignore_errors=True)
            os.makedirs(iconset)
            sq = os.path.join(self.work, "icon-square.png")
            subprocess.run(["sips", "-c", "160", "160", shot, "--out", sq], check=True, capture_output=True)
            for size in (16, 32, 128, 256, 512):
                for scale in (1, 2):
                    n = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
                    subprocess.run(["sips", "-z", str(size * scale), str(size * scale), sq, "--out", os.path.join(iconset, n)], check=True, capture_output=True)
            subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(res_dir, "AppIcon.icns")], check=True, capture_output=True)
            return True
        except (subprocess.CalledProcessError, OSError):
            return None


def main():
    ap = argparse.ArgumentParser(description="Convert a Game Boy Advance game into a Mac app")
    ap.add_argument("rom")
    ap.add_argument("-o", "--out")
    ap.add_argument("--work-dir")
    ap.add_argument("--home", help="the game's own folder: the app and the build folder go here unless -o / --work-dir say otherwise")
    ap.add_argument("--progress", choices=["text", "json"], default="text")
    ap.add_argument("--name")
    ap.add_argument("--fresh", action="store_true")
    ap.add_argument("--one-pass", action="store_true")
    ap.add_argument("--cleanup", action="store_true", help="remove the C and object files once the app is made")
    ap.add_argument("--trial-frames", type=int, default=3600)
    ap.add_argument("--info", action="store_true")
    a = ap.parse_args()
    b = Build(a)
    b.child = None

    def stop(sig, frame):
        if b.child:
            b.child.terminate()
        sys.exit(130)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    try:
        b.run()
    except Stop as e:
        b.p.emit(ev="stage_end", ok=False, elapsed=round(time.time() - b.p.t0, 1), summary=str(e))
        b.p.say(f"stopped: {e}")
        print(f"gba_build: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
