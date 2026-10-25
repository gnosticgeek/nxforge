# Atmosphere cheat files (.txt) to nxnative's Markdown cheat files (docs/cheats.md), and a check of Markdown ones.
# Usage:
#   cheats_md.py convert <in> <out dir> [--version V] [--game NAME] [--source URL]
#       <in> is one <build ID>.txt, or a folder holding Atmosphere's layout (<title ID>/cheats/<build ID>.txt, as in atmosphere/contents or the community cheat collections).
#       Writes <out dir>/<title ID>/<build ID>.md; the title ID comes from the path (…/<title ID>/cheats/<build ID>.txt), or --title-id for a lone file.
#   cheats_md.py check <file.md>...   parses each file as the host does (dm/host/cheats.c) and lists its cheats; non-zero exit when one has a problem
import argparse, os, re, sys

HEX16 = re.compile(r'^[0-9A-Fa-f]{16}$')
WORD = re.compile(r'^[0-9A-Fa-f]{8}$')

def parse_txt(text, warn=lambda s: None):
    """[(name, master, [lines of words])] from an Atmosphere cheat .txt; a cheat with a malformed line is left out (as the host does), and warn says so"""
    out, bad = [], set()
    for n, line in enumerate(text.splitlines(), 1):
        s = line.strip()
        if not s: continue
        m = re.match(r'^([\[{])(.*?)([\]}])', s)
        if m: out.append((m.group(2).strip(), m.group(1) == '{', [])); continue
        words = s.split()
        if not out or not all(WORD.match(w) for w in words):
            warn(f'line {n}: {s!r} is not a list of 8-digit hex words' + (f'; {out[-1][0]!r} left out' if out else '')); bad.add(len(out) - 1); continue
        out[-1][2].append(' '.join(w.upper() for w in words))
    return [c for i, c in enumerate(out) if c[2] and i not in bad]

def to_md(cheats, title_id, build_id, version=None, game=None, source=None):
    fm = [f'title_id: {title_id.upper()}', f'build_id: {build_id.upper()}']
    if version: fm.append(f'version: {version}')
    if game: fm.append(f'game: "{game}"')
    if source: fm.append(f'source: {source}')
    body = ['---', *fm, '---', '', f'# {game or title_id.upper()}' + (f' {version}' if version else ''), '']
    for name, master, lines in cheats:
        body += [f'## {name or "Master code"}', '```dmnt master' if master else '```dmnt', *lines, '```', '']
    return '\n'.join(body)

def parse_md(text):
    """(front matter dict, [(name, flags, word count, description)], [problems]) with the host's rules"""
    fm, cheats, problems, cur, fence, code = {}, [], [], None, False, False
    lines = text.splitlines()
    i = 0
    if lines and lines[0] == '---':
        i = 1
        while i < len(lines) and lines[i] != '---':
            k, _, v = lines[i].partition(':'); v = re.sub(r'\s+#.*$', '', v).strip().strip('"\''); fm[k.strip()] = v; i += 1
        i += 1
    for n, line in enumerate(lines[i:], i + 1):
        s = line.lstrip(' ')
        if s.startswith('```'):
            if fence: fence = code = False; continue
            info = s[3:].strip().split()
            fence, code = True, bool(info) and info[0].lower() == 'dmnt'
            if code and cur is None: problems.append(f'line {n}: code before the first ## heading')
            if code and cur is not None: cur['flags'] |= set(info[1:])
            continue
        if fence:
            if code and cur is not None and s.strip():
                ws = s.split()
                if not all(WORD.match(w) for w in ws): problems.append(f'line {n}: {s.strip()!r} in {cur["name"]!r} is not a list of 8-digit hex words'); cur['bad'] = True
                cur['words'] += len(ws)
            continue
        if s.startswith('## '):
            cur = {'name': s[3:].strip(), 'flags': set(), 'words': 0, 'desc': '', 'bad': False}; cheats.append(cur); continue
        if s.startswith('#'): continue
        if cur is not None and s.strip() and not cur['words']: cur['desc'] = (cur['desc'] + ' ' + s.strip()).strip()
    for c in cheats:
        if not c['words'] and not c['bad']: problems.append(f'{c["name"]!r} has no ```dmnt code')
        if c['words'] > 0x100: problems.append(f'{c["name"]!r} has {c["words"]} words, over the 256 one cheat may have')
    for k in ('title_id', 'build_id'):
        if k not in fm: problems.append(f'no {k} in the front matter')
    if 'title_id' in fm and not HEX16.match(fm['title_id']): problems.append(f'title_id {fm["title_id"]!r} is not 16 hex digits')
    if 'build_id' in fm and not re.match(r'^[0-9A-Fa-f]{16,64}$', fm['build_id']): problems.append(f'build_id {fm["build_id"]!r} is not 16 or more hex digits')
    return fm, [c for c in cheats if c['words'] and not c['bad']], problems

def convert(args):
    jobs = []
    if os.path.isdir(args.input):
        for root, _, files in os.walk(args.input):
            for f in files:
                stem, ext = os.path.splitext(f)
                if ext.lower() == '.txt' and HEX16.match(stem) and os.path.basename(root).lower() == 'cheats':
                    tid = os.path.basename(os.path.dirname(root))
                    if HEX16.match(tid): jobs.append((os.path.join(root, f), tid, stem))
    else:
        stem = os.path.splitext(os.path.basename(args.input))[0]
        parent = os.path.basename(os.path.dirname(os.path.dirname(os.path.abspath(args.input))))
        tid = args.title_id or (parent if HEX16.match(parent) else None)
        if not tid or not HEX16.match(stem): sys.exit(f'{args.input}: name it <build ID>.txt and give --title-id (or keep Atmosphere\'s <title ID>/cheats/ path)')
        jobs.append((args.input, tid, stem))
    for path, tid, bid in sorted(jobs):
        cheats = parse_txt(open(path, encoding='utf-8', errors='replace').read(), lambda s: print(f'{path}: {s}', file=sys.stderr))
        out = os.path.join(args.out, tid.upper(), bid.upper() + '.md')
        os.makedirs(os.path.dirname(out), exist_ok=True)
        open(out, 'w', encoding='utf-8').write(to_md(cheats, tid, bid, args.version, args.game, args.source))
        print(f'{out}: {len(cheats)} cheats')
    return 0

def check(args):
    bad = 0
    for path in args.files:
        fm, cheats, problems = parse_md(open(path, encoding='utf-8').read())
        print(f'{path}: {fm.get("game", "")} {fm.get("title_id", "?")} build {fm.get("build_id", "?")} {fm.get("version", "")}'.replace('  ', ' '))
        for c in cheats: print(f'  {c["name"]}  ({c["words"]} words{", " + ", ".join(sorted(c["flags"])) if c["flags"] else ""})')
        for p in problems: print(f'  problem: {p}')
        bad += bool(problems)
    return 1 if bad else 0

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description='Atmosphere cheat .txt to nxnative Markdown cheat files, and checks of Markdown ones')
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('convert'); c.add_argument('input'); c.add_argument('out'); c.add_argument('--title-id'); c.add_argument('--version'); c.add_argument('--game'); c.add_argument('--source')
    k = sub.add_parser('check'); k.add_argument('files', nargs='+')
    a = ap.parse_args()
    sys.exit(convert(a) if a.cmd == 'convert' else check(a))
