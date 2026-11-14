#!/usr/bin/env python3
# NXForge automation interface: the converter app's core functions from a terminal, a script or an agent (scripts/nxforge_mcp.py wraps it as an MCP server).
# It reads the converter's own state, so the app and this tool agree: settings.json and builds.json in ~/Library/Application Support/NXForge Converter (NXC_SUPPORT_DIR
# moves it, as for the app), the engine checkout the settings name, the game folders of the recorded builds and their <id>_build folders.
# Commands (every one takes --json for machine-readable output; docs/automation.md has the details):
#   status                 engine version, update state, running builds and games, free space, recorded builds
#   builds                 the recorded builds: app, game folder, engine, whether the app is still there, backups
#   disk                   what NXForge uses on disk, by category, with what a safe cleanup would free
#   clean                  delete what a category holds: --safe (the hourly-safe set), or --only <category>[,…]; --dry-run lists without deleting
#   build <game folder>    build or rebuild a game's Mac app as the converter does, refused when the game needs glslang / nsz / zbic and it is missing (--plan: the dry run that lists which stages are reused or redone; --background)
#   jobs / job <id> / stop <id>   background builds started here
#   update [--apply]       engine updates: commits waiting on its update branch; --apply fast-forwards
#   doctor [game folder]   the tools a build needs (git, python modules, dotnet, xcrun), then glslang / nsz / zbic: optional unless the game folder needs one; exit 1 when one is missing
# Safety: nothing here touches the NSPs, prod.keys, installed or recorded apps, saves, profiles or the engine's own checkout; build-folder and Metal-cache cleanups wait while a
# build runs; worktrees are only reported unless named one by one, and one with uncommitted or unpushed work, or the engine's, is never removed.
# Exit code 0 on success (also when there is nothing to delete), 1 on an error, 2 when a cleanup or build was refused because something is running.
import argparse, datetime, fcntl, json, os, re, shutil, signal, subprocess, sys, time
from pathlib import Path

HOME = Path.home()
SCRIPT = 'scripts/build_ipa_from_nsp.py'
TOOL_PATHS = ['/opt/homebrew/bin', '/usr/local/bin', '/usr/local/share/dotnet', str(HOME / '.dotnet')]
BUILD_PROCS = ('build_ipa_from_nsp.py', 'dmsh_build.py', 'pso_offline.py', 'pack_app.py', 'nx_extract', 'metal-pack')   # a build is running while one of these is
GAME_PROCS = {'dmhost'}   # a game is running (the Mac app's launcher starts the host under this name)
MTLCACHE_GB = float(os.environ.get('DMSH_MTLCACHE_GB') or 12)   # the size a cleanup trims the shared Metal library cache to (the build's own prune uses its LIMIT_GB)
CATEGORIES = {
    # name: (description, part of --safe)
    'gpuarchiver': ("Metal's pipeline-archive build folders in the user cache folder, idle for an hour and older than every running game", True),
    'build-temp': ('temporary files in each <id>_build: tmp/, tmp.noindex/, *.partial (left by a stopped or failed step)', True),
    'metal-cache': (f'the shared compiled-shader cache (~/Library/Caches/NXForge/metallib.db; the metallib folder before 0.11), trimmed to {MTLCACHE_GB:g} GB by deleting the libraries unused the longest', True),
    'app-backups': ('apps a rebuild moved to app-backups/: all but the newest per game, and only ones older than --backup-days (default 3)', True),
    'old-logs': ('files in ~/Library/Logs/nxnative older than --log-days (default 30)', True),
    'build-unused': ("each <id>_build's rewritten modules of versions other than the last packed one (patched_<v>, nro_<v>) and the game's survey folder", False),
    'build-cache': ('each <id>_build except logs/, profile/ and run/: the next build extracts and compiles everything again (about 30 min or more)', False),
    'swift-build': ("the converter app's Swift build folder (app/.build) in each NXForge checkout; the next app install rebuilds it", False),
    'worktrees': ('git worktrees of the engine: reported only; `clean --worktree <path>` removes one that is clean, pushed and not the engine', False),
}
SAFE = [c for c, (_, s) in CATEGORIES.items() if s]


class Refused(Exception): pass


# ---------- the converter's state ----------

def support_dir():
    d = os.environ.get('NXC_SUPPORT_DIR')
    return Path(d) if d else HOME / 'Library/Application Support/NXForge Converter'


def load_json(p, default):
    try: return json.loads(Path(p).read_text())
    except (OSError, ValueError): return default


def settings(): return load_json(support_dir() / 'settings.json', {})
def records(): return load_json(support_dir() / 'builds.json', [])


def layered(p): return bool(p) and (Path(p) / 'layer/ENGINE').is_file() and (Path(p) / 'scripts/layer.py').is_file()
def is_repo(p): return layered(p) or (bool(p) and (Path(p) / SCRIPT).is_file() and (Path(p) / 'dm/tools/nx_extract/Program.cs').is_file())


def tree_of(repo):
    """Where the engine's files are and builds run: tree/ of a layered checkout (0.19.0 on: scripts/layer.py), else the checkout"""
    return str(Path(repo) / 'tree') if layered(repo) else repo


def ensure_tree(repo):
    """Assemble tree/ from the layer (a quick no-op while it matches); Refused when it cannot be"""
    if not layered(repo): return
    r = subprocess.run([sys.executable, '-I', str(Path(repo) / 'scripts/layer.py'), 'assemble'], capture_output=True, text=True, cwd=repo, timeout=1800)
    if r.returncode: raise Refused('engine tree not assembled: ' + (r.stderr or r.stdout).strip().removeprefix('layer.py: '))


def find_repo(s=None):
    """The engine checkout as the app finds it: the setting, then this tool's own checkout, then the usual places"""
    s = settings() if s is None else s
    cands = [s.get('repo'), str(Path(__file__).resolve().parent.parent)]
    cands += [str(HOME / p) for p in ('Development/NXForge', 'Developer/nxforge', 'nxforge', 'src/nxforge', 'Documents/nxforge', 'Projects/nxforge', 'code/nxforge')]
    cands += [str(support_dir() / 'nxforge')]
    return next((str(Path(c).expanduser()) for c in cands if is_repo(c and os.path.expanduser(c))), None)


def tool_env(repo):
    env = dict(os.environ)
    env['PATH'] = ':'.join(TOOL_PATHS + [p for p in env.get('PATH', '').split(':') if p and p not in TOOL_PATHS])
    if 'DOTNET_ROOT' not in env and (dn := shutil.which('dotnet', path=env['PATH'])): env['DOTNET_ROOT'] = str(Path(dn).resolve().parent)
    return env


def find_python(s, repo):
    """The Python the app would use: the setting, its own venv, the checkout's .venv, then python3 on PATH; the first with the script's modules"""
    probe = ("import sys\ndef has(m):\n try: __import__(m); return True\n except ImportError: return False\n"
             "miss=[m for m in ('lz4.block','capstone','fontTools') if not has(m)]\n"
             "miss+=[] if has('compression.zstd') or has('backports.zstd') else ['backports.zstd']\nprint(','.join(miss))")
    env = tool_env(repo)
    cands = [s.get('python'), str(support_dir() / 'venv/bin/python3'), repo and f'{repo}/.venv/bin/python3']
    cands += [f'{d}/python3' for d in env['PATH'].split(':')]
    first = None
    for c in cands:
        if not c or not os.access(c, os.X_OK): continue
        try: r = subprocess.run([c, '-I', '-c', probe], capture_output=True, text=True, timeout=30, env=env)
        except (OSError, subprocess.TimeoutExpired): continue
        if r.returncode: continue
        miss = r.stdout.strip()
        if not miss: return c, []
        first = first or (c, miss.split(','))
    return first or (None, ['python3'])


