#!/usr/bin/env python3
"""NXForge as a layer on an untouched nxnative engine (UPSTREAM.md, "Engine and layer").

The engine is seedds/nxnative exactly as published, pinned to one commit in layer/ENGINE. Everything NXForge adds sits beside it:
  layer/patches/NNNN-<name>.patch   changes to nxnative's own files, one patch per purpose, applied in order with `git am -3`
  layer/files/<path>                files NXForge adds to the engine tree (the sidebar, capture, NXForge game profiles and tools)
`assemble` makes tree/ (git-ignored): a git worktree of this repository at the pinned commit, with each patch as one commit and
the layer files as one last commit ("NXForge layer files"). Builds, the converter and the nxforge CLI run in tree/.

  layer.py assemble [--force]   make tree/ match the layer; a no-op while it already does. --force throws away edits in tree/
  layer.py status               the pin, how far nxnative's main is ahead of it, and whether tree/ is current
  layer.py update [REF]         move the pin to REF (default: nxnative's main, fetched) and assemble. A patch nxnative now has
                                is dropped; a patch that no longer applies stops in tree/ (git am) for you to fix, then
                                `layer.py continue` (or `continue --skip` to drop it) and `layer.py export`
  layer.py continue [--skip]    after fixing a stopped patch (files `git -C tree add`ed): finish it and apply the patches after it
  layer.py export               write tree/'s commits back to the layer: patch commits to layer/patches (an edited or new commit
                                after the pin), changed layer files to layer/files
  layer.py local [REF]          try nxnative's newest main (or REF) on this Mac before NXForge releases it: when every patch
                                still applies, tree/ is assembled on it (layer/ stays as it is; the choice is kept in .git);
                                when one does not, nothing changes and the clashing patches are named
  layer.py local --off          back to the pinned engine. A new pin (an NXForge release) ends it by itself
  layer.py try [REF]            dry run of update: which patches apply to REF (default: nxnative's main), which nxnative already
                                has, which conflict and in what files. Changes nothing (a temporary worktree)
  layer.py path                 print tree/'s path

To change a patch: edit in tree/, commit (`git -C tree commit --fixup <patch commit>` then `git -C tree rebase -i --autosquash
<pin>`, or a new commit for a new patch), then `layer.py export`. Layer files can be edited in either place; export copies
tree/'s version back.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LAYER = ROOT / 'layer'
ENGINE = LAYER / 'ENGINE'
PATCHES = LAYER / 'patches'
FILES = LAYER / 'files'
TREE = ROOT / 'tree'
FILES_SUBJECT = 'NXForge layer files'
MAIN_REF = 'refs/nxnative/main'
IDENT = {'GIT_AUTHOR_NAME': 'NXForge layer', 'GIT_AUTHOR_EMAIL': 'layer@nxforge.invalid',
         'GIT_COMMITTER_NAME': 'NXForge layer', 'GIT_COMMITTER_EMAIL': 'layer@nxforge.invalid',
         'GIT_AUTHOR_DATE': '2026-01-01T00:00:00Z', 'GIT_COMMITTER_DATE': '2026-01-01T00:00:00Z'}


class LayerError(Exception):
    pass


def git(*args: str, cwd: Path = ROOT, check: bool = True, env: dict | None = None, quiet: bool = False) -> subprocess.CompletedProcess:
    p = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True, env={**os.environ, **(env or {})})
    if check and p.returncode:
        raise LayerError(f'git {" ".join(args)} failed in {cwd}:\n{(p.stderr or p.stdout).strip()}')
    return p


def read_engine(path: Path = ENGINE) -> tuple[str, str]:
    """(url, commit) from layer/ENGINE: "url <url>" and "commit <40 hex>" lines; # comments."""
    url = commit = ''
    for line in path.read_text(encoding='utf-8').splitlines():
        line = line.split('#', 1)[0].strip()
        if line.startswith('url '):
            url = line[4:].strip()
        elif line.startswith('commit '):
            commit = line[7:].strip()
    if not url or not re.fullmatch(r'[0-9a-f]{40}', commit):
        raise LayerError(f'{path}: needs "url <url>" and "commit <40 hex digits>" lines')
    return url, commit


def write_engine(url: str, commit: str, path: Path = ENGINE) -> None:
    path.write_text('# The nxnative commit NXForge is built on (scripts/layer.py; UPSTREAM.md, "Engine and layer").\n'
                    f'url {url}\ncommit {commit}\n', encoding='utf-8')


