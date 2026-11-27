#!/usr/bin/env python3
"""Fetch and build the Wii and GameCube engine: Dolphin as one library, and NXForge's Wii player (wii/README.md).

  scripts/wii_engine.py build      fetch Dolphin at the commit in wii/ENGINE if needed, build nxdolphin.dylib with
                                   NXForge's bridge (wii/bridge) and, on a Mac, the player (wii/host/mac)
  scripts/wii_engine.py stale      "stale" when build would do something, else "current"
  scripts/wii_engine.py where      print the paths the build script uses, as JSON

Dolphin's source and its build are large (about 1 GB and 2 GB) and are the same for every checkout of NXForge, so they
live outside the repository, in NXF_DOLPHIN_HOME (default ~/Library/Application Support/NXForge Converter/dolphin):
src/ (Dolphin at the pin, with its submodules), build/ (CMake and Ninja's), out/ (what a game app takes: nxdolphin.dylib,
Sys/, Dolphin's licences). The first build takes 15 to 30 minutes; later ones rebuild only the bridge.
"""
import hashlib
import json
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WII = os.path.join(ROOT, "wii")
BRIDGE = os.path.join(WII, "bridge")
MAC = os.path.join(WII, "host", "mac")
HOME = os.environ.get("NXF_DOLPHIN_HOME") or os.path.expanduser("~/Library/Application Support/NXForge Converter/dolphin")
SRC, BUILD, OUT, TOOLS = (os.path.join(HOME, n) for n in ("src", "build", "out", "tools"))
ABI = 1
# Dolphin's submodules a Mac build without Qt needs: the rest are Windows bundles or features the bridge turns off.
EXCLUDED = {"Externals/FFmpeg-bin", "Externals/Qt", "Externals/SDL/SDL", "Externals/mGBA/mgba", "Externals/libadrenotools",
            "Externals/wil", "Externals/rcheevos"}
DISABLED = ["ENABLE_QT", "ENABLE_NOGUI", "ENABLE_CLI_TOOL", "ENABLE_TESTS", "ENABLE_AUTOUPDATE", "ENABLE_ANALYTICS",
            "USE_DISCORD_PRESENCE", "USE_RETRO_ACHIEVEMENTS", "USE_MGBA", "USE_UPNP", "ENABLE_VULKAN", "ENABLE_LLVM",
            "ENCODE_FRAMEDUMPS", "ENABLE_SDL"]
HOOK = "\n# NXForge's bridge (added by scripts/wii_engine.py).\nadd_subdirectory(\"${NXF_BRIDGE_DIR}\" nxf-bridge)\n"


def engine():
    out = {}
    with open(os.path.join(WII, "ENGINE")) as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                k, v = line.split(None, 1)
                out[k] = v
    return out


def files_hash(paths):
    h = hashlib.sha1()
    for p in sorted(paths):
        h.update(os.path.basename(p).encode())
        with open(p, "rb") as f:
            h.update(f.read())
    return h.hexdigest()[:12]


def bridge_stamp():
    return engine()["commit"] + " " + files_hash([os.path.join(BRIDGE, n) for n in os.listdir(BRIDGE) if not n.startswith(".")])


def player_sources():
    qs = os.path.join(ROOT, "layer", "files", "dm", "host")
    return [os.path.join(MAC, n) for n in os.listdir(MAC) if not n.startswith(".")] + \
        [os.path.join(qs, "quick_settings_mac.swift"), os.path.join(qs, "quick_settings_mac.h")]


def where():
    return {
        "lib": os.path.join(OUT, "nxdolphin.dylib"),
        "sys": os.path.join(OUT, "Sys"),
        "licences": [os.path.join(OUT, "Dolphin-COPYING.txt"), os.path.join(OUT, "LICENSES")],
        "player": os.path.join(WII, "build", "nxwii-player"),
        "home": HOME,
        "commit": engine()["commit"],
        "abi": ABI,
    }


def built_stamp():
    try:
        with open(os.path.join(OUT, "build.json")) as f:
            return json.load(f).get("stamp")
    except (OSError, ValueError):
        return None


def stale():
    """True when the library or the player is missing or older than what it is built from."""
    w = where()
    if not os.path.exists(w["lib"]) or built_stamp() != bridge_stamp():
        return True
    if sys.platform == "darwin":
        if not os.path.exists(w["player"]):
            return True
        built = os.path.getmtime(w["player"])
        return any(os.path.getmtime(s) > built for s in player_sources() if os.path.exists(s))
    return False


