# NXForge's Markdown cheat files (0.4.0 to 0.8.0, docs/cheats.md) to Atmosphère's .txt, which the host reads since 0.9.0 (dm/host/hle_cheats.c).
# Usage:
#   cheats_md.py txt <file.md>... [--out DIR]   writes <build ID>.txt (the front matter's first 16 hex digits) beside each file, or in DIR; an existing .txt is left alone
#       Each ## heading becomes [name] ({name} for a ```dmnt master block), its ```dmnt lines the cheat's code; a cheat whose code is not 8-digit hex words is left out with a line
import argparse, os, re, sys

WORD = re.compile(r'^[0-9A-Fa-f]{8}$')

def parse_md(text):
    """(front matter dict, [(name, master, [code lines])], [problems])"""
    fm, cheats, problems, cur, fence, code = {}, [], [], None, False, False
    lines = text.splitlines()
    i = 0
    if lines and lines[0] == '---':
        i = 1
        while i < len(lines) and lines[i] != '---':
            k, _, v = lines[i].partition(':'); v = re.sub(r'\s+#.*$', '', v).strip().strip('"\''); fm[k.strip()] = v; i += 1
        i += 1
    for n, line in enumerate(lines[i:], i + 1):
        s = line.strip()
        if s.startswith('```'):
            if fence: fence = code = False; continue
            info = s[3:].strip().split()
            fence, code = True, bool(info) and info[0].lower() == 'dmnt'
            if code and cur is None: problems.append(f'line {n}: code before the first ## heading')
            if code and cur is not None and 'master' in info[1:]: cur['master'] = True
            continue
        if fence:
            if code and cur is not None and s:
                if not all(WORD.match(w) for w in s.split()): problems.append(f'line {n}: {s!r} in {cur["name"]!r} is not a list of 8-digit hex words'); cur['bad'] = True
                cur['code'].append(' '.join(w.upper() for w in s.split()))
            continue
        if s.startswith('## '): cur = {'name': s[3:].strip(), 'master': False, 'code': [], 'bad': False}; cheats.append(cur)
    for c in cheats:
        if not c['code'] and not c['bad']: problems.append(f'{c["name"]!r} has no ```dmnt code')
    if not re.match(r'^[0-9A-Fa-f]{16}', fm.get('build_id', '')): problems.append('no build_id of 16 or more hex digits in the front matter')
    return fm, [(c['name'], c['master'], c['code']) for c in cheats if c['code'] and not c['bad']], problems

def to_txt(cheats):
    out = []
    for name, master, code in cheats: out += [f'{{{name}}}' if master else f'[{name}]', *code, '']
    return '\n'.join(out)

def txt(args):
    bad = 0
    for path in args.files:
        fm, cheats, problems = parse_md(open(path, encoding='utf-8').read())
        for p in problems: print(f'{path}: {p}', file=sys.stderr)
        if 'build_id' not in fm or not cheats: bad = 1; continue
        out = os.path.join(args.out or os.path.dirname(os.path.abspath(path)), fm['build_id'][:16].upper() + '.txt')
        if os.path.exists(out): print(f'{out}: already there, left alone'); continue
        os.makedirs(os.path.dirname(out), exist_ok=True)
        open(out, 'w', encoding='utf-8').write(to_txt(cheats))
        print(f'{out}: {len(cheats)} cheats')
    return bad

if __name__ == '__main__':
    ap = argparse.ArgumentParser(description="NXForge's Markdown cheat files to Atmosphère .txt files")
    sub = ap.add_subparsers(dest='cmd', required=True)
    t = sub.add_parser('txt'); t.add_argument('files', nargs='+'); t.add_argument('--out')
    a = ap.parse_args()
    sys.exit(txt(a))