def local_file() -> Path:
    """Where `layer.py local` keeps its nxnative commit: in the checkout's git folder, so it is never committed."""
    return ROOT / git('rev-parse', '--git-path', 'nxforge-local-engine').stdout.strip()


def local_commit() -> str | None:
    """The local engine commit, while the pin is still the one it was taken on (an engine update to a new release ends it:
    the release brings upstream itself) and does not include it; else the file is dropped. The file: "<commit> <pin>"."""
    f = local_file()
    if not f.is_file():
        return None
    parts = f.read_text().split()
    c, on = (parts + ['', ''])[:2]
    _, pin = read_engine()
    if not re.fullmatch(r'[0-9a-f]{40}', c) or on != pin or c == pin or (
            git('cat-file', '-e', f'{c}^{{commit}}', check=False).returncode == 0
            and git('merge-base', '--is-ancestor', c, pin, check=False).returncode == 0):
        f.unlink(missing_ok=True)
        return None
    return c


def engine() -> tuple[str, str]:
    """(url, commit) tree/ is built on: the local commit when one is set, else the pin."""
    url, pin = read_engine()
    return url, local_commit() or pin


def patch_files() -> list[Path]:
    return sorted(PATCHES.glob('*.patch'))


def layer_files() -> list[str]:
    """Layer files as tree paths ("dm/host/quick_settings_mac.swift"), sorted."""
    return sorted(str(p.relative_to(FILES)) for p in FILES.rglob('*') if p.is_file() or p.is_symlink())


def stamp() -> str:
    h = hashlib.sha256(ENGINE.read_bytes())
    local = local_commit()
    if local:
        h.update(b'L' + local.encode())
    for p in patch_files():
        h.update(b'P' + p.name.encode() + b'\0' + p.read_bytes())
    for rel in layer_files():
        f = FILES / rel
        h.update(b'F' + rel.encode() + b'\0' + (b'x' if os.access(f, os.X_OK) else b'-') + f.read_bytes())
    return h.hexdigest()


def gitdir() -> Path:
    d = tree_gitdir()
    if d is None:
        raise LayerError('tree/ is not assembled')
    return d


def tree_gitdir() -> Path | None:
    if not (TREE / '.git').exists():
        return None
    return Path(git('rev-parse', '--absolute-git-dir', cwd=TREE).stdout.strip())


def recorded() -> tuple[str, str] | None:
    """(stamp, head) written by the last assemble, if tree/ has one."""
    d = tree_gitdir()
    f = d / 'nxforge-layer' if d else None
    if not f or not f.is_file():
        return None
    parts = f.read_text().split()
    return (parts[0], parts[1]) if len(parts) == 2 else None


def tree_head() -> str:
    return git('rev-parse', 'HEAD', cwd=TREE).stdout.strip()


def ensure_commit(url: str, commit: str) -> None:
    if git('cat-file', '-e', f'{commit}^{{commit}}', check=False).returncode == 0:
        return
    if git('rev-parse', '--is-shallow-repository').stdout.strip() == 'true':   # a CI checkout: just that commit
        git('fetch', '--quiet', '--depth=1', url, commit)
        return
    git('fetch', '--quiet', url, f'+refs/heads/main:{MAIN_REF}', check=False)
    if git('cat-file', '-e', f'{commit}^{{commit}}', check=False).returncode:
        git('fetch', '--quiet', url, commit)


def is_current() -> bool:
    r = recorded()
    return bool(r) and r[0] == stamp() and tree_head() == r[1] and not dirty()


def dirty() -> bool:
    return bool(git('status', '--porcelain', '--untracked-files=no', cwd=TREE).stdout.strip())


def in_am() -> bool:
    d = tree_gitdir()
    return bool(d and (d / 'rebase-apply').exists())


def unexported() -> list[str]:
    """Commits in tree/ after the last assemble's head (work not yet exported)."""
    r = recorded()
    if not r or git('cat-file', '-e', f'{r[1]}^{{commit}}', cwd=TREE, check=False).returncode:
        return []
    return git('rev-list', f'{r[1]}..HEAD', cwd=TREE).stdout.split()