def git(repo, *a, timeout=60):
    try: r = subprocess.run(['git', '-C', str(repo), *a], capture_output=True, text=True, timeout=timeout, env=tool_env(repo))
    except (OSError, subprocess.TimeoutExpired): return None
    return r.stdout.strip() if r.returncode == 0 else None


def release_name(desc):
    """git describe → the app's release name: v0.2.0-2-g4ad5093 → 0.2.0+2, v0.2.0-0-g… → 0.2.0; anything else as it is"""
    m = re.fullmatch(r'v?(\d+\.\d+\.\d+)-(\d+)-g[0-9a-f]+', desc or '')
    return (m[1] + (f'+{m[2]}' if m[2] != '0' else '')) if m else desc


def engine(repo):
    if not repo: return None
    log = git(repo, 'log', '-1', '--format=%H%x1f%s%x1f%cs')
    if not log: return None
    commit, subject, date = (log.split('\x1f') + ['', ''])[:3]
    desc = git(repo, 'describe', '--tags', '--match', 'v[0-9]*.[0-9]*.[0-9]*', '--long', commit)
    version = release_name(desc) if desc else None
    return {'repo': repo, 'commit': commit, 'subject': subject, 'date': date, 'branch': git(repo, 'rev-parse', '--abbrev-ref', 'HEAD') or '',
            'dirty': bool(git(repo, 'status', '--porcelain', '--untracked-files=no')), 'version': version or commit[:7]}


def processes():
    """[(pid, elapsed seconds, command line)]; an error when ps fails, so nothing is deleted without knowing what runs"""
    r = subprocess.run(['ps', '-axww', '-o', 'pid=,etime=,command='], capture_output=True, text=True)
    if r.returncode: raise OSError(f'ps failed: {r.stderr.strip()}')
    out = []
    for line in r.stdout.splitlines():
        p = line.split(None, 2)
        if len(p) == 3: out.append((int(p[0]), etime_s(p[1]), p[2]))
    return out


def etime_s(s):   # ps's elapsed time, [[dd-]hh:]mm:ss
    d, _, hms = s.rpartition('-')
    p = [int(x) for x in hms.split(':')]
    p = [0] * (3 - len(p)) + p
    return int(d or 0) * 86400 + p[0] * 3600 + p[1] * 60 + p[2]


def running(procs=None):
    procs = processes() if procs is None else procs
    me = os.getpid()
    builds = [{'pid': p, 'seconds': t, 'command': c} for p, t, c in procs if p != me and any(k in c for k in BUILD_PROCS)]
    games = [{'pid': p, 'seconds': t, 'command': c} for p, t, c in procs if os.path.basename(c.split()[0]) in GAME_PROCS]
    return {'builds': builds, 'games': games}


def brief(command):
    """A running build's or game's command line as a person reads it: from the tool itself (build_ipa_from_nsp.py ..., dmhost ...), without the interpreter's path in front of it
    or the caffeinate wrapper the converter starts it under, and with the paths in its arguments shortened to their last part"""
    words = command.split()
    start = next((i for i, w in enumerate(words) if any(k in os.path.basename(w) for k in BUILD_PROCS) or os.path.basename(w) in GAME_PROCS), 0)
    return ' '.join(os.path.basename(w) if '/' in w and not w.startswith('-') else w for w in words[start:])


def shown(items):
    """running()'s builds or games for the text output: one line per tool run, so the caffeinate wrapper and the Python it starts are not two builds"""
    out, seen = [], set()
    for p in sorted(items, key=lambda p: 'caffeinate' in p['command'].split()[0]):   # the tool's own process first, its wrapper after
        if (b := brief(p['command'])) not in seen: seen.add(b); out.append({**p, 'brief': b})
    return out


def game_dirs(s=None, recs=None):
    """The game folders NXForge knows: the recorded builds' and the settings' last one"""
    s = settings() if s is None else s
    recs = records() if recs is None else recs
    seen, out = set(), []
    for d in [r.get('game_dir') for r in recs] + [s.get('game_dir')]:
        if d and (p := Path(d).expanduser()).is_dir() and str(p) not in seen: seen.add(str(p)); out.append(p)
    return out


SCAN = ('Documents', 'Downloads', 'Desktop')   # where a game folder or a loose <id>_build (a Switch 2 dump's: Ocarina of Time) usually is


def build_dirs(dirs):
    """<id>_build folders in the known game folders, their parents and the top of ~/Documents, ~/Downloads and ~/Desktop (one level down too)"""
    roots, seen, out = list(dirs) + [d.parent for d in dirs] + [HOME / n for n in SCAN], set(), []
    for r in roots:
        if not r.is_dir(): continue
        try: subs = [r] + [c for c in r.iterdir() if c.is_dir() and not c.is_symlink() and not c.name.startswith('.') and c.suffix != '.app' and not c.name.endswith('_build')]
        except OSError: continue
        for d in subs:
            try: found = sorted(d.glob('*_build'))
            except OSError: continue
            for b in found:
                if b.is_dir() and not b.is_symlink() and str(b) not in seen and re.fullmatch(r'[0-9A-Fa-f]{16}_build', b.name): seen.add(str(b)); out.append(b)
    return out


def protected_apps(recs=None):
    """Apps never deleted: every recorded build's app"""
    recs = records() if recs is None else recs
    return {str(Path(r['app']).expanduser().resolve()) for r in recs if r.get('app')}


def size_of(p):
    """Allocated bytes under p (du -sk: fast on big app bundles); 0 when it is gone"""
    p = Path(p)
    if not p.exists() and not p.is_symlink(): return 0
    if p.is_symlink() or p.is_file(): return p.lstat().st_blocks * 512
    try:
        r = subprocess.run(['du', '-sk', str(p)], capture_output=True, text=True, timeout=600)
        if r.stdout.strip(): return int(r.stdout.split()[0]) * 1024
    except (OSError, subprocess.TimeoutExpired, ValueError): pass
    total = 0
    for root, ds, fs in os.walk(p):
        for n in ds + fs:
            try: total += os.lstat(os.path.join(root, n)).st_blocks * 512
            except OSError: pass
    return total


def free_bytes(p=HOME):
    st = os.statvfs(p)
    return st.f_bavail * st.f_frsize


def gb(b): return round(b / 1e9, 2)


# ---------- cleanup candidates, by category ----------
# Each finder returns (items, notes): items [{'path', 'bytes', 'why'}] it would delete; notes [str] on what it left and why.

def gpuarchiver_dir():
    r = subprocess.run(['getconf', 'DARWIN_USER_CACHE_DIR'], capture_output=True, text=True)
    return Path(r.stdout.strip()) / 'com.apple.gpuarchiver' if r.returncode == 0 and r.stdout.strip() else None


