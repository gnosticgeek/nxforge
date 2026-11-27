#!/usr/bin/env python3
"""Make a Mac app for a Wii or GameCube game, played with Dolphin (wii/README.md).

  scripts/wii_build.py <disc image | .wad> [--home DIR] [-o <Name>.app] [--work-dir DIR] [--progress json] [--name NAME]
                       [--trial-seconds N] [--no-trial] [--no-cover] [--info]

Unlike a Switch or Game Boy Advance game, nothing is translated: the app is NXForge's Wii player (wii/host) with Dolphin
(nxdolphin.dylib, scripts/wii_engine.py) and its data, and it plays the disc image where it lies (its path is in the app's
port.json), so a 4 GB disc is never copied. Stages, in order:

  Read disc, Prepare engine, Package, Trial run

With --progress json every line on stdout is one JSON event, the ones the NXForge app reads from the other build scripts:
stage / step / progress / stage_end / say, the last "say" being "done: <path>.app". Prepare engine builds Dolphin the
first time (15 to 30 minutes) and is skipped after; the rest takes about half a minute.

--info prints what the app needs to list the game (title, game ID, title ID, platform) as one JSON line and stops.
"""
import argparse
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
import urllib.request
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "scripts"))
import wii_engine as engine  # noqa: E402

STAGES = ["Read disc", "Prepare engine", "Package", "Trial run"]
DISC_EXTENSIONS = {".iso", ".gcm", ".rvz", ".wia", ".wbfs", ".gcz", ".ciso", ".wad", ".dol", ".elf"}
WII_MAGIC, GC_MAGIC = 0x5D1C9EA3, 0xC2339F3D


class Stop(Exception):
    pass


class Progress:
    def __init__(self, as_json):
        self.json = as_json
        self.t0 = time.time()
        self.name = ""

    def emit(self, **ev):
        if self.json:
            print(json.dumps(ev), flush=True)

    def stage(self, name, step=""):
        self.t0 = time.time()
        self.name = name
        self.emit(ev="stage", k=STAGES.index(name) + 1, n=len(STAGES), name=name, step=step)
        if not self.json:
            print(f"[{STAGES.index(name) + 1}/{len(STAGES)}] {name}", flush=True)

    def step(self, text):
        self.emit(ev="step", step=text)
        if not self.json:
            print(f"      {text}", flush=True)

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


def clean_name(file_name):
    """"Zack & Wiki - Quest for Barbaros' Treasure (USA).rvz" -> "Zack & Wiki - Quest for Barbaros' Treasure" (GBA.cleanName's rule)."""
    n = os.path.splitext(os.path.basename(file_name))[0]
    n = re.sub(r"\s*[\(\[][^\)\]]*[\)\]]", "", n).strip()
    m = re.match(r"^(.*?), (The|A|An)( - .*)?$", n)
    if m:
        n = f"{m.group(2)} {m.group(1)}{m.group(3) or ''}"
    return n or "Game"


def disc_header(path):
    """The disc's own header (its first 0x80 bytes) from any of the image formats Dolphin reads, or None.
    ISO and GCM are the disc as it is; WBFS keeps it at 0x200, CISO at 0x8000, RVZ and WIA a copy in their own header,
    GCZ in its first compressed block."""
    with open(path, "rb") as f:
        head = f.read(0x8100)
        if len(head) < 0x80:
            return None
        magic = head[:4]
        if magic in (b"RVZ\x01", b"WIA\x01"):
            return head[0x58:0x58 + 0x80]
        if magic == b"WBFS":
            return head[0x200:0x280]
        if magic == b"CISO":
            return head[0x8000:0x8080]
        if struct.unpack("<I", magic)[0] == 0xB10BC001:
            sub, csize, dsize, block_size, blocks = struct.unpack("<IQQII", head[4:32])
            if blocks == 0:
                return None
            ptr0 = struct.unpack("<Q", head[32:40])[0]
            data_start = 32 + blocks * 12
            f.seek(data_start + (ptr0 & ~(1 << 63)))
            raw = f.read(block_size + 64)
            if ptr0 & (1 << 63):
                return raw[:0x80]
            try:
                return zlib.decompressobj().decompress(raw, 0x80)
            except zlib.error:
                return None
        return head[:0x80]