def assemble(force: bool = False, log=print) -> bool:
    """Make tree/ match the layer. True when it changed. Raises LayerError when a patch does not apply (tree/ is left in git am)."""
    url, commit = engine()
    if TREE.exists() and (TREE / '.git').exists():
        if in_am():
            raise LayerError('tree/ is in the middle of applying patches (git am): finish with `layer.py continue` (or '
                             '`continue --skip`), then `layer.py export`; or `layer.py assemble --force` to start again')
        if not force and is_current():
            return False
        if not force and dirty():
            raise LayerError('tree/ has uncommitted changes: commit them and run `layer.py export`, or `layer.py assemble --force` to throw them away')
        if not force and unexported():
            raise LayerError(f'tree/ has {len(unexported())} commit(s) not exported to layer/: run `layer.py export`, or `layer.py assemble --force` to throw them away')
    ensure_commit(url, commit)
    if not (TREE / '.git').exists():
        git('worktree', 'prune')
        if TREE.exists() and any(TREE.iterdir()):
            raise LayerError(f'{TREE} exists and is not a worktree: move it away first')
        log(f'tree/: new worktree at nxnative {commit[:10]}')
        git('worktree', 'add', '--quiet', '--detach', str(TREE), commit)
    else:
        if in_am():
            git('am', '--abort', cwd=TREE, check=False)
        log(f'tree/: nxnative {commit[:10]}')
        git('checkout', '--quiet', '--detach', '--force', commit, cwd=TREE)
    _apply(patch_files(), commit, log)
    return True


def rest_file() -> Path:
    return gitdir() / 'nxforge-layer-rest'


def _apply(patches: list[Path], commit: str, log=print) -> None:
    """Apply patches in order, then the layer files. On a conflict, records the patches after the stopped one (for `continue`)."""
    rest_file().unlink(missing_ok=True)
    for i, p in enumerate(patches):
        r = git('am', '-3', '--quiet', '--keep-cr', str(p), cwd=TREE, check=False, env=IDENT)
        if r.returncode:
            out = (r.stdout + r.stderr)
            if 'No changes' in out or 'already applied' in out or 'Patch is empty' in out:
                git('am', '--skip', cwd=TREE, env=IDENT)
                log(f'  {p.name}: nxnative already has it; it can be dropped (delete the file, or `layer.py export`)')
                continue
            conflicts = git('diff', '--name-only', '--diff-filter=U', cwd=TREE, check=False).stdout.split()
            rest_file().write_text(''.join(f'{q.name}\n' for q in patches[i + 1:]))
            raise LayerError(f'{p.name} does not apply to nxnative {commit[:10]}'
                             + (f' (conflicts in {", ".join(conflicts)})' if conflicts else '') +
                             '.\nFix it in tree/, `git -C tree add` the files and `scripts/layer.py continue` (or `continue --skip` '
                             'to drop the patch), then `scripts/layer.py export`.')
        log(f'  {p.name}')
    files = layer_files()
    for rel in files:
        dst = TREE / rel
        dst.parent.mkdir(parents=True, exist_ok=True)
        if dst.is_symlink() or dst.exists():
            dst.unlink()
        shutil.copy2(FILES / rel, dst, follow_symlinks=False)
    if files:
        for i in range(0, len(files), 200):
            git('add', '--force', '--', *files[i:i + 200], cwd=TREE)
        git('commit', '--quiet', '--allow-empty', '-m', FILES_SUBJECT, cwd=TREE, env=IDENT)
        log(f'  {len(files)} layer files')
    (gitdir() / 'nxforge-layer').write_text(f'{stamp()} {tree_head()}\n')


def continue_(skip: bool = False, log=print) -> None:
    """Finish the stopped patch (or drop it), then apply the patches after it and the layer files."""
    rest = rest_file()
    if in_am():
        r = git('am', '--skip' if skip else '--continue', cwd=TREE, check=False, env=IDENT)
        if r.returncode:
            raise LayerError('git am could not go on: ' + (r.stdout + r.stderr).strip())
    elif not rest.exists():
        raise LayerError('nothing to continue: tree/ is not stopped on a patch')
    names = rest.read_text().split() if rest.exists() else []
    _, commit = engine()
    _apply([PATCHES / n for n in names], commit, log)
    log('tree/: all patches applied; now `layer.py export`')


def slug(subject: str) -> str:
    m = re.match(r'([a-z0-9][a-z0-9-]*):', subject)
    return m[1] if m else re.sub(r'[^a-z0-9]+', '-', subject.lower()).strip('-')[:40]