def find_gpuarchiver(ctx):
    d = ctx.get('gpuarchiver_dir') or gpuarchiver_dir()
    if not d or not d.is_dir(): return [], []
    now = time.time()
    starts = [now - g['seconds'] for g in ctx['running']['games']]
    limit = min([now - 3600] + [s - 60 for s in starts])
    items, kept = [], 0
    for f in sorted(d.glob('gpuarchiver-*')):   # one item per folder here, collapsed into one below
        if f.is_symlink() or not f.is_dir(): continue
        t, b = f.lstat().st_mtime, 0
        for root, ds, fs in os.walk(f):
            for n in ds + fs:
                try: st = os.lstat(os.path.join(root, n))
                except OSError: continue
                t = max(t, st.st_mtime); b += st.st_blocks * 512
        if t >= limit: kept += 1; continue
        items.append({'path': str(f), 'bytes': b + f.lstat().st_blocks * 512})
    if items: items = [{'path': str(d), 'bytes': sum(i['bytes'] for i in items), 'why': f'{len(items)} idle Metal build folders (gpuarchiver-*)', 'dirs': [i['path'] for i in items]}]
    return items, [f'{kept} gpuarchiver folders kept (changed in the last hour or since a running game started)'] if kept else []


def find_build_temp(ctx):
    items = []
    for b in ctx['build_dirs']:
        for p in sorted(b.iterdir()):
            if p.name in ('tmp', 'tmp.noindex') or p.name.endswith('.partial'):
                items.append({'path': str(p), 'bytes': size_of(p), 'why': f'temporary files of {b.name}'})
    return items, []


def mtlcache_path():
    """The shared compiled-shader cache: one SQLite file (metallib.db, dm/tools/shader_cache.py) since 0.11, a folder of metallib files before"""
    if e := os.environ.get('DMSH_MTLCACHE'): return Path(e)
    db = HOME / 'Library/Caches/NXForge/metallib.db'
    return db if db.exists() or not (HOME / 'Library/Caches/NXForge/metallib').is_dir() else HOME / 'Library/Caches/NXForge/metallib'


def find_metal_cache(ctx):
    root = ctx.get('mtlcache_path') or mtlcache_path()
    limit = ctx.get('mtlcache_gb') or MTLCACHE_GB
    if root.is_file() or root.suffix == '.db':
        size = sum(size_of(Path(f'{root}{x}')) for x in ('', '-wal', '-shm'))
        if size <= limit * 2**30: return [], [f'Metal cache {size / 2**30:.1f} GB, under its {limit:g} GB limit'] if size else []
        if not ctx['repo'] or not (Path(tree_of(ctx['repo'])) / 'dm/tools/shader_cache.py').is_file(): return [], ['[RED] Metal cache over its limit, but the engine has no shader_cache.py to trim it with']
        return [{'path': str(root), 'bytes': size - int(limit * 2**30), 'why': f'trim the {size / 2**30:.1f} GB cache to {limit:g} GB (entries unused the longest)', 'db_limit': int(limit * 2**30)}], []
    files, total = [], 0
    for t in ('mac', 'ios'):
        for d, _, names in os.walk(root / t):
            for n in names:
                try: st = os.stat(os.path.join(d, n))
                except OSError: continue
                files.append((st.st_mtime, st.st_blocks * 512, os.path.join(d, n))); total += st.st_blocks * 512
    if total <= limit * 2**30: return [], [f'Metal cache {total / 2**30:.1f} GB, under its {limit:g} GB limit'] if files else []
    gone, size = [], 0
    for _, b, p in sorted(files):
        if total - size <= limit * 2**30: break
        gone.append(p); size += b
    # one item for the whole trim: the files are many and small
    return [{'path': str(root), 'bytes': size, 'why': f'{len(gone):,} of {len(files):,} libraries unused the longest (cache {total / 2**30:.1f} GB > {limit:g} GB)', 'files': gone}], []


def backup_dirs(ctx):
    dirs = {Path(r['app']).expanduser().parent / 'app-backups' for r in ctx['records'] if r.get('app')}
    dirs |= {d / 'app-backups' for d in ctx['game_dirs']}
    dirs |= {b.parent / 'app-backups' for b in ctx['build_dirs']}
    if o := ctx['settings'].get('out_dir'): dirs.add(Path(o).expanduser() / 'app-backups')
    return sorted(d for d in dirs if d.is_dir())


BACKUP = re.compile(r'^(?P<name>.+) \((?P<engine>[^,()]+), (?P<stamp>\d{4}-\d\d-\d\d-\d\d-\d\d)\)\.app$')


def find_app_backups(ctx):
    days = ctx.get('backup_days', 3)
    cutoff = time.time() - days * 86400
    keep_n = ctx.get('backup_keep', 1)
    items, notes, protected = [], [], ctx['protected']
    for d in backup_dirs(ctx):
        groups = {}
        for p in d.iterdir():
            if p.suffix != '.app' or p.is_symlink(): continue
            m = BACKUP.match(p.name)
            when = datetime.datetime.strptime(m['stamp'], '%Y-%m-%d-%H-%M').timestamp() if m else p.lstat().st_mtime
            groups.setdefault(m['name'] if m else p.stem, []).append((when, p))
        for name, bs in groups.items():
            bs.sort(reverse=True)
            for i, (when, p) in enumerate(bs):
                if str(p.resolve()) in protected: notes.append(f'{p} kept: a recorded build'); continue
                if i < keep_n: notes.append(f'{p.name} kept: the newest backup of {name}'); continue
                if when > cutoff: notes.append(f'{p.name} kept: younger than {days:g} days'); continue
                items.append({'path': str(p), 'bytes': size_of(p), 'why': f'older backup of {name}'})
    return items, notes


def find_old_logs(ctx):
    d = ctx.get('logs_dir') or HOME / 'Library/Logs/nxnative'
    cutoff = time.time() - ctx.get('log_days', 30) * 86400
    items = []
    if d.is_dir():
        for root, _, fs in os.walk(d):
            for n in fs:
                p = Path(root) / n
                try: st = p.lstat()
                except OSError: continue
                if st.st_mtime < cutoff: items.append({'path': str(p), 'bytes': st.st_blocks * 512, 'why': 'log older than the limit'})
    return items, []


def recorded_version(ctx, b):
    """The version the recorded build of this build folder packed: patched_<v> / nro_<v> with the newest key; None when unknown"""
    cands = [(p.stat().st_mtime, p.name.split('_', 1)[1].removesuffix('.key')) for p in b.iterdir() if p.name.startswith(('patched_', 'nro_')) and p.name.endswith('.key')]
    return max(cands)[1] if cands else None


def last_change(b):
    """The newest mtime among a build folder and its entries one level down (a build writes its keys, logs and stage folders there)"""
    t = b.stat().st_mtime
    for p in b.iterdir():
        try:
            t = max(t, p.lstat().st_mtime)
            if p.is_dir() and not p.is_symlink(): t = max([t] + [c.lstat().st_mtime for c in p.iterdir()])
        except OSError: pass
    return t


def idle_builds(ctx, notes):
    """The build folders unchanged for ctx['idle_hours'] (default 24): one built or worked on today is someone's current work"""
    h = ctx.get('idle_hours', 24)
    out = []
    for b in ctx['build_dirs']:
        age = (time.time() - last_change(b)) / 3600
        if age < h: notes.append(f'{b} kept: changed {age:.1f} hours ago (--idle-hours {h:g})')
        else: out.append(b)
    return out


