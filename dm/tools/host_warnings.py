#!/usr/bin/env python3
# Mac host compiler warnings with a ratchet, like lint_python.py for Python. CI's build check builds the Mac host for three profiles and passes
# the compiler output here. Each warning is keyed by file, flag and message (no line or column numbers: they survive edits elsewhere in the
# file) and counted once however many profiles or translation units repeat it. dm/tools/host_warnings_baseline.tsv lists the warnings the
# code is allowed to have; the check fails on a warning not listed (a new one) and on a listed one the build no longer gives (fixed: run
# --update). So the list only shrinks:
#   host_warnings.py <log>...            check the logs against the baseline (exit 1 on a new or a fixed-but-listed warning)
#   host_warnings.py --report <log>...   print every warning, sorted, with no check (for reading a build)
#   host_warnings.py --update <log>...   drop the fixed entries from the baseline; it never adds one (a new warning is fixed at its cause)
# Under GitHub Actions, new warnings are annotated on their lines and a summary goes to $GITHUB_STEP_SUMMARY.
import argparse, os, pathlib, re, sys

REPO = pathlib.Path(__file__).resolve().parents[2]
BASELINE = REPO / 'dm/tools/host_warnings_baseline.tsv'
HEADER = '# file\tflag\tmessage   (dm/tools/host_warnings.py; shrink with --update, never add by hand)\n'
# clang: /abs/or/rel/path/file.m:123:45: warning: message [-Wflag]   (also "[-Wflag,-Wgroup]")
WARN = re.compile(r'^(?P<file>[^\s:][^:]*\.(?:c|cc|cpp|h|hpp|m|mm|swift)):(?P<line>\d+):(?:\d+:)? warning: (?P<msg>.*?)(?: \[(?P<flag>-W[^\]]+)\])?\s*$')


def rel(path):
    p = pathlib.Path(path)
    if p.is_absolute():
        try: return p.resolve().relative_to(REPO).as_posix()
        except ValueError: pass
    s = p.as_posix()
    i = s.find('dm/')   # make -C dm/host prints paths relative to that folder, CI's checkout is absolute
    return s[i:] if i >= 0 else ('dm/host/' + s if not s.startswith('/') else s)


def parse(text):
    """{(file, flag, message): first line number} for the warnings in compiler output; our own sources only (not the SDK, not third_party)."""
    found = {}
    for raw in text.splitlines():
        m = WARN.match(raw.strip())
        if not m: continue
        f = rel(m['file'])
        if not f.startswith('dm/') or '/third_party/' in f or '/gen/' in f: continue
        key = (f, (m['flag'] or '-W').split(',')[0], re.sub(r'\s+', ' ', m['msg']).strip())
        found.setdefault(key, int(m['line']))
    return found


def load():
    if not BASELINE.is_file(): return set()
    return {tuple(ln.split('\t', 2)) for ln in BASELINE.read_text().splitlines() if ln and not ln.startswith('#')}


def write(keys):
    BASELINE.write_text(HEADER + ''.join(f'{k[0]}\t{k[1]}\t{k[2]}\n' for k in sorted(keys)))


def main(argv=None):
    ap = argparse.ArgumentParser(description='Mac host compiler warnings with a ratchet (see the comment at the top).')
    ap.add_argument('logs', nargs='+', type=pathlib.Path)
    g = ap.add_mutually_exclusive_group()
    g.add_argument('--report', action='store_true')
    g.add_argument('--update', action='store_true')
    a = ap.parse_args(argv)
    found = {}
    for log in a.logs:
        for k, v in parse(log.read_text(errors='replace')).items(): found.setdefault(k, v)
    if a.report:
        for (f, flag, msg), line in sorted(found.items()): print(f'{f}:{line}: {msg} [{flag}]')
        print(f'host_warnings: {len(found)} distinct warning(s)')
        return 0
    base = load()
    new = sorted(k for k in found if k not in base)
    fixed = sorted(base - set(found))
    if a.update:
        write(base & set(found))
        print(f'host_warnings: baseline {len(base)} → {len(base & set(found))}; {len(new)} new warning(s) not added')
        return 0
    gha = os.environ.get('GITHUB_ACTIONS') == 'true'
    for k in new:
        print(f'new: {k[0]}:{found[k]}: {k[2]} [{k[1]}]')
        if gha: print(f'::error file={k[0]},line={found[k]}::{k[2]} [{k[1]}]')
    for k in fixed: print(f'fixed, still in the baseline: {k[0]}: {k[2]} [{k[1]}]')
    print(f'host_warnings: {len(found)} warning(s), {len(base)} in the baseline, {len(new)} new, {len(fixed)} fixed but still listed')
    if fixed: print('host_warnings: run python3 dm/tools/host_warnings.py --update <logs> to shrink the baseline')
    if gha and os.environ.get('GITHUB_STEP_SUMMARY'):
        with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as s:
            s.write(f'### Mac host warnings\n\n{len(found)} warning(s), {len(base)} in the baseline, {len(new)} new, {len(fixed)} fixed but still listed\n')
    return 1 if new or fixed else 0


if __name__ == '__main__':
    sys.exit(main())