def export(log=print) -> None:
    if local_commit():
        raise LayerError('tree/ is on a local nxnative commit (`layer.py local`): `layer.py local --off` first, or move the pin '
                         'with `layer.py update`')
    if in_am():
        raise LayerError('tree/ is still applying patches: finish with `layer.py continue` first')
    if rest_file().exists():
        raise LayerError('patches after the stopped one are not applied yet: run `layer.py continue` first '
                         '(exporting now would drop them)')
    if dirty():
        raise LayerError('tree/ has uncommitted changes: commit them first')
    _, commit = read_engine()
    overlay = set(layer_files())
    excludes = [f':(exclude){p}' for p in sorted(overlay)]
    new: list[tuple[str, str]] = []
    for c in git('rev-list', '--reverse', '--no-merges', f'{commit}..HEAD', cwd=TREE).stdout.split():
        subject = git('log', '-1', '--format=%s', c, cwd=TREE).stdout.strip()
        if subject == FILES_SUBJECT:
            continue
        text = git('format-patch', '-1', '--stdout', '--zero-commit', '--full-index', '--no-signature', '--keep-subject',
                   c, '--', '.', *excludes, cwd=TREE).stdout
        if '\ndiff --git ' not in text:
            continue
        new.append((slug(subject), text))
    for p in patch_files():
        p.unlink()
    for i, (name, text) in enumerate(new, 1):
        (PATCHES / f'{i:04d}-{name}.patch').write_text(text, encoding='utf-8')
    log(f'layer/patches: {len(new)} patch(es)')
    changed = 0
    for rel in sorted(overlay):
        src = TREE / rel
        if not src.exists():
            continue
        if src.read_bytes() != (FILES / rel).read_bytes() or os.access(src, os.X_OK) != os.access(FILES / rel, os.X_OK):
            shutil.copy2(src, FILES / rel)
            changed += 1
    log(f'layer/files: {changed} file(s) updated from tree/')
    (gitdir() / 'nxforge-layer').unlink(missing_ok=True)
    assemble(force=True, log=lambda *_: None)


def update(ref: str | None, log=print) -> None:
    url, old = read_engine()
    if TREE.exists() and (TREE / '.git').exists() and (dirty() or unexported() or in_am() or rest_file().exists()):
        raise LayerError('tree/ has work that is not exported: run `layer.py export` first')
    local_file().unlink(missing_ok=True)   # the pin moves anyway
    git('fetch', '--quiet', url, f'+refs/heads/main:{MAIN_REF}')
    target = ref or MAIN_REF
    if git('rev-parse', '--verify', '--quiet', f'{target}^{{commit}}', check=False).returncode:
        git('fetch', '--quiet', url, target)
        target = 'FETCH_HEAD'
    new = git('rev-parse', f'{target}^{{commit}}').stdout.strip()
    if new == old:
        log(f'already on nxnative {new[:10]}')
        assemble(log=log)
        return
    n = git('rev-list', '--count', f'{old}..{new}', check=False).stdout.strip() or '?'
    log(f'nxnative {old[:10]} -> {new[:10]} ({n} commit(s))')
    write_engine(url, new)
    assemble(force=True, log=log)
    export(log=log)


def resolve(url: str, ref: str | None) -> str:
    """The nxnative commit REF names (default: nxnative's main, fetched)."""
    git('fetch', '--quiet', url, f'+refs/heads/main:{MAIN_REF}', check=False)
    target = ref or MAIN_REF
    if git('rev-parse', '--verify', '--quiet', f'{target}^{{commit}}', check=False).returncode:
        git('fetch', '--quiet', url, target)
        target = 'FETCH_HEAD'
    return git('rev-parse', f'{target}^{{commit}}').stdout.strip()


def local(ref: str | None, off: bool = False, log=print) -> None:
    """Assemble tree/ on nxnative's newest main (or REF) without changing layer/, or (off) go back to the pin."""
    if TREE.exists() and (TREE / '.git').exists() and (dirty() or unexported() or in_am() or rest_file().exists()):
        raise LayerError('tree/ has work that is not exported: run `layer.py export` (or `assemble --force`) first')
    url, pin = read_engine()
    if off:
        had = local_commit()
        local_file().unlink(missing_ok=True)
        assemble(force=True, log=log)
        log(f'engine: back to the pinned nxnative {pin[:10]}' if had else f'engine: already on the pinned nxnative {pin[:10]}')
        return
    new = resolve(url, ref)
    ensure_commit(url, pin)
    if new == pin or git('merge-base', '--is-ancestor', new, pin, check=False).returncode == 0:
        local_file().unlink(missing_ok=True)
        assemble(log=log)
        log(f'engine: the pin {pin[:10]} already has nxnative {new[:10]}; nothing to take')
        return
    results = try_update(new, log=log)
    bad = [(n, f) for n, state, f in results if state == 'conflicts']
    if bad:
        raise LayerError('not switched: ' + '; '.join(f'{n} clashes' + (f' in {", ".join(f)}' if f else '') for n, f in bad)
                         + '. The engine stays on the pin; NXForge has to update the patch first.')
    local_file().write_text(f'{new} {pin}\n')
    assemble(force=True, log=log)
    n = git('rev-list', '--count', f'{pin}..{new}', check=False).stdout.strip() or '?'
    log(f'engine: nxnative {new[:10]} (local, {n} commit(s) past the pin {pin[:10]}); `layer.py local --off` goes back')


