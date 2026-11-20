#!/usr/bin/env python3
"""NXForge's game library (library/README.md): one folder per title ID with its enhancements and cheats as Markdown.

  library.py collect GAMES_FOLDER [--library DIR]   copy each game folder's enhancements/*.md and cheats/*.md into the library,
                                                    by the title ID in each file, switched off; prints what it added or changed
  library.py check [--library DIR]                  check every file: front matter, title ID folder, at least one block;
                                                    each game.md's genres are NXForge's (app/.../Genres.swift)
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HEX16 = re.compile(r'^[0-9A-Fa-f]{16}$')
FENCE = re.compile(r'^\s*```\s*(\w+)?')


def front_matter(text: str) -> dict[str, str] | None:
    lines = text.split('\n')
    if not lines or lines[0].strip() != '---':
        return None
    out: dict[str, str] = {}
    for line in lines[1:]:
        if line.strip() == '---':
            return out
        t = line.strip()
        if not t or t.startswith('#') or ':' not in t:
            continue
        k, v = t.split(':', 1)
        v = v.split(' #', 1)[0].strip()
        if len(v) >= 2 and v[0] == v[-1] == '"':
            v = v[1:-1]
        out[k.strip()] = v
    return None


def switched_off(text: str) -> str:
    """The file with its front matter's on: line set to false (the cheats' ```dmnt on fences too)."""
    lines = text.split('\n')
    end = next((i for i in range(1, len(lines)) if lines[i].strip() == '---'), None) if lines and lines[0].strip() == '---' else None
    if end is not None:
        lines = [('on: false' if 0 < i < end and l.strip().startswith('on:') else l) for i, l in enumerate(lines)]
    return '\n'.join(re.sub(r'^(\s*```dmnt)\s+on\s*$', r'\1', l) for l in lines)


def kind(fm: dict[str, str]) -> str | None:
    if 'nxforge_enhancement' in fm:
        return 'enhancements'
    if 'nxforge_cheats' in fm or 'build_id' in fm:
        return 'cheats'
    return None


def collect(games: Path, library: Path) -> list[str]:
    done = []
    for folder in ('enhancements', 'cheats'):
        for f in sorted(games.glob(f'**/{folder}/*.md')) + sorted(games.glob(f'**/* {folder}/*.md')):
            if f.name.startswith('.'):
                continue
            try:
                text = f.read_text(encoding='utf-8')
            except (OSError, UnicodeDecodeError):
                continue
            fm = front_matter(text)
            if fm is None or kind(fm) != folder or not HEX16.match(fm.get('title_id', '')):
                continue
            dest = library / fm['title_id'].upper() / folder / f.name
            new = switched_off(text)
            if dest.exists() and dest.read_text(encoding='utf-8') == new:
                continue
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_text(new, encoding='utf-8')
            done.append(str(dest.relative_to(library)))
    return done


def known_genres() -> set[str]:
    """Every genre and sub-genre in Genres.tree, read from the app's source."""
    src = (REPO / 'app/Sources/NXForgeConverter/Genres.swift').read_text(encoding='utf-8')
    tree = src.split('static let tree', 1)[1].split('\n    ]', 1)[0]
    return {m.replace("\\'", "'") for m in re.findall(r'"((?:[^"\\]|\\.)*)"', tree)}


def genres(text: str) -> list[str]:
    """The genres: list of a game.md's front matter."""
    out, inside = [], False
    for line in text.split('\n')[1:]:
        if line.strip() == '---':
            break
        if line.startswith('genres:'):
            inside = True
        elif inside and line.strip().startswith('- '):
            v = line.strip()[2:].strip()
            out.append(v[1:-1] if len(v) >= 2 and v[0] == v[-1] == '"' else v)
        elif inside and line.strip():
            inside = False
    return out


def check(library: Path) -> list[str]:
    bad = []
    known = known_genres()
    for f in sorted(library.glob('*/game.md')):
        rel = f.relative_to(library)
        text = f.read_text(encoding='utf-8')
        fm = front_matter(text)
        if fm is None or 'nxforge_game' not in fm:
            bad.append(f'{rel}: no nxforge_game front matter')
        elif fm.get('title_id', '').upper() != rel.parts[0].upper():
            bad.append(f'{rel}: title_id {fm.get("title_id")!r} is not the folder\'s')
        g = genres(text)
        if not g:
            bad.append(f'{rel}: no genres')
        for x in g:
            if x not in known:
                bad.append(f'{rel}: {x!r} is not one of NXForge\'s genres (Genres.swift)')
    for f in sorted(library.glob('*/*/*.md')):
        rel = f.relative_to(library)
        tid, folder = rel.parts[0], rel.parts[1]
        text = f.read_text(encoding='utf-8')
        fm = front_matter(text)
        if not HEX16.match(tid):
            bad.append(f'{rel}: the folder is not a title ID')
        elif fm is None:
            bad.append(f'{rel}: no front matter')
        elif fm.get('title_id', '').upper() != tid.upper():
            bad.append(f'{rel}: title_id {fm.get("title_id")!r} is not the folder\'s')
        elif kind(fm) != folder:
            bad.append(f'{rel}: not a file of {folder}/')
        elif folder == 'enhancements':
            if not fm.get('name'):
                bad.append(f'{rel}: no name')
            if fm.get('on', 'false') != 'false':
                bad.append(f'{rel}: on: must be false in the library')
            blocks = {m.group(1) for l in text.split('\n') if (m := FENCE.match(l)) and m.group(1)}
            if not blocks & {'env', 'dmnt', 'mods', 'mod'}:
                bad.append(f'{rel}: no env, dmnt or mods block')
            for b in fm.get('builds', '').replace(',', ' ').split():
                if not HEX16.match(b):
                    bad.append(f'{rel}: build {b!r} is not a build ID')
    return bad


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('collect'); c.add_argument('games', type=Path); c.add_argument('--library', type=Path, default=REPO / 'library')
    k = sub.add_parser('check'); k.add_argument('--library', type=Path, default=REPO / 'library')
    a = ap.parse_args(argv)
    if a.cmd == 'collect':
        for d in collect(a.games, a.library):
            print(d)
        return 0
    bad = check(a.library)
    for b in bad:
        print(b, file=sys.stderr)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