def find_build_unused(ctx):
    items, notes = [], []
    for b in idle_builds(ctx, notes):
        v = recorded_version(ctx, b)
        if not v: notes.append(f'{b}: packed version unknown, nothing taken'); continue
        for p in sorted(b.iterdir()):
            n = p.name.removesuffix('.key')
            if n.startswith(('patched_', 'nro_')) and n.split('_', 1)[1] != v: items.append({'path': str(p), 'bytes': size_of(p), 'why': f'files of version {n.split("_", 1)[1]}'})
        if (sv := b.parent / f'{b.name.removesuffix("_build")}_survey').is_dir(): items.append({'path': str(sv), 'bytes': size_of(sv), 'why': 'survey of a game that has a profile'})
    # extract/<version> is left: which versions a build needs (the base's RomFS, the profile's shader versions) only the build knows; a build with --cleanup unused removes the rest
    return items, notes


def find_build_cache(ctx):
    items, notes = [], []
    for b in idle_builds(ctx, notes):
        for p in sorted(b.iterdir()):
            if p.name not in ('logs', 'profile', 'run'): items.append({'path': str(p), 'bytes': size_of(p), 'why': f'build cache of {b.name}'})
    if items: notes += ['the next build of these games extracts them and compiles every shader again; it needs the game files (and prod.keys for NSPs)',
                        "a Mac app's game files are APFS clones of extract/: while the app is there, deleting extract/ frees little of its size"]
    return items, notes


def checkouts(ctx):
    """The engine and its worktrees (git worktree list), as Paths"""
    repo = ctx['repo']
    if not repo: return []
    out = [Path(l[9:]) for l in (git(repo, 'worktree', 'list', '--porcelain') or '').splitlines() if l.startswith('worktree ')]
    return out or [Path(repo)]


def find_swift_build(ctx):
    items = []
    for c in checkouts(ctx):
        if (p := c / 'app/.build').is_dir(): items.append({'path': str(p), 'bytes': size_of(p), 'why': f'Swift build folder of {c}'})
    return items, []


def worktree_state(ctx, wt):
    """(removable, why, info) for one worktree of the engine"""
    wt = Path(wt).expanduser().resolve()
    main_wt = checkouts(ctx)[0].resolve() if checkouts(ctx) else None
    info = {'path': str(wt), 'branch': git(wt, 'rev-parse', '--abbrev-ref', 'HEAD') or '?'}
    if wt not in [c.resolve() for c in checkouts(ctx)]: return False, 'not a worktree of the engine', info
    if wt == main_wt: return False, 'the main checkout', info
    if ctx['repo'] and wt == Path(ctx['repo']).resolve(): return False, 'the converter engine (settings "repo") runs from it', info
    if ctx['repo'] and layered(ctx['repo']) and wt == Path(tree_of(ctx['repo'])).resolve(): return False, 'the engine tree builds run in (scripts/layer.py assemble makes it)', info
    if git(wt, 'status', '--porcelain'): return False, 'it has uncommitted or untracked changes', info
    head = git(wt, 'rev-parse', 'HEAD')
    if head and git(wt, 'branch', '-r', '--contains', head) == '': return False, 'its commit is not on any remote branch (unpushed work)', info
    if any(str(wt) in b['command'] for b in ctx['running']['builds']): return False, 'a build runs from it', info
    return True, 'clean and pushed', info


def find_worktrees(ctx):
    notes, items = [], []
    for c in checkouts(ctx)[1:]:
        ok, why, info = worktree_state(ctx, c)
        notes.append(f'{c} ({info["branch"]}): {"removable with clean --worktree" if ok else "kept"}: {why}, {gb(size_of(c))} GB')
    return items, notes


FINDERS = {'gpuarchiver': find_gpuarchiver, 'build-temp': find_build_temp, 'metal-cache': find_metal_cache, 'app-backups': find_app_backups, 'old-logs': find_old_logs,
           'build-unused': find_build_unused, 'build-cache': find_build_cache, 'swift-build': find_swift_build, 'worktrees': find_worktrees}
NEEDS_IDLE = {'build-temp', 'metal-cache', 'build-unused', 'build-cache', 'swift-build'}   # wait while a build runs


def context(**kw):
    s, recs = settings(), records()
    dirs = game_dirs(s, recs)
    ctx = {'settings': s, 'records': recs, 'repo': find_repo(s), 'game_dirs': dirs, 'build_dirs': build_dirs(dirs), 'protected': protected_apps(recs), 'running': running()}
    if g := kw.pop('game', None):   # only one game: its folder, its <id>_build, or its title ID
        g = str(Path(g).expanduser())
        ctx['build_dirs'] = [b for b in ctx['build_dirs'] if g in (str(b), str(b.parent)) or b.name.lower().startswith(Path(g).name.lower().removesuffix('_build'))]
        ctx['game_dirs'] = [d for d in dirs if str(d) == g or d in [b.parent for b in ctx['build_dirs']]]
        if not ctx['build_dirs'] and not ctx['game_dirs']: raise Refused(f'no game folder or build folder matches {g}')
    ctx.update({k: v for k, v in kw.items() if v is not None})
    return ctx


def overview(ctx):
    """What NXForge uses on disk, beyond the cleanup categories: per game folder, per <id>_build, installed apps"""
    games = []
    for d in ctx['game_dirs']:
        entries = []
        for p in sorted(d.iterdir()):
            if p.name.endswith(('_build', '-work', '_survey')) or p.name == 'app-backups' or p.suffix == '.app':
                entries.append({'path': str(p), 'bytes': size_of(p), 'kind': 'app' if p.suffix == '.app' else p.name.rsplit('_', 1)[-1].rsplit('-', 1)[-1]})
        games.append({'folder': str(d), 'entries': entries, 'bytes': sum(e['bytes'] for e in entries)})
    caches = [{'path': str(p), 'bytes': size_of(p)} for p in (HOME / 'Library/Caches/NXForge', gpuarchiver_dir(), HOME / 'Library/Logs/nxnative',
                                                               HOME / 'Library/Application Support/nxnative') if p and p.exists()]
    known = {g['folder'] for g in games}
    other = []
    for r in [HOME / n for n in SCAN]:
        try: subs = sorted(r.iterdir()) if r.is_dir() else []
        except OSError: continue
        for p in subs:
            if p.suffix == '.app' and str(p.parent) not in known: other.append({'path': str(p), 'bytes': size_of(p), 'kind': 'app'})
            elif p.is_dir() and not p.is_symlink() and p.suffix != '.app' and str(p) not in known:
                try: apps = [c for c in p.iterdir() if c.suffix == '.app']
                except OSError: continue
                if apps: other.append({'path': str(p), 'bytes': size_of(p), 'kind': 'game folder', 'apps': [str(a) for a in apps]})
    games += [{'folder': o['path'], 'entries': [o], 'bytes': o['bytes'], 'unrecorded': True} for o in other]
    builds = [{'path': str(b), 'bytes': size_of(b), 'entries': {p.name: size_of(p) for p in sorted(b.iterdir())}} for b in ctx['build_dirs']]
    return {'games': games, 'build_folders': builds, 'caches': caches, 'checkouts': [{'path': str(c), 'bytes': size_of(c)} for c in checkouts(ctx)]}