def try_update(ref: str | None, log=print) -> list[tuple[str, str, list[str]]]:
    """[(patch, 'applies' | 'in nxnative' | 'conflicts', files)] for the patches on REF, in a throwaway worktree."""
    import tempfile
    url, old = read_engine()
    new = resolve(url, ref)
    ensure_commit(url, old)
    n = git('rev-list', '--count', f'{old}..{new}', check=False).stdout.strip() or '?'
    log(f'nxnative {old[:10]} -> {new[:10]} ({n} commit(s))')
    out = []
    with tempfile.TemporaryDirectory(prefix='nxforge-layer-try-') as tmp:
        w = Path(tmp) / 'tree'
        git('worktree', 'add', '--quiet', '--detach', str(w), new)
        try:
            for p in patch_files():
                r = git('am', '-3', '--quiet', '--keep-cr', str(p), cwd=w, check=False, env=IDENT)
                text = r.stdout + r.stderr
                if not r.returncode:
                    out.append((p.name, 'applies', []))
                elif 'No changes' in text or 'already applied' in text or 'Patch is empty' in text:
                    out.append((p.name, 'in nxnative', []))
                    git('am', '--skip', cwd=w, check=False, env=IDENT)
                else:
                    files = git('diff', '--name-only', '--diff-filter=U', cwd=w, check=False).stdout.split()
                    out.append((p.name, 'conflicts', files))
                    git('am', '--skip', cwd=w, check=False, env=IDENT)
                    git('checkout', '--quiet', '--force', 'HEAD', cwd=w, check=False)
        finally:
            git('worktree', 'remove', '--force', str(w), check=False)
            git('worktree', 'prune', check=False)
    for name, state, files in out:
        log(f'  {name}: {state}' + (f' ({", ".join(files)})' if files else ''))
    return out


def status(log=print) -> None:
    url, commit = read_engine()
    git('fetch', '--quiet', url, f'+refs/heads/main:{MAIN_REF}', check=False)
    ahead = git('rev-list', '--count', f'{commit}..{MAIN_REF}', check=False).stdout.strip()
    log(f'engine: {url} {commit[:10]}' + (f' (nxnative main is {ahead} commit(s) ahead)' if ahead else ''))
    lc = local_commit()
    if lc:
        n = git('rev-list', '--count', f'{commit}..{lc}', check=False).stdout.strip() or '?'
        log(f'local: tree/ is on nxnative {lc[:10]} ({n} commit(s) past the pin; `layer.py local --off` goes back)')
    log(f'layer: {len(patch_files())} patch(es), {len(layer_files())} file(s)')
    if not (TREE / '.git').exists():
        log('tree/: not assembled (run `layer.py assemble`)')
    elif in_am() or rest_file().exists():
        log('tree/: stopped on a patch that did not apply (fix it, then `layer.py continue`)')
    elif is_current():
        log('tree/: current')
    else:
        log('tree/: out of date' + (' (has unexported work)' if dirty() or unexported() else '') + ' (run `layer.py assemble`)')


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    a_as = sub.add_parser('assemble'); a_as.add_argument('--force', action='store_true')
    sub.add_parser('status'); sub.add_parser('export'); sub.add_parser('path')
    a_up = sub.add_parser('update'); a_up.add_argument('ref', nargs='?')
    a_try = sub.add_parser('try'); a_try.add_argument('ref', nargs='?')
    a_co = sub.add_parser('continue'); a_co.add_argument('--skip', action='store_true')
    a_lo = sub.add_parser('local'); a_lo.add_argument('ref', nargs='?'); a_lo.add_argument('--off', action='store_true')
    a = ap.parse_args(argv)
    try:
        if a.cmd == 'path':
            print(TREE)
        elif a.cmd == 'assemble':
            print('tree/ is current' if not assemble(a.force) else 'tree/ assembled')
        elif a.cmd == 'status':
            status()
        elif a.cmd == 'export':
            export()
        elif a.cmd == 'update':
            update(a.ref)
        elif a.cmd == 'continue':
            continue_(a.skip)
        elif a.cmd == 'local':
            local(a.ref, a.off)
        elif a.cmd == 'try':
            return 1 if any(state == 'conflicts' for _, state, _ in try_update(a.ref)) else 0
    except LayerError as e:
        print(f'layer.py: {e}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
