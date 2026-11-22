#!/usr/bin/env python3
"""Assemble and build the Game Boy Advance engine (gba/README.md).

  scripts/gba_engine.py assemble   clone gba-recomp at the commit in gba/ENGINE into gba/tree and apply gba/patches
  scripts/gba_engine.py build      assemble if needed, then build the recompiler (recomp), the host (nxgba) and, on a Mac, the player
  scripts/gba_engine.py where      print the paths the build script uses, as JSON

The engine's code is never committed here: gba/tree is assembled and git-ignored, like tree/ for nxnative.
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GBA = os.path.join(ROOT, "gba")
TREE = os.path.join(GBA, "tree")
HOST = os.path.join(GBA, "host")


def engine():
    out = {}
    with open(os.path.join(GBA, "ENGINE")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                k, v = line.split(None, 1)
                out[k] = v
    return out


def patches():
    d = os.path.join(GBA, "patches")
    return [os.path.join(d, n) for n in sorted(os.listdir(d)) if n.endswith(".patch")]


def stamp():
    """What gba/tree was assembled from: the pin plus every patch's name and size."""
    e = engine()
    return e["commit"] + "".join(f"\n{os.path.basename(p)} {os.path.getsize(p)}" for p in patches())


def git(*a, cwd=TREE):
    subprocess.run(["git", *a], cwd=cwd, check=True)


def assemble(force=False):
    mark = os.path.join(TREE, ".nxforge-assembled")
    if not force and os.path.exists(mark) and open(mark).read() == stamp():
        return False
    e = engine()
    if not os.path.isdir(os.path.join(TREE, ".git")):
        os.makedirs(TREE, exist_ok=True)
        git("init", "-q")
        git("remote", "add", "origin", e["url"])
    have = subprocess.run(["git", "cat-file", "-e", e["commit"] + "^{commit}"], cwd=TREE, capture_output=True)
    if have.returncode != 0:
        git("fetch", "-q", "--depth", "1", "origin", e["commit"])
    git("checkout", "-q", "-f", e["commit"])
    git("clean", "-q", "-fd", "-e", "target", "-e", ".nxforge-assembled")
    for p in patches():
        git("apply", "--whitespace=nowarn", p)
    with open(mark, "w") as f:
        f.write(stamp())
    return True


def env():
    e = dict(os.environ)
    extra = [os.path.expanduser("~/.cargo/bin"), "/opt/homebrew/bin"]
    e["PATH"] = os.pathsep.join(extra + [e.get("PATH", "")])
    return e


def where():
    return {
        "recomp": os.path.join(TREE, "target", "release", "recomp"),
        "run": os.path.join(HOST, "target", "release", "nxgba-run"),
        "lib": os.path.join(HOST, "target", "release", "libnxgba.a"),
        "player": os.path.join(GBA, "build", "nxgba-player"),
        "runtime_dir": os.path.join(TREE, "runtime"),
        "tree": TREE,
        "commit": engine()["commit"],
    }


def stale():
    """True when the tools are missing or older than what they are built from (the pin, the patches, the host's and the
    player's sources): scripts/gba_build.py builds them before its first conversion and after an engine update."""
    w = where()
    outs = [w["recomp"], w["run"]] + ([w["player"]] if sys.platform == "darwin" else [])
    if not all(os.path.exists(o) for o in outs):
        return True
    mark = os.path.join(TREE, ".nxforge-assembled")
    if not os.path.exists(mark) or open(mark).read() != stamp():
        return True
    built = min(os.path.getmtime(o) for o in outs)
    srcs = [os.path.join(d, f) for top in (os.path.join(HOST, "src"), os.path.join(HOST, "mac")) for d, _, fs in os.walk(top) for f in fs]
    srcs += [os.path.join(HOST, "Cargo.toml"), os.path.join(HOST, "nxgba.h")]
    if sys.platform == "darwin":
        qs = os.path.join(ROOT, "layer", "files", "dm", "host")
        srcs += [os.path.join(qs, "quick_settings_mac.swift"), os.path.join(qs, "quick_settings_mac.h")]
    return any(os.path.getmtime(s) > built for s in srcs if os.path.exists(s))


def build():
    assemble()
    subprocess.run(["cargo", "build", "--release", "-p", "recomp"], cwd=TREE, env=env(), check=True)
    subprocess.run(["cargo", "build", "--release"], cwd=HOST, env=env(), check=True)
    if sys.platform == "darwin":
        subprocess.run([os.path.join(HOST, "mac", "build.sh")], env=env(), check=True)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "assemble":
        print("assembled" if assemble("--force" in sys.argv) else "up to date")
    elif cmd == "build":
        build()
    elif cmd == "stale":
        print("stale" if stale() else "current")
    elif cmd == "where":
        print(json.dumps(where()))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