def read_disc(path):
    """What the game is: platform (wii, gamecube), its six-character game ID, its version and title. A disc image is read
    from its header; a WAD from its title ID; a DOL or ELF (homebrew) from its file name."""
    ext = os.path.splitext(path)[1].lower()
    name = clean_name(path)
    if ext in (".dol", ".elf"):
        gid = re.sub(r"[^A-Z0-9]", "", name.upper())[:6].ljust(6, "0")
        return dict(platform="wii", id=gid, version=0, title=name, form="homebrew")
    if ext == ".wad":
        with open(path, "rb") as f:
            h = f.read(0x20)
            hsize, _, cert, _, tik, tmd = struct.unpack(">IIIIII", h[:24])
            align = lambda n: (n + 63) & ~63  # noqa: E731
            f.seek(align(hsize) + align(cert) + align(tik) + 0x18C)
            tid = f.read(8)
        if len(tid) < 8:
            raise Stop("not a WAD Dolphin can read: its header is cut short")
        code = "".join(chr(c) if 32 < c < 127 else "0" for c in tid[4:])
        return dict(platform="wii", id=code + "00", version=0, title=name, form="WiiWare")
    h = disc_header(path)
    if not h or len(h) < 0x60:
        raise Stop("not a Wii or GameCube disc image NXForge can read")
    wii, gc = struct.unpack(">I", h[0x18:0x1C])[0] == WII_MAGIC, struct.unpack(">I", h[0x1C:0x20])[0] == GC_MAGIC
    if not (wii or gc):
        raise Stop("not a Wii or GameCube disc: its header has neither console's mark")
    gid = "".join(chr(c) if 32 < c < 127 else "0" for c in h[:6])
    title = h[0x20:0x60].split(b"\0")[0].decode("latin-1", "replace").strip()
    return dict(platform="wii" if wii else "gamecube", id=gid, version=h[7], title=title or name, form="disc")


def title_id(info):
    """The 16 hex digits NXForge keeps the game under: 0E00 (Wii) or 0C00 (GameCube) and the game ID's six characters in hex."""
    return ("0E00" if info["platform"] == "wii" else "0C00") + info["id"].encode("latin-1", "replace")[:6].hex().upper().ljust(12, "0")


GAMETDB_REGIONS = {"E": "US", "N": "US", "P": "EN", "D": "DE", "F": "FR", "I": "IT", "S": "ES", "J": "JA", "K": "KO", "W": "ZH"}


def fetch_cover(gid, platform, dst):
    """The game's box front from GameTDB (art.gametdb.com, the covers Dolphin and most front ends show), or False."""
    region = GAMETDB_REGIONS.get(gid[3:4], "EN")
    for r in dict.fromkeys([region, "US", "EN"]):
        url = f"https://art.gametdb.com/wii/cover/{r}/{gid}.png"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "NXForge"})
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = resp.read()
            if data[:8] == b"\x89PNG\r\n\x1a\n":
                with open(dst, "wb") as f:
                    f.write(data)
                return True
        except Exception:  # noqa: BLE001
            continue
    return False


def make_icon(src, res_dir, work, square=False):
    """AppIcon.icns from a picture (macOS's sips and iconutil): the cover as it is, padded square, or the trial picture's middle."""
    if sys.platform != "darwin" or not os.path.exists(src):
        return False
    try:
        iconset = os.path.join(work, "AppIcon.iconset")
        shutil.rmtree(iconset, ignore_errors=True)
        os.makedirs(iconset)
        sq = os.path.join(work, "icon-square.png")
        out = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", src], capture_output=True, text=True).stdout
        mw = re.search(r"pixelWidth: (\d+)", out)
        mh = re.search(r"pixelHeight: (\d+)", out)
        if not mw or not mh:
            return False
        w, hgt = int(mw.group(1)), int(mh.group(1))
        side = max(w, hgt) if square else min(w, hgt)
        args = ["--padToHeightWidth", str(side), str(side)] if square else ["-c", str(side), str(side)]
        subprocess.run(["sips", *args, src, "--out", sq], check=True, capture_output=True)
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                n = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
                subprocess.run(["sips", "-z", str(size * scale), str(size * scale), sq, "--out", os.path.join(iconset, n)], check=True, capture_output=True)
        subprocess.run(["iconutil", "-c", "icns", iconset, "-o", os.path.join(res_dir, "AppIcon.icns")], check=True, capture_output=True)
        return True
    except (subprocess.CalledProcessError, OSError, AttributeError, ValueError):
        return False


def sign(path):
    r = subprocess.run(["codesign", "--force", "-s", "-", path], capture_output=True, text=True)
    if r.returncode != 0:
        raise Stop("signing failed: " + r.stderr.strip())


def tree_size(path):
    return sum(os.path.getsize(os.path.join(d, f)) for d, _, fs in os.walk(path) for f in fs)


