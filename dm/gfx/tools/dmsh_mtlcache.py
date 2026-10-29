#!/usr/bin/env python3
# Compiled-shader cache keyed by the Metal source (dmsh_build.py): a library is compiled once per (MSL text, compile convention, compiler), so a chain change
# that leaves a shader's MSL as it was (a translator fix, a new rule for other shaders) costs that shader no Metal compile. The Metal compiler is deterministic:
# the same MSL with the same flags gives a byte-identical metallib (checked for macOS and iOS), which is what makes reuse safe.
# Layout: <cache>/<target>/<2 hex>/<digest>.metallib, digest = sha256 over FORMAT, the target's compile convention (the record written into json chain_metal),
# the compiler's identity (metal / metallib --version without the install path, the SDK version and build) and the MSL bytes.
# Filling from earlier builds: every imported library must record the current compiler identity and flags in its reflection. Legacy libraries without that identity are not imported.
# A fresh compile of two shaders per stage also checks their bytes. Each folder is read once per compiler identity (filled.json remembers its number of libraries).
# Not part of the chain version (dmsh_chain.py): the cache never changes an output, it only skips recompiling one. Change FORMAT when what it stores changes.
# One cache for every game and build (SHARED, DMSH_MTLCACHE): nothing in a key names a game, and a cache inside <id>_build went with it when a Mac app's build cleaned up
# (CLEANUP 'all'), so the next build of the game after a chain change compiled every shader again (Cruis'n Blast: 46 minutes). A use refreshes a library's mtime and prune() keeps the
# cache under DMSH_MTLCACHE_GB by deleting the libraries unused the longest; a library deleted while another build reads it is compiled again there
import os, re, json, shutil, ctypes, hashlib, threading, subprocess, collections

SHARED = os.environ.get('DMSH_MTLCACHE') or os.path.expanduser('~/Library/Caches/NXForge/metallib')
LIMIT_GB = float(os.environ.get('DMSH_MTLCACHE_GB') or 4)   # Kirby's Return to Dream Land Deluxe: 32,278 libraries in 0.9 GB

FORMAT = b'dmsh_mtlcache 2'   # earlier prefill could misclassify an unsampled library from another compiler
_clonefile = getattr(ctypes.CDLL(None, use_errno=True), 'clonefile', None)   # APFS copy-on-write copy (no data written); elsewhere a plain copy


def clone(src, dst):
    tmp = f'{dst}.tmp-{os.getpid()}-{threading.get_ident()}'
    if _clonefile is None or _clonefile(os.fsencode(src), os.fsencode(tmp), 0) != 0: shutil.copyfile(src, tmp)
    os.replace(tmp, dst)


def run(cmd, **kw):
    """subprocess.run, started with posix_spawn rather than fork + exec. A fork copies the page tables of the whole build process (several hundred MB) and holds the GIL while it does:
    about 6 ms, three or four times a shader, which kept dmsh_build.py at 100% of one core and half its Metal compiles waiting (Kirby, 47,099 shaders). Python spawns only for an executable
    given with its folder and close_fds=False (macOS has no POSIX_SPAWN_CLOSEFROM); every descriptor Python opens is close-on-exec, so the child still gets only its standard streams"""
    exe = cmd[0] if os.path.dirname(cmd[0]) else shutil.which(cmd[0]) or cmd[0]
    return subprocess.run(cmd, executable=exe, close_fds=False, **kw)


def compiler_id(sdk):
    def ask(*a): return run(['xcrun', '-sdk', sdk, *a], capture_output=True, text=True).stdout
    tools = ''.join(ask(t, '--version') for t in ('metal', 'metallib'))
    return re.sub(r'(?m)^InstalledDir:.*\n?', '', tools) + ask('--show-sdk-version') + ask('--show-sdk-build-version')   # the install path changes with each toolchain mount


