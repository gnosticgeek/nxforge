#!/usr/bin/env python3
"""A `clang` for CI that compiles each source file of a one-shot "compile and link" command through ccache.

The engine's test Makefiles build each test with one command that names every source (`clang $(CFLAGS) -o t_x t_x.c
$(GFX) ...`), so the same dozens of gfx sources are compiled again for every test, and ccache cannot cache such a command.
Put a link named `clang` to this script first on PATH (tests.yml, the build job): a command with two or more sources and
no -c/-E/-S becomes one `ccache clang ... -c` per source (the same flags, so the cache key is the same as the real
command's) and a link of the objects. Any other command goes through ccache as it is (ccache caches a one-file -c and runs the rest unchanged). Without
ccache it does nothing.

  NXF_CLANG_REAL   the real clang (default: the next `clang` on PATH after this one's folder, or `xcrun -f clang`)
  NXF_CLANG_OFF=1  pass everything through
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

SOURCES = ('.c', '.m', '.cc', '.cpp', '.cxx', '.mm', '.S', '.s')
NO_SPLIT = {'-c', '-E', '-S', '-M', '-MM', '-x', '-', '-fsyntax-only', '-emit-llvm', '-###', '--version', '-v'}
WITH_ARG = {'-o', '-I', '-D', '-U', '-include', '-isystem', '-iquote', '-idirafter', '-framework', '-F', '-L', '-l',
            '-arch', '-target', '-isysroot', '-MF', '-MT', '-MQ', '-Xlinker', '-Xclang', '-mllvm', '-install_name',
            '-weak_framework', '-rpath', '-exported_symbols_list', '-sectcreate'}
LINK_ONLY_PREFIX = ('-l', '-L', '-Wl,', '-framework', '-weak_framework', '-F', '-rpath', '-Xlinker', '-dynamiclib',
                    '-shared', '-install_name', '-exported_symbols_list', '-sectcreate')


def real_clang() -> str:
    if os.environ.get('NXF_CLANG_REAL'):
        return os.environ['NXF_CLANG_REAL']
    here = Path(__file__).resolve().parent
    me = Path(sys.argv[0]).absolute().parent
    for d in os.environ.get('PATH', '').split(os.pathsep):
        if not d or Path(d).absolute() in (here, me):
            continue
        c = Path(d) / 'clang'
        if c.is_file() and os.access(c, os.X_OK) and c.resolve() != Path(__file__).resolve():
            return str(c)
    try:
        return subprocess.run(['xcrun', '-f', 'clang'], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return 'clang'


def split(args: list[str]) -> tuple[list[str], list[str], list[str], str | None] | None:
    """(compile flags, sources, link-only args, output) for a multi-source compile-and-link command, else None."""
    flags: list[str] = []
    sources: list[str] = []
    link: list[str] = []
    out = None
    i = 0
    while i < len(args):
        a = args[i]
        if a in NO_SPLIT:
            return None
        pair = a in WITH_ARG and i + 1 < len(args)
        group = [a, args[i + 1]] if pair else [a]
        i += len(group)
        if a == '-o' and pair:
            out = group[1]
        elif a.startswith(LINK_ONLY_PREFIX) or (not a.startswith('-') and a.endswith(('.o', '.a', '.dylib', '.tbd'))):
            link += group
        elif not a.startswith('-') and a.endswith(SOURCES):
            sources.append(a)
        else:
            flags += group
    return (flags, sources, link, out) if len(sources) >= 2 and out else None


def main(argv: list[str]) -> int:
    clang = real_clang()
    ccache = shutil.which('ccache')
    if os.environ.get('NXF_CLANG_OFF') or not ccache:
        os.execvp(clang, [clang, *argv])
    plan = split(argv)
    if plan is None:
        # a plain one-file compile is cached as it is; anything else (a link, -E, -M) ccache passes through itself
        os.execv(ccache, [ccache, clang, *argv])
    flags, sources, link, out = plan
    assert ccache and out
    with tempfile.TemporaryDirectory(prefix='nxf-clang-') as tmp:
        objs = []
        for n, src in enumerate(sources):
            obj = os.path.join(tmp, f'{n}-{Path(src).stem}.o')
            # -Qunused-arguments: a flag the whole command used for one kind of file (-fobjc-arc) is unused for another
            r = subprocess.run([ccache, clang, *flags, '-Qunused-arguments', '-c', src, '-o', obj])
            if r.returncode:
                return r.returncode
            objs.append(obj)
        return subprocess.run([clang, *flags, '-Qunused-arguments', *objs, *link, '-o', out]).returncode


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
