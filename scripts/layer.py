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
                                `git -C tree am --continue` (or --skip to drop it) and `layer.py export`
  layer.py export               write tree/'s commits back to the layer: patch commits to layer/patches (an edited or new commit
                                after the pin), changed layer files to layer/files
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


def patch_files() -> list[Path]:
    return sorted(PATCHES.glob('*.patch'))


def layer_files() -> list[str]:
    """Layer files as tree paths ("dm/host/quick_settings_mac.swift"), sorted."""
    return sorted(str(p.relative_to(FILES)) for p in FILES.rglob('*') if p.is_file() or p.is_symlink())


def stamp() -> str:
    h = hashlib.sha256(ENGINE.read_bytes())
    for p in patch_files():
        h.update(b'P' + p.name.encode() + b'\0' + p.read_bytes())
    for rel in layer_files():
        f = FILES / rel
        h.update(b'F' + rel.encode() + b'\0' + (b'x' if os.access(f, os.X_OK) else b'-') + f.read_bytes())
    return h.hexdigest()


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
    url, commit = read_engine()
    if TREE.exists() and (TREE / '.git').exists():
        if in_am():
            raise LayerError('tree/ is in the middle of applying patches (git am): finish with `git -C tree am --continue` or '
                             '--skip, then `layer.py export`; or `layer.py assemble --force` to start again')
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
    patches = patch_files()
    for p in patches:
        r = git('am', '-3', '--quiet', '--keep-cr', str(p), cwd=TREE, check=False, env=IDENT)
        if r.returncode:
            out = (r.stdout + r.stderr)
            if 'No changes' in out or 'already applied' in out or 'Patch is empty' in out:
                git('am', '--skip', cwd=TREE, env=IDENT)
                log(f'  {p.name}: nxnative already has it; it can be dropped (delete the file, or `layer.py export`)')
                continue
            conflicts = git('diff', '--name-only', '--diff-filter=U', cwd=TREE, check=False).stdout.split()
            raise LayerError(f'{p.name} does not apply to nxnative {commit[:10]}'
                             + (f' (conflicts in {", ".join(conflicts)})' if conflicts else '') +
                             '.\nFix it in tree/, `git -C tree add` the files and `git -C tree am --continue` (or `--skip` to drop the '
                             'patch), then `scripts/layer.py export`.')
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
    (tree_gitdir() / 'nxforge-layer').write_text(f'{stamp()} {tree_head()}\n')
    return True


def slug(subject: str) -> str:
    m = re.match(r'([a-z0-9][a-z0-9-]*):', subject)
    return m[1] if m else re.sub(r'[^a-z0-9]+', '-', subject.lower()).strip('-')[:40]


def export(log=print) -> None:
    if in_am():
        raise LayerError('tree/ is still applying patches: finish `git -C tree am --continue` first')
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
    (tree_gitdir() / 'nxforge-layer').unlink(missing_ok=True)
    assemble(force=True, log=lambda *_: None)


def update(ref: str | None, log=print) -> None:
    url, old = read_engine()
    if TREE.exists() and (TREE / '.git').exists() and (dirty() or unexported() or in_am()):
        raise LayerError('tree/ has work that is not exported: run `layer.py export` first')
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


def status(log=print) -> None:
    url, commit = read_engine()
    git('fetch', '--quiet', url, f'+refs/heads/main:{MAIN_REF}', check=False)
    ahead = git('rev-list', '--count', f'{commit}..{MAIN_REF}', check=False).stdout.strip()
    log(f'engine: {url} {commit[:10]}' + (f' (nxnative main is {ahead} commit(s) ahead)' if ahead else ''))
    log(f'layer: {len(patch_files())} patch(es), {len(layer_files())} file(s)')
    if not (TREE / '.git').exists():
        log('tree/: not assembled (run `layer.py assemble`)')
    elif in_am():
        log('tree/: stopped in git am (a patch did not apply)')
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
    except LayerError as e:
        print(f'layer.py: {e}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