def find(ctx, cats):
    out = {}
    for c in cats:
        if c in NEEDS_IDLE and ctx['running']['builds']:
            out[c] = {'items': [], 'notes': ['skipped: a build is running'], 'skipped': True}; continue
        try: items, notes = FINDERS[c](ctx)
        except OSError as e: items, notes = [], [f'[RED] {c}: {e}']
        out[c] = {'items': items, 'notes': notes, 'bytes': sum(i['bytes'] for i in items)}
    return out


def delete(item, ctx):
    if 'db_limit' in item:   # the shared cache's SQLite file, trimmed by the engine's own shader_cache.Store (it also gives the pages back)
        code = ('import sys; sys.path.insert(0, sys.argv[1]); import shader_cache; s = shader_cache.Store(sys.argv[2]); '
                "n, total, gone = s.prune_oldest('metallib/', int(sys.argv[3])); s.close(); print(n, total, gone)")
        r = subprocess.run([sys.executable, '-I', '-c', code, f'{tree_of(ctx["repo"])}/dm/tools', item['path'], str(item['db_limit'])], capture_output=True, text=True, timeout=1800)
        if r.returncode: raise OSError(f'trim failed: {(r.stderr or r.stdout).strip()[-300:]}')
        return
    if 'dirs' in item:   # many folders inside one cache folder
        for f in item['dirs']: shutil.rmtree(f, ignore_errors=not Path(f).exists())
        return
    if 'files' in item:   # a trim of many files
        for f in item['files']:
            try: os.unlink(f)
            except FileNotFoundError: pass
        return
    p = Path(item['path'])
    if p.is_dir() and not p.is_symlink(): shutil.rmtree(p)
    elif p.exists() or p.is_symlink(): p.unlink()


def guard(item, ctx):
    """Last check before a delete: never an app that is recorded or installed, a game file, keys, or anything outside NXForge's places"""
    p = Path(item['path']).expanduser()
    rp = str(p.resolve())
    if 'db_limit' in item or 'files' in item: return   # a trim inside the cache
    if 'dirs' in item:
        if any(Path(f).parent != p or not Path(f).name.startswith('gpuarchiver-') for f in item['dirs']): raise Refused('not a gpuarchiver folder')
        return
    if rp in ctx['protected']: raise Refused(f'{p} is a recorded build')
    if p.suffix == '.app' and p.parent.name != 'app-backups': raise Refused(f'{p} is an app outside app-backups/')
    if p.suffix.lower() in ('.nsp', '.nsz', '.xci', '.xcz', '.keys') or p.name in ('prod.keys', 'title.keys'): raise Refused(f'{p} is a game or keys file')
    home = str(HOME.resolve())
    if rp in ('/', home) or len(Path(rp).parts) < 4: raise Refused(f'{p} is too high up')
    for top in ('/Applications', HOME / 'Applications', HOME / 'Documents', HOME / 'Downloads', HOME / 'Desktop', HOME / 'Library'):
        if rp == str(Path(top).resolve()): raise Refused(f'{p} is {top}')