class Cache:
    def __init__(self, root, targets, work):
        """targets: {name: (sdk, record, compile)}, compile(msl, air, lib) as ios_metal.compile; work: a folder for temporary .air files"""
        self.root, self.targets, self.work = root, targets, work
        self.ident = {t: hashlib.sha256(FORMAT + b'\0' + rec.encode() + b'\0' + compiler_id(sdk).encode()).digest() for t, (sdk, rec, _) in targets.items()}
        self.stats, self.lock, self.busy = collections.Counter(), threading.Lock(), {}

    def path(self, target, src):
        d = hashlib.sha256(self.ident[target] + b'\0' + src).hexdigest()
        return os.path.join(self.root, target, d[:2], d + '.metallib')

    def with_compiler(self, target, refl):
        return dict(refl, chain_metal=self.targets[target][1], chain_compiler=self.ident[target].hex())

    def count(self, what, n=1):
        with self.lock: self.stats[what] += n

    def _compile(self, target, msl, lib):
        air = os.path.join(self.work, f'mtlcache-{target}-{os.getpid()}-{threading.get_ident()}.air')
        try: self.targets[target][2](msl, air, lib)
        finally:
            if os.path.exists(air): os.unlink(air)

    def compile(self, target, msl, lib):
        """msl → lib for target: a clone of the library that the same source compiled to before, or a compile (then kept). Raises CalledProcessError as the compile does.
        A source another thread is compiling waits for that compile (about half of a game's libraries share their MSL with another)"""
        p = self.path(target, open(msl, 'rb').read())
        with self.lock: mine = self.busy.setdefault(p, threading.Lock())
        with mine:
            try:
                clone(p, lib); os.utime(p); self.count((target, 'reused')); return
            except OSError: pass   # not in the cache (or pruned by another build just now)
            tmp = f'{lib}.tmp-{os.getpid()}-{threading.get_ident()}'
            self._compile(target, msl, tmp)
            os.replace(tmp, lib)
            os.makedirs(os.path.dirname(p), exist_ok=True); clone(lib, p); self.count((target, 'compiled'))

    def adopt(self, old):
        """Moves the libraries of an older cache folder (a game's <cas>/metallib from before SHARED) into this one and deletes it; returns the number moved. One on another volume stays"""
        moved = 0
        for target in ('mac', 'ios'):   # also a target this build does not compile
            for d, _, names in os.walk(os.path.join(old, target)):
                for n in names:
                    dst = os.path.join(self.root, target, os.path.basename(d), n)
                    try:
                        os.makedirs(os.path.dirname(dst), exist_ok=True)
                        if os.path.exists(dst): os.unlink(os.path.join(d, n))
                        else: os.rename(os.path.join(d, n), dst); moved += 1
                    except OSError: return moved
        shutil.rmtree(old, ignore_errors=True)
        return moved

    def prune(self, limit_gb=LIMIT_GB):
        """Deletes the libraries unused the longest until the cache is under limit_gb (allocated size: a library cloned into a build's output shares its blocks, so this overstates
        what deleting frees). Returns the line to print"""
        files, total = [], 0
        for t in ('mac', 'ios'):
            for d, _, names in os.walk(os.path.join(self.root, t)):
                for n in names:
                    try: st = os.stat(os.path.join(d, n))
                    except OSError: continue
                    files.append((st.st_mtime, st.st_blocks * 512, os.path.join(d, n))); total += st.st_blocks * 512
        limit, gone = limit_gb * 2**30, 0
        for _, size, path in sorted(files):
            if total <= limit: break
            try: os.unlink(path); total -= size; gone += 1
            except OSError: pass
        return f'Metal cache: {len(files) - gone:,} libraries, {total / 2**30:.1f} GB in {self.root}' + (f' ({gone:,} unused the longest deleted, limit {limit_gb:g} GB, DMSH_MTLCACHE_GB)' if gone else '')

    def _check(self, target, d, stems, mac_dir):
        """None if folder d was built with the current convention and compiler, else why not"""
        rec, picks = self.targets[target][1], collections.defaultdict(list)
        for stem in stems:
            try: j = json.load(open(os.path.join(d, stem + '.json')))
            except (OSError, ValueError): return f'no readable {stem}.json'
            if j.get('chain_metal') != rec: return f'built with "{j.get("chain_metal")}"'
            if j.get('chain_compiler') != self.ident[target].hex(): return f'{stem} has a different or unrecorded Metal compiler'
            if len(picks[j.get('stage')]) < 2: picks[j.get('stage')].append(stem)
        for stem in (s for v in picks.values() for s in v):
            tmp = os.path.join(self.work, f'mtlcache-check-{target}.metallib')
            try: self._compile(target, os.path.join(mac_dir, stem + '.metal'), tmp)
            except subprocess.CalledProcessError: return f'{stem}.metal does not compile now'
            same = open(tmp, 'rb').read() == open(os.path.join(d, stem + '.metallib'), 'rb').read(); os.unlink(tmp)
            if not same: return f'a fresh compile of {stem}.metal differs from its library'
        return None

    def fill(self, mac_dir, ios_dir=None, targets=None):
        """Takes the libraries of an earlier build: mac_dir = its Mac b-<chain>/ folder, ios_dir = the iOS folder of the same chain (or None). Returns the lines to print"""
        stamp_file = os.path.join(self.root, 'filled.json')
        try: stamps = json.load(open(stamp_file))
        except (OSError, ValueError): stamps = {}
        names = set(os.listdir(mac_dir)); stems = sorted(n[:-6] for n in names if n.endswith('_b.metal'))
        todo, notes = {}, []
        for target, d in (('mac', mac_dir), ('ios', ios_dir)):
            if targets is not None and target not in targets: continue   # checking an earlier build compiles samples too
            if target not in self.targets or not d or not os.path.isdir(d): continue
            libs = names if d == mac_dir else set(os.listdir(d))
            have = [s for s in stems if s + '.metallib' in libs]; key = self.ident[target].hex() + ':' + os.path.realpath(d)
            if not have or stamps.get(key) == len(have): continue
            why = self._check(target, d, have, mac_dir)
            if why: notes.append(f'Metal cache: not filled from {d}: {why}')
            else: todo[target] = (d, set(have))
            stamps[key] = len(have)
        added = collections.Counter()
        for stem in stems:
            ts = [t for t, (d, have) in todo.items() if stem in have]
            if not ts: continue
            src = open(os.path.join(mac_dir, stem + '.metal'), 'rb').read()
            for t in ts:
                p = self.path(t, src)
                if os.path.exists(p): continue
                os.makedirs(os.path.dirname(p), exist_ok=True); clone(os.path.join(todo[t][0], stem + '.metallib'), p); added[t] += 1
        for t, (d, have) in todo.items():
            self.count((t, 'filled'), added[t]); notes.append(f'Metal cache: {added[t]} {t} libraries added from {d} ({len(have)} there)')
        os.makedirs(self.root, exist_ok=True)
        tmp = f'{stamp_file}.tmp-{os.getpid()}'; json.dump(stamps, open(tmp, 'w'), indent=1); os.replace(tmp, stamp_file)
        return notes

    def summary(self):
        s = self.stats
        return 'Metal cache: ' + '; '.join(f'{t} {s[t, "reused"]} reused, {s[t, "compiled"]} compiled' + (f', {s[t, "filled"]} filled from earlier builds' if s[t, 'filled'] else '')
                                          for t in self.targets)