class Build:
    def __init__(self, a):
        self.a = a
        self.p = Progress(a.progress == "json")
        self.child = None
        self.times = {}

    def end(self, summary):
        self.times[self.p.name] = self.p.end(summary)

    def run(self):
        a, p = self.a, self.p
        disc = os.path.abspath(a.disc)
        if not a.info:
            p.stage("Read disc", os.path.basename(disc))
        if not os.path.isfile(disc):
            raise Stop(f"no file at {disc}")
        info = read_disc(disc)
        tid = title_id(info)
        name = a.name or clean_name(disc)
        size = os.path.getsize(disc)
        info.update(titleID=tid, name=name, bytes=size, disc=disc)
        if a.info:
            print(json.dumps(info), flush=True)
            return None
        console = "Wii" if info["platform"] == "wii" else "GameCube"
        self.end(f"{console} {info['form']}: {info['title']} ({info['id']}), {size / (1 << 30):.2f} GB, played from where it is")

        home = os.path.abspath(a.home) if a.home else None
        safe = name.replace(":", " - ").replace("/", " - ")
        out = os.path.abspath(a.out or os.path.join(home or os.path.dirname(disc), safe + ".app"))
        work = os.path.abspath(a.work_dir or os.path.join(home or os.path.dirname(out), tid + "_build"))
        os.makedirs(work, exist_ok=True)

        p.stage("Prepare engine", "Dolphin " + engine.engine()["commit"][:8])
        if engine.stale():
            p.step("Building Dolphin and the Wii player (the first time takes 15 to 30 minutes)")
            log = os.path.join(work, "engine-build.log")
            with open(log, "w") as lf:
                self.child = subprocess.Popen([sys.executable, os.path.join(ROOT, "scripts", "wii_engine.py"), "build"], stdout=lf, stderr=subprocess.STDOUT)
                rc = self.child.wait()
                self.child = None
            if rc != 0:
                with open(log, errors="replace") as lf:
                    tail = lf.read().strip().splitlines()[-6:]
                for line in tail:
                    p.say(line)
                raise Stop("Dolphin did not build: " + (tail[-1] if tail else f"exit {rc}") + f" (log: {log})")
            self.end("built Dolphin and the player")
        else:
            self.end("Dolphin and the player are built")
        w = engine.where()

        p.stage("Package", os.path.basename(out))
        tmp = out + ".making"
        shutil.rmtree(tmp, ignore_errors=True)
        contents = os.path.join(tmp, "Contents")
        res, fw, macos = os.path.join(contents, "Resources"), os.path.join(contents, "Frameworks"), os.path.join(contents, "MacOS")
        for d in (os.path.join(res, "wii"), fw, macos):
            os.makedirs(d)
        exe = os.path.join(macos, "nxnative")   # the name NXForge's checks look for
        shutil.copy2(w["player"], exe)
        os.chmod(exe, 0o755)
        shutil.copy2(w["lib"], os.path.join(fw, "nxdolphin.dylib"))
        shutil.copytree(w["sys"], os.path.join(res, "Sys"))
        lic = os.path.join(res, "Dolphin licences")
        os.makedirs(lic)
        for src in w["licences"]:
            (shutil.copytree if os.path.isdir(src) else shutil.copy2)(src, os.path.join(lic, os.path.basename(src)))
        cover = os.path.join(work, "cover.png")
        if not a.no_cover and info["form"] != "homebrew" and not os.path.exists(cover):
            p.step("Fetching the box art from GameTDB")
            fetch_cover(info["id"], info["platform"], cover)
        if os.path.exists(cover):
            shutil.copy2(cover, os.path.join(res, "wii", "cover.png"))
        plist = dict(CFBundleName=name, CFBundleDisplayName=name, CFBundleIdentifier="com.nxforge.wii." + tid.lower(), CFBundleExecutable="nxnative",
                     CFBundlePackageType="APPL", CFBundleShortVersionString="1.0", CFBundleVersion=str(int(time.time())), LSMinimumSystemVersion="26.0",
                     NSHighResolutionCapable=True, LSApplicationCategoryType="public.app-category.games", NXForgeTitleID=tid, NXForgePlatform=info["platform"],
                     NXForgeGameCode=info["id"], GCSupportsControllerUserInteraction=True)
        self.write_port(res, info, w, trial=None)
        with open(os.path.join(contents, "Info.plist"), "wb") as f:
            plistlib.dump(plist, f)
        if sys.platform == "darwin":
            sign(os.path.join(fw, "nxdolphin.dylib"))
            sign(tmp)
        self.end(f"{tree_size(tmp) / (1 << 20):.0f} MB app; the disc stays at {disc}")

        trial = None
        if not a.no_trial and sys.platform == "darwin":
            p.stage("Trial run", f"{a.trial_seconds} s with no window")
            trial = self.trial(tmp, work, tid)
            shot = os.path.join(work, "title.png")
            if os.path.exists(shot):
                shutil.copy2(shot, os.path.join(res, "wii", "title.png"))
                subprocess.run(["sips", "-Z", "960", os.path.join(res, "wii", "title.png")], capture_output=True)
            self.end(("started and drew " + f"{trial['frames']:,} frames" + (f" at {trial['fps']:.0f} fps" if trial.get("fps") else "")) if trial.get("playing")
                     else "did not reach its first frame in the trial: " + str(trial.get("error") or "see the log"))
        icon = make_icon(cover, res, work, square=True) if os.path.exists(cover) else make_icon(os.path.join(work, "title.png"), res, work)
        if icon:
            plist["CFBundleIconFile"] = "AppIcon"
            with open(os.path.join(contents, "Info.plist"), "wb") as f:
                plistlib.dump(plist, f)
        self.write_port(res, info, w, trial)
        if sys.platform == "darwin":
            sign(tmp)
        old = out + ".old"
        shutil.rmtree(old, ignore_errors=True)
        if os.path.exists(out):
            os.rename(out, old)
        os.rename(tmp, out)
        shutil.rmtree(old, ignore_errors=True)
        p.say(f"done: {out}")
        return out

    def write_port(self, res, info, w, trial):
        port = dict(info, engine=dict(name="Dolphin", commit=w["commit"]), built=int(time.time()),
                    stages=[dict(name=s, seconds=round(self.times.get(s, 0), 1)) for s in STAGES], trial=trial)
        with open(os.path.join(res, "wii", "port.json"), "w") as f:
            json.dump(port, f, indent=1)

    def trial(self, app, work, tid):
        """The game started with no window for a while, its saves in the build folder, never the player's own: did it reach a frame, and its picture."""
        root = os.path.join(work, "trial-root")
        shutil.rmtree(root, ignore_errors=True)
        shot = os.path.join(work, "title.png")
        if os.path.exists(shot):
            os.remove(shot)
        env = dict(os.environ, NXWII_SNAPSHOT=shot, NXWII_SNAPSHOT_SECONDS=str(self.a.trial_seconds), NXWII_SNAPSHOT_INPUT="menus", DM_ROOT=root)
        log = os.path.join(work, "trial.log")
        with open(log, "w") as lf:
            self.child = subprocess.Popen([os.path.join(app, "Contents", "MacOS", "nxnative")], env=env, stdout=subprocess.PIPE, stderr=lf, text=True)
            try:
                outp, _ = self.child.communicate(timeout=self.a.trial_seconds + 90)
            except subprocess.TimeoutExpired:
                self.child.kill()
                outp = ""
            self.child = None
        shutil.rmtree(root, ignore_errors=True)
        res = {}
        for line in (outp or "").splitlines():
            if line.startswith("{"):
                try:
                    res = json.loads(line)
                except ValueError:
                    pass
        if not res:
            with open(log, errors="replace") as lf:
                tail = [ln for ln in lf.read().splitlines() if ln.strip()][-1:]
            res = dict(playing=False, frames=0, error=tail[0] if tail else "the player stopped without a word")
        return dict(playing=bool(res.get("playing")), frames=int(res.get("frames", 0)), fps=float(res.get("fps", 0)), seconds=self.a.trial_seconds,
                    picture=os.path.exists(shot), **({"error": res["error"]} if "error" in res else {}))


def main():
    ap = argparse.ArgumentParser(description="Make a Mac app for a Wii or GameCube game")
    ap.add_argument("disc")
    ap.add_argument("-o", "--out")
    ap.add_argument("--work-dir")
    ap.add_argument("--home", help="the game's own folder: the app and the build folder go here unless -o / --work-dir say otherwise")
    ap.add_argument("--progress", choices=["text", "json"], default="text")
    ap.add_argument("--name")
    ap.add_argument("--trial-seconds", type=int, default=25)
    ap.add_argument("--no-trial", action="store_true")
    ap.add_argument("--no-cover", action="store_true")
    ap.add_argument("--info", action="store_true")
    a = ap.parse_args()
    b = Build(a)

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
        print(f"wii_build: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