def lock():
    support_dir().mkdir(parents=True, exist_ok=True)
    f = open(support_dir() / 'cli-clean.lock', 'w')
    try: fcntl.flock(f, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        f.close(); raise Refused('another cleanup is running') from None
    return f


def log_line(msg):
    with open(support_dir() / 'cli-clean.log', 'a') as f: f.write(f'{datetime.datetime.now():%Y-%m-%d %H:%M:%S} {msg}\n')


def clean(cats, dry_run=False, ctx=None, worktree=None):
    ctx = ctx or context()
    held = None if dry_run else lock()
    try:
        res = {'dry_run': dry_run, 'categories': find(ctx, cats), 'free_before': free_bytes(), 'errors': []}
        if worktree:
            ok, why, info = worktree_state(ctx, worktree)
            item = {'path': info['path'], 'bytes': size_of(info['path']), 'why': why}
            res['categories']['worktrees'] = {'items': [item] if ok else [], 'notes': [] if ok else [f'{info["path"]} kept: {why}'], 'bytes': item['bytes'] if ok else 0}
            if not ok: res['errors'].append(f'{info["path"]} not removed: {why}')
        for c, r in res['categories'].items():
            for it in r['items']:
                if dry_run: continue
                try:
                    guard(it, ctx)
                    if c == 'worktrees':
                        if git(ctx['repo'], 'worktree', 'remove', it['path'], timeout=600) is None: raise OSError('git worktree remove failed')
                    else: delete(it, ctx)
                    it['deleted'] = True; log_line(f'deleted {it["path"]} ({gb(it["bytes"])} GB, {c}: {it["why"]})')
                except (OSError, Refused) as e:
                    it['deleted'] = False; res['errors'].append(f'{it["path"]}: {e}'); log_line(f'[RED] not deleted {it["path"]}: {e}')
        for r in res['categories'].values(): [(i.pop('files', None), i.pop('dirs', None)) for i in r['items']]
        res['bytes'] = sum(r.get('bytes', 0) for r in res['categories'].values())
        res['free_after'] = free_bytes()
        if not dry_run: res['freed_bytes'] = max(res['free_after'] - res['free_before'], 0)   # what the volume got back: less than the sizes when clones share blocks
        return res
    finally:
        if held: held.close()


# ---------- builds ----------

def jobs_dir():
    d = support_dir() / 'cli-jobs'
    d.mkdir(parents=True, exist_ok=True)
    return d


def script_has(repo, py, opt):
    r = subprocess.run([py, f'{tree_of(repo)}/{SCRIPT}', '--help'], capture_output=True, text=True, cwd=tree_of(repo), env=tool_env(repo), timeout=120)
    return opt in r.stdout


def saved_keys(s, game_dir):
    """The keys a build uses, as the app picks them: the keys file saved in Settings, else the game folder's prod.keys, else the last chosen."""
    for k in (s.get('default_keys'), str(Path(game_dir) / 'prod.keys'), s.get('keys')):
        if k and Path(k).expanduser().is_file(): return k
    return None


def build_command(game_dir, *, plan=False, rebuild=None, out=None, keys=None, cleanup=None, sign=None):
    s = settings()
    repo = find_repo(s)
    if not repo: raise Refused('no NXForge engine checkout found (settings "repo")')
    ensure_tree(repo)
    py, miss = find_python(s, repo)
    if not py or miss: raise Refused(f'no Python with the script\'s modules ({", ".join(miss)}): run doctor')
    gd = Path(game_dir).expanduser().resolve()
    if not gd.is_dir(): raise Refused(f'{gd} is not a folder')
    if not plan and (needs := game_needs(gd, repo)):   # as the converter does before it starts a build: a missing one would stop the build partway (nsz at the start, zbic at the unpack)
        tools = optional_tools(py, tool_env(repo))
        if gone := [n for n in needs if not tools[n][0]]: raise Refused('; '.join(f'{n} is needed ({needs[n]}): {tools[n][2]}' for n in gone))
    keys = keys or saved_keys(s, gd)
    if not keys or not Path(keys).expanduser().is_file(): raise Refused('no prod.keys: choose one in NXForge Settings (Keys file), put one in the game folder or pass --keys')
    if plan and not script_has(repo, py, '--plan'): raise Refused(f'the engine at {repo} has no --plan yet (update it)')
    args = [py, '-u', f'{tree_of(repo)}/{SCRIPT}', str(gd), '-k', str(Path(keys).expanduser()), '--platform', 'mac-app', '--progress', 'json']
    if plan: args.append('--plan')
    if sign := sign or s.get('sign_identity'): args += ['--mac-sign', sign]
    if o := rebuild or out or s.get('out_dir'): args += ['-o', str(Path(o).expanduser())]
    cleanup = cleanup or s.get('cleanup')
    if cleanup and cleanup != 'off' and not plan: args += ['--cleanup', cleanup]
    return repo, args


def back_up(app, eng):
    """As the app does: move the old app to app-backups/<name> (<engine>, <time>).app before a rebuild"""
    u = Path(app)
    d = u.parent / 'app-backups'
    d.mkdir(exist_ok=True)
    dst = d / f'{u.stem} ({(eng or {}).get("version", "old engine")}, {datetime.datetime.now():%Y-%m-%d-%H-%M}).app'
    u.rename(dst)
    return dst


def record(app, game_dir, eng):
    recs = [r for r in records() if r.get('app') != app]
    e = {k: eng[k] for k in ('commit', 'subject', 'date', 'branch', 'dirty', 'version')}
    recs.append({'app': app, 'game_dir': game_dir, 'engine': e, 'repo': eng['repo'], 'built_at': f'{datetime.datetime.now():%Y-%m-%d %H:%M}'})
    (support_dir() / 'builds.json').write_text(json.dumps(recs, indent=2, sort_keys=True))


def run_build(game_dir, *, plan=False, rebuild=None, events=None, **kw):
    """Runs a build in the foreground; events(dict) gets the script's JSON events. Returns {'ok', 'app', 'exit', 'last_red'}"""
    if not plan and running()['builds']: raise Refused('a build is already running')
    repo, args = build_command(game_dir, plan=plan, rebuild=rebuild, **kw)
    eng = engine(repo)
    backup = None
    if rebuild and not plan and Path(rebuild).exists(): backup = back_up(rebuild, eng)
    p = subprocess.Popen(args, cwd=tree_of(repo), env=dict(tool_env(repo), PYTHONUNBUFFERED='1'), stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    app = red = None
    for line in p.stdout or ():
        line = line.rstrip('\n')
        try: ev = json.loads(line)
        except ValueError: ev = {'ev': 'log', 'msg': line}
        if not isinstance(ev, dict): ev = {'ev': 'log', 'msg': line}
        msg = ev.get('msg', '')
        if '[RED]' in msg: red = msg
        if ev.get('ev') == 'say' and (m := re.search(r'done: (.+?\.app)', msg)): app = m[1]
        if events: events(ev)
    code = p.wait()
    ok = code == 0
    if ok and app and not plan: record(app, str(Path(game_dir).expanduser().resolve()), eng)
    if not ok and backup and rebuild and not Path(rebuild).exists(): backup.rename(rebuild)   # keep a working game
    return {'ok': ok, 'exit': code, 'app': app, 'last_red': red, 'backup': str(backup) if backup and backup.exists() else None}


def start_job(game_dir, **kw):
    """Starts `nxforge.py build … --json-events` detached; returns the job"""
    build_command(game_dir, **{k: v for k, v in kw.items() if k in ('plan', 'rebuild', 'out', 'keys', 'cleanup', 'sign')})   # fail now, not in the background
    if not kw.get('plan') and running()['builds']: raise Refused('a build is already running')
    jid = f'{datetime.datetime.now():%Y%m%d-%H%M%S}-{Path(game_dir).name[:24].replace(" ", "_")}'
    log = jobs_dir() / f'{jid}.jsonl'
    cmd = [sys.executable, str(Path(__file__).resolve()), 'build', str(game_dir), '--events']
    for k in ('rebuild', 'out', 'keys', 'cleanup', 'sign'):
        if kw.get(k): cmd += [f'--{k}', str(kw[k])]
    if kw.get('plan'): cmd.append('--plan')
    with open(log, 'w') as f:
        p = subprocess.Popen(cmd, stdout=f, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL, start_new_session=True)
    job = {'id': jid, 'pid': p.pid, 'game_dir': str(game_dir), 'plan': bool(kw.get('plan')), 'started': time.time(), 'log': str(log), 'command': cmd}
    (jobs_dir() / f'{jid}.json').write_text(json.dumps(job, indent=2))
    return job


def alive(pid):
    try: os.kill(pid, 0); return True
    except ProcessLookupError: return False
    except PermissionError: return True


def job_state(jid, tail=20):
    j = load_json(jobs_dir() / f'{jid}.json', None)
    if not j: raise Refused(f'no job {jid}')
    stage, last, result, lines = None, None, None, []
    try:
        for line in Path(j['log']).read_text(errors='replace').splitlines():
            try: ev = json.loads(line)
            except ValueError: ev = {'ev': 'log', 'msg': line}
            if not isinstance(ev, dict): continue
            if ev.get('ev') == 'stage': stage = ev
            if ev.get('ev') in ('progress', 'step'): last = ev
            if ev.get('ev') == 'result': result = ev
            if ev.get('msg'): lines.append(ev['msg'])
    except OSError: pass
    j.update({'running': alive(j['pid']) and result is None, 'stage': stage, 'progress': last, 'result': result, 'tail': lines[-tail:]})
    return j


def list_jobs():
    return [job_state(p.stem, tail=3) for p in sorted(jobs_dir().glob('*.json'), reverse=True)[:20]]


def stop_job(jid):
    j = job_state(jid, 0)
    if not j['running']: return {'id': jid, 'stopped': False, 'why': 'not running'}
    os.killpg(os.getpgid(j['pid']), signal.SIGINT)   # the script stops at its next step and exits 130, as with the app's Stop
    return {'id': jid, 'stopped': True}


# ---------- engine updates ----------

def update_target(repo):
    up = git(repo, 'rev-parse', '--abbrev-ref', '@{upstream}')
    main = git(repo, 'rev-parse', '--abbrev-ref', 'origin/HEAD') or 'origin/main'
    if not git(repo, 'rev-parse', '--verify', '--quiet', main): return up
    if up and (up == main or git(repo, 'merge-base', '--is-ancestor', up, main) is None): return up
    return main if git(repo, 'merge-base', '--is-ancestor', 'HEAD', main) is not None else up


def update(apply=False):
    repo = find_repo()
    if not repo: raise Refused('no engine checkout')
    if git(repo, 'fetch', '--quiet', 'origin', timeout=300) is None: raise Refused('git fetch failed')
    tgt = update_target(repo)
    if not tgt: raise Refused('the engine branch has no upstream and is not merged into main')
    n = int(git(repo, 'rev-list', '--count', f'HEAD..{tgt}') or 0)
    subjects = (git(repo, 'log', '--format=%h %s', f'HEAD..{tgt}') or '').splitlines()[:30]
    res = {'repo': repo, 'target': tgt, 'behind': n, 'commits': subjects, 'applied': False, 'engine': engine(repo)}
    if apply and n:
        if running()['builds']: raise Refused('a build is running from the engine')
        if (engine(repo) or {}).get('dirty'): raise Refused('the engine has uncommitted changes')
        branch = git(repo, 'symbolic-ref', '--short', 'HEAD')
        name = tgt.split('/', 1)[1]
        if git(repo, 'rev-parse', '--abbrev-ref', '@{upstream}') != tgt and branch != name:
            exists = git(repo, 'rev-parse', '--verify', '--quiet', f'refs/heads/{name}') is not None
            if git(repo, *(['switch', '--quiet', name] if exists else ['switch', '--quiet', '--track', tgt])) is None: raise Refused(f'cannot switch to {name}')
        if git(repo, 'merge', '--ff-only', '--quiet', tgt, timeout=300) is None: raise Refused(f'{tgt} cannot be fast-forwarded to (local commits?)')
        ensure_tree(repo)
        res.update(applied=True, engine=engine(repo))
    return res


# ---------- status, builds, doctor ----------

def builds_list():
    out = []
    for r in records():
        app = Path(r.get('app', '')).expanduser()
        bdir = app.parent / 'app-backups'
        bks = sorted(str(p) for p in bdir.glob(f'{app.stem} (*).app')) if bdir.is_dir() else []
        out.append({'app': str(app), 'exists': app.exists(), 'game_dir': r.get('game_dir'), 'built_at': r.get('built_at'), 'engine': release_name((r.get('engine') or {}).get('version'))
                    or (r.get('engine') or {}).get('commit', '')[:7], 'kept': bool(r.get('kept')), 'backups': bks})
    return out


def status():
    s = settings()
    repo = find_repo(s)
    return {'support_dir': str(support_dir()), 'engine': engine(repo), 'running': running(), 'free_bytes': free_bytes(), 'free_gb': gb(free_bytes()),
            'builds': builds_list(), 'jobs': [j for j in list_jobs() if j['running']], 'game_dirs': [str(d) for d in game_dirs(s)]}


def game_needs(game_dir, repo):
    """{optional tool: why this game needs it}, as the converter decides it (app GameNeeds.swift): nsz for .nsz / .xcz files, zbic for code built with system 22 or later
    (every Switch 2 game, and a Switch game whose profile names SDK 22 or later), glslang for an OpenGL game"""
    d, out = Path(game_dir).expanduser(), {}
    try: names = sorted(n.name for n in d.iterdir())
    except OSError: return out
    if any(n.lower().endswith(('.nsz', '.xcz')) for n in names): out['nsz'] = 'this folder has compressed .nsz or .xcz files'
    tid = next((n[:16].upper() for n in names if n.endswith('_build') and len(n) == 22), None)
    if not tid and (m := next((m for n in names if (m := re.search(r'\[([0-9A-Fa-f]{16})\]', n))), None)): tid = m.group(1)[:13].upper() + '000'
    prof = Path(tree_of(repo)) / 'dm/games' / tid if repo and tid else None
    try: tsv = (prof / 'game.tsv').read_text(errors='replace') if prof else ''
    except OSError: tsv = ''
    if tid and tid.startswith('04'): out['zbic'] = 'Switch 2 games are built with system 22 or later, whose code is ZBIC-compressed'
    elif (m := re.search(r'SDK (\d+)\.', tsv)) and int(m.group(1)) >= 22: out['zbic'] = f'its profile says SDK {m.group(1)}: code built with system 22 or later is ZBIC-compressed'
    if prof and ((prof / 'gl_capture.tsv').is_file() or 'OpenGL' in tsv): out['glslang'] = 'it is an OpenGL game: glslang compiles its GLSL shaders'
    return out


def optional_tools(py, env):
    """{name: (there, detail, the command that installs it)} for the tools only some games need: glslang, and nsz / zbic in the build's Python"""
    def has(mod):
        try: return bool(py) and subprocess.run([py, '-I', '-c', f'import {mod}'], capture_output=True, timeout=30, env=env).returncode == 0
        except (OSError, subprocess.TimeoutExpired): return False
    gl = shutil.which('glslangValidator', path=env['PATH'])
    nsz, zbic = has('nsz'), has('zbic')
    return {'glslang': (bool(gl), gl or 'not found', 'brew install glslang'),
            'nsz': (nsz, 'installed' if nsz else 'not installed in that Python', f'{py} -m pip install nsz'),
            'zbic': (zbic, 'installed' if zbic else 'not installed in that Python', f'{py} -m pip install zbic==1.0.1.post1')}


def doctor(game_dir=None):
    """The tools a build needs, then the optional ones (glslang, nsz, zbic) the converter's Toolchain page lists: optional unless game_dir is a game that needs one"""
    s = settings()
    repo = find_repo(s)
    env = tool_env(repo)
    py, miss = find_python(s, repo)
    checks = [('engine', bool(repo), repo or 'not found'), ('python', bool(py) and not miss, f'{py} lacks {", ".join(miss)}' if miss else py)]
    for t in ('git', 'dotnet', 'xcrun', 'zstd'):
        w = shutil.which(t, path=env['PATH'])
        checks.append((t, bool(w), w or 'not found'))
    out = [{'name': n, 'ok': ok, 'detail': d} for n, ok, d in checks]
    needs = game_needs(game_dir, repo) if game_dir else {}
    for name, (ok, detail, fix) in optional_tools(py, env).items():
        out.append({'name': name, 'ok': ok, 'detail': detail, 'optional': name not in needs, **({'needed': needs[name]} if name in needs else {}), **({} if ok else {'fix': fix})})
    return out


# ---------- command line ----------

def human(cmd, res):
    if cmd == 'status':
        e = res['engine'] or {}
        print(f'engine   {e.get("version", "?")}{"+changes" if e.get("dirty") else ""} ({e.get("branch", "?")}) {e.get("subject", "")}  [{e.get("repo", "not found")}]')
        print(f'free     {res["free_gb"]} GB')
        for k in ('builds', 'games'):
            for p in shown(res['running'][k]): print(f'running  {k[:-1]} pid {p["pid"]} for {p["seconds"] // 60} min: {p["brief"][:120]}')
        for b in res['builds']:
            if b['exists']: print(f'build    {b["built_at"]}  {b["engine"]:<10} {b["app"]}')
        if gone := sum(not b['exists'] for b in res['builds']): print(f'build    {gone} more recorded whose app is gone (`nxforge builds` lists them)')
    elif cmd == 'builds':
        for b in res: print(f'{b["built_at"]}  {b["engine"]:<10} {"kept " if b["kept"] else ""}{"" if b["exists"] else "(missing) "}{b["app"]}  backups: {len(b["backups"])}')
    elif cmd in ('disk', 'clean'):
        if cmd == 'disk':
            for g in res['overview']['games']:
                print(f'{gb(g["bytes"]):>8} GB  {g["folder"]}')
                for e in g['entries']: print(f'{gb(e["bytes"]):>8} GB    {Path(e["path"]).name}')
            for b in res['overview']['build_folders']:
                print(f'{gb(b["bytes"]):>8} GB  {b["path"]}')
                for n, v in b['entries'].items(): print(f'{gb(v):>8} GB    {n}')
            for c in res['overview']['caches'] + res['overview']['checkouts']: print(f'{gb(c["bytes"]):>8} GB  {c["path"]}')
            print()
        verb = 'would free' if res.get('dry_run', True) else 'freed'
        for c, r in res['categories'].items():
            print(f'{c}: {verb} {gb(r.get("bytes", 0))} GB{" (safe)" if CATEGORIES[c][1] else ""}')
            for i in r['items']: print(f'  {gb(i["bytes"]):>8} GB  {i["path"]}  ({i["why"]}){"" if i.get("deleted", True) else "  NOT DELETED"}')
            for n in r['notes']: print(f'  - {n}')
        print(f'total: {verb} {gb(res["bytes"])} GB' + (f' (the volume got {gb(res["freed_bytes"])} GB back)' if 'freed_bytes' in res else '') + f'; free now {gb(res.get("free_after", free_bytes()))} GB')
        for e in res.get('errors', []): print(f'[RED] {e}')
    elif cmd == 'update':
        print(f'{res["repo"]}: {res["behind"]} commits on {res["target"]}{" (applied)" if res["applied"] else ""}')
        for c in res['commits']: print(f'  {c}')
    elif cmd == 'doctor':
        for c in res:
            mark = 'ok ' if c['ok'] else '-- ' if c.get('optional') else 'NO '
            print(f'{mark} {c["name"]:<8} {c["detail"]}' + (f'  (needed: {c["needed"]})' if c.get('needed') else '  (optional)' if c.get('optional') and not c['ok'] else '') + (f'\n             fix: {c["fix"]}' if c.get('fix') and not c.get('optional') else ''))
    else:
        print(json.dumps(res, indent=2, default=str))


def main(argv=None):
    ap = argparse.ArgumentParser(description='NXForge automation: status, builds, disk cleanup and engine updates (docs/automation.md)')
    ap.add_argument('--json', action='store_true', help='print one JSON document')
    sub = ap.add_subparsers(dest='cmd', required=True)
    sub.add_parser('status', help='engine, running builds and games, free space, recorded builds')
    sub.add_parser('builds', help='recorded builds and their backups')
    sub.add_parser('doctor', help='check the tools a build needs').add_argument('game_dir', nargs='?', help="a game folder: the optional tools it needs (glslang, nsz, zbic) count as required")
    for name in ('disk', 'clean'):
        p = sub.add_parser(name, help='report disk use by category' if name == 'disk' else 'delete what cleanup categories hold')
        p.add_argument('--safe', action='store_true', help=f'the safe set: {", ".join(SAFE)}' + (' (the default)' if name == 'disk' else ''))
        p.add_argument('--only', help=f'comma-separated categories: {", ".join(CATEGORIES)}')
        p.add_argument('--backup-days', type=float, default=3, help='app-backups: delete only backups older than this (default 3)')
        p.add_argument('--backup-keep', type=int, default=1, help='app-backups: newest backups kept per game (default 1)')
        p.add_argument('--log-days', type=float, default=30, help='old-logs: age in days (default 30)')
        p.add_argument('--game', help='only this game: its folder, its <id>_build folder or its title ID (build-* and app-backups categories)')
        p.add_argument('--idle-hours', type=float, default=24, help='build-unused, build-cache: only build folders unchanged for this many hours (default 24)')
        p.add_argument('--metal-cache-gb', type=float, help=f'metal-cache: trim to this size (default {MTLCACHE_GB:g}, DMSH_MTLCACHE_GB)')
        if name == 'clean':
            p.add_argument('--dry-run', action='store_true', help='list what would go, delete nothing')
            p.add_argument('--worktree', help='remove this engine worktree (only when clean, pushed and not the engine)')
        else: p.add_argument('--all', action='store_true', help='every category, not only the safe ones')
    p = sub.add_parser('build', help="build or rebuild a game's Mac app")
    p.add_argument('game_dir')
    p.add_argument('--plan', action='store_true', help='dry run: list the stages that will be reused or redone')
    p.add_argument('--rebuild', help='the existing app to replace (moved to app-backups/ first)')
    p.add_argument('--out', help='where the app goes (default: the settings, else beside the game files)')
    p.add_argument('--keys', help='prod.keys (default: the one saved in NXForge Settings, else the game folder\'s)')
    p.add_argument('--cleanup', choices=('off', 'unused', 'all'), help='after the build (default: the settings)')
    p.add_argument('--sign', help='codesign identity (default: the settings, else ad-hoc)')
    p.add_argument('--background', action='store_true', help='start it detached and print the job')
    p.add_argument('--events', action='store_true', help=argparse.SUPPRESS)   # one JSON event per line, then a result event (background jobs)
    sub.add_parser('jobs', help='background builds started here')
    sub.add_parser('job', help='one background build: stage, progress, last lines').add_argument('id')
    sub.add_parser('stop', help='stop a background build').add_argument('id')
    sub.add_parser('update', help='engine updates').add_argument('--apply', action='store_true', help='fast-forward the engine')
    a = ap.parse_args(argv)

    try:
        if a.cmd == 'status': res = status()
        elif a.cmd == 'builds': res = builds_list()
        elif a.cmd == 'doctor': res = doctor(a.game_dir)
        elif a.cmd in ('disk', 'clean'):
            if a.only:
                cats = [c.strip() for c in a.only.split(',') if c.strip()]
                if bad := [c for c in cats if c not in CATEGORIES]: ap.error(f'unknown category: {", ".join(bad)}')
            elif a.cmd == 'disk' and a.all: cats = list(CATEGORIES)
            elif a.safe or a.cmd == 'disk': cats = SAFE
            elif a.worktree: cats = []
            else: ap.error('clean needs --safe, --only <categories> or --worktree <path>')
            ctx = context(game=a.game, idle_hours=a.idle_hours, backup_days=a.backup_days, backup_keep=a.backup_keep, log_days=a.log_days, mtlcache_gb=a.metal_cache_gb)
            if a.cmd == 'disk':
                res = {'dry_run': True, 'categories': find(ctx, cats), 'overview': overview(ctx)}
                res['bytes'] = sum(r.get('bytes', 0) for r in res['categories'].values()); res['free_after'] = free_bytes()
                for r in res['categories'].values(): [(i.pop('files', None), i.pop('dirs', None)) for i in r['items']]
            else: res = clean(cats, a.dry_run, ctx, a.worktree)
        elif a.cmd == 'build':
            kw = {k: getattr(a, k) for k in ('plan', 'rebuild', 'out', 'keys', 'cleanup', 'sign')}
            for k in ('rebuild', 'out', 'keys'):   # the build runs in the engine's tree/: a relative path means the caller's folder
                if kw[k]: kw[k] = str(Path(kw[k]).expanduser().absolute())
            if a.background: res = start_job(a.game_dir, **kw)
            else:
                show = (lambda ev: print(json.dumps(ev), flush=True)) if a.events else (lambda ev: ev.get('msg') and print(ev['msg'], flush=True)) if not a.json else None
                res = run_build(a.game_dir, events=show, **kw)
                if a.events: print(json.dumps({'ev': 'result', **res}), flush=True); return 0 if res['ok'] else 1
        elif a.cmd == 'jobs': res = list_jobs()
        elif a.cmd == 'job': res = job_state(a.id)
        elif a.cmd == 'stop': res = stop_job(a.id)
        elif a.cmd == 'update': res = update(a.apply)
        else: ap.error(a.cmd)
    except Refused as e:
        if a.json: print(json.dumps({'error': str(e), 'refused': True}))
        else: print(f'[RED] {e}', file=sys.stderr)
        return 2
    except OSError as e:
        if a.json: print(json.dumps({'error': str(e)}))
        else: print(f'[RED] {e}', file=sys.stderr)
        return 1
    if a.json: print(json.dumps(res, indent=2, default=str))
    else: human(a.cmd, res)
    if a.cmd == 'clean' and isinstance(res, dict) and res.get('errors'): return 1
    if a.cmd == 'build' and isinstance(res, dict) and not res.get('ok', True): return 1
    if a.cmd == 'doctor' and isinstance(res, list) and any(isinstance(c, dict) and not c['ok'] and not c.get('optional') for c in res): return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