def run(*a, **kw):
    subprocess.run([str(x) for x in a], check=True, **kw)


def fetch():
    e = engine()
    if not os.path.isdir(os.path.join(SRC, ".git")):
        os.makedirs(SRC, exist_ok=True)
        run("git", "init", "-q", SRC)
        run("git", "-C", SRC, "remote", "add", "origin", e["url"])
    have = subprocess.run(["git", "-C", SRC, "rev-parse", "HEAD"], capture_output=True, text=True).stdout.strip()
    if have != e["commit"]:
        if subprocess.run(["git", "-C", SRC, "cat-file", "-e", e["commit"] + "^{commit}"], capture_output=True).returncode != 0:
            run("git", "-C", SRC, "fetch", "-q", "--depth", "1", "origin", e["commit"])
        run("git", "-C", SRC, "checkout", "-q", "--force", "--detach", e["commit"])
    paths = subprocess.check_output(["git", "-C", SRC, "config", "--file", ".gitmodules", "--get-regexp", "path"], text=True)
    mods = [ln.split(None, 1)[1] for ln in paths.splitlines() if ln.split(None, 1)[1] not in EXCLUDED]
    run("git", "-C", SRC, "submodule", "update", "--init", "--recursive", "--depth", "1", "--", *mods)
    # Dolphin's CMakeLists.txt as it is upstream, plus one line that adds the bridge
    upstream = subprocess.check_output(["git", "-C", SRC, "show", "HEAD:CMakeLists.txt"], text=True)
    with open(os.path.join(SRC, "CMakeLists.txt"), "w") as f:
        f.write(upstream + HOOK)


def tool(name):
    """cmake and ninja: Homebrew's when installed, else a private Python environment's."""
    found = shutil.which(name, path=os.pathsep.join(["/opt/homebrew/bin", "/usr/local/bin", os.environ.get("PATH", "")]))
    if found:
        return found
    pip = os.path.join(TOOLS, "bin", "pip")
    if not os.path.exists(pip):
        run(sys.executable, "-m", "venv", TOOLS)
    if not os.path.exists(os.path.join(TOOLS, "bin", name)):
        run(pip, "install", "-q", "cmake==4.4.4", "ninja==1.13.2")
    return os.path.join(TOOLS, "bin", name)


def build_lib():
    fetch()
    cmake, ninja = tool("cmake"), tool("ninja")
    run(cmake, "-S", SRC, "-B", BUILD, "-G", "Ninja", f"-DCMAKE_MAKE_PROGRAM={ninja}", f"-DDOLPHIN_SOURCE={SRC}",
        f"-DNXF_BRIDGE_DIR={BRIDGE}", "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_OSX_ARCHITECTURES=arm64",
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON", "-DUSE_SYSTEM_LIBS=OFF",
        # newer Xcode headers declare pipe2 even with a macOS 26 deployment target
        "-DHAVE_PIPE2=0", *[f"-D{o}=OFF" for o in DISABLED], stdout=subprocess.DEVNULL)
    jobs = os.environ.get("NXF_DOLPHIN_JOBS") or str(max(2, (os.cpu_count() or 4) - 2))
    run(cmake, "--build", BUILD, "--target", "nxdolphin", "-j", jobs)
    os.makedirs(OUT, exist_ok=True)
    shutil.copy2(os.path.join(BUILD, "nxf-bridge", "nxdolphin.dylib"), os.path.join(OUT, "nxdolphin.dylib"))
    shutil.copytree(os.path.join(SRC, "Data", "Sys"), os.path.join(OUT, "Sys"), dirs_exist_ok=True)
    shutil.copy2(os.path.join(SRC, "COPYING"), os.path.join(OUT, "Dolphin-COPYING.txt"))
    shutil.copytree(os.path.join(SRC, "LICENSES"), os.path.join(OUT, "LICENSES"), dirs_exist_ok=True)
    run("strip", "-x", os.path.join(OUT, "nxdolphin.dylib"))
    with open(os.path.join(OUT, "build.json"), "w") as f:
        json.dump({"revision": engine()["commit"], "abi": ABI, "stamp": bridge_stamp()}, f, indent=1)


def build():
    if not os.path.exists(where()["lib"]) or built_stamp() != bridge_stamp():
        build_lib()
    if sys.platform == "darwin":
        run(os.path.join(MAC, "build.sh"))


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "build":
        build()
    elif cmd == "lib":
        build_lib()
    elif cmd == "stale":
        print("stale" if stale() else "current")
    elif cmd == "where":
        print(json.dumps(where()))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
