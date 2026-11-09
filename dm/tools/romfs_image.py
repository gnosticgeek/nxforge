#!/usr/bin/env python3
# Pack an extracted RomFS folder into one image file the host reads in place of the folder (hle_fs.c, "RomFS image"): DM_ROMFS may name the image instead of a folder.
# One file instead of hundreds of thousands copies to an iPhone at full speed (Tears of the Kingdom's 304,000 files ran the phone's file service out of open files), and the host
# keeps one descriptor open for the whole RomFS.
# Layout (little-endian):
#   header  32 bytes: magic "DMROMFS1", u64 index offset, u64 index size, u64 entry count
#   data    each file's bytes, one after another
#   index   entry count entries of 24 bytes: u64 a, u64 b, u32 name offset, u16 name length, u8 type (0 directory, 1 file), u8 flags
#           a directory: a = its first child's entry, b = its number of children; a file: a = data offset in the image, b = size
#           flags: 0, or 1 on a file that failed the NCA's hash check and was written as read (nx_extract --allow-damaged; the host names it in its log)
#           then the names, one pool. Entry 0 is the root (empty name). Each directory's children are consecutive entries sorted by name (bytes), so a lookup is a
#           binary search per path component; directories are numbered breadth-first.
# The index comes last, so a copy cut off partway has no valid index (the header points past the end of the file) and the host refuses it.
# Names are the guest names: a host name chosen on a case collision (.dm-case-N) is replaced by the one in its xattr, as hle_fs.c's guest_name does.
# Usage: romfs_image.py [--reuse] <RomFS folder> <out image>   (written to <out>.part, renamed at the end)
# --reuse checks the source tree's names and file metadata, the packer's version and the image's identity before keeping a previous image.
import argparse, hashlib, json, os, struct, subprocess, sys
from pathlib import Path

MAGIC = b'DMROMFS1'
HEAD = struct.Struct('<8sQQQ')
ENT = struct.Struct('<QQIHBB')
GUEST_NAME = 'org.d2rmobile.guest-name'
# Files a dump tool leaves in every folder of the game's tree, which are not game files: an FTP dump keeps the server's listing as .listing (as the NUP spec's §6.3 says a producer
# may). Packed, a game that lists a folder sees one more entry: Nintendo Switch Sports Resort cuts each name at its first '.', loaded "Parameter/<folder>/" with an empty name, got
# no resource and crashed at main+0x9d7c60. A folder's artifacts are left out of the image (and out of a NUP's, pack_nup.py), as they are of the survey's file list
ARTIFACTS = {b'.listing'}


def guest(parent, name):
    if not name.startswith('.dm-case-'): return name
    r = subprocess.run(['xattr', '-p', GUEST_NAME, os.path.join(parent, name)], capture_output=True, text=True)
    return r.stdout.rstrip('\n') if r.returncode == 0 else name


# A folder's entries with their metadata in one call per folder (macOS getattrlistbulk), not a stat per file: on an exFAT drive (macOS's FSKit driver) a
# stat costs about a millisecond, and a dump of Mario Kart World's 411,696 files was walked four times before its image was written. Elsewhere os.scandir.
_IDS = {}   # host path → file_identity, from the listing children() made; source_digest takes each one out
_ATTR_CMN_NAME, _ATTR_CMN_OBJTYPE, _ATTR_CMN_MODTIME, _ATTR_CMN_CHGTIME, _ATTR_CMN_FILEID = 0x1, 0x8, 0x400, 0x800, 0x02000000
_ATTR_CMN_RETURNED_ATTRS, _ATTR_FILE_DATALENGTH = 0x80000000, 0x200
_VREG, _VDIR, _VLNK = 1, 2, 5
_bulk_fn = None


def _bulk():
    global _bulk_fn
    if _bulk_fn is None:
        _bulk_fn = False
        if sys.platform == 'darwin':
            try:
                import ctypes
                f = ctypes.CDLL(None, use_errno=True).getattrlistbulk
                f.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_uint64]
                f.restype = ctypes.c_int
                common = _ATTR_CMN_RETURNED_ATTRS | _ATTR_CMN_NAME | _ATTR_CMN_OBJTYPE | _ATTR_CMN_MODTIME | _ATTR_CMN_CHGTIME | _ATTR_CMN_FILEID
                al = struct.pack('<HHIIIII', 5, 0, common, 0, 0, _ATTR_FILE_DATALENGTH, 0)
                _bulk_fn = (ctypes, f, ctypes.create_string_buffer(al, len(al)))
            except (OSError, AttributeError): pass
    return _bulk_fn


def _bulk_listing(path):   # [(name, kind, identity or None)]; identity only for a regular file that returned all four fields
    lib = _bulk()
    if not isinstance(lib, tuple): raise OSError('getattrlistbulk is not available')
    ctypes, f, al = lib
    buf = ctypes.create_string_buffer(256 * 1024)
    out = []
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        while True:
            n = f(fd, al, buf, len(buf), 0)
            if n < 0: raise OSError(ctypes.get_errno(), os.strerror(ctypes.get_errno()), path)
            if n == 0: break
            raw = buf.raw; p = 0
            for _ in range(n):
                length, common, _vol, _dir, file = struct.unpack_from('<IIIII', raw, p)
                q = p + 24
                name = kind = mtime = ctime = ino = size = None
                if common & _ATTR_CMN_NAME:
                    off, nlen = struct.unpack_from('<iI', raw, q); name = raw[q + off:q + off + nlen].split(b'\0', 1)[0]; q += 8
                if common & _ATTR_CMN_OBJTYPE: kind, = struct.unpack_from('<I', raw, q); q += 4
                if common & _ATTR_CMN_MODTIME: sec, ns = struct.unpack_from('<qq', raw, q); mtime = sec * 10**9 + ns; q += 16
                if common & _ATTR_CMN_CHGTIME: sec, ns = struct.unpack_from('<qq', raw, q); ctime = sec * 10**9 + ns; q += 16
                if common & _ATTR_CMN_FILEID: ino, = struct.unpack_from('<Q', raw, q); q += 8
                if file & _ATTR_FILE_DATALENGTH: size, = struct.unpack_from('<q', raw, q)
                p += length
                if name is None: continue
                k = 'dir' if kind == _VDIR else 'file' if kind == _VREG else 'link' if kind == _VLNK else 'other'
                ident = [ino, size, mtime, ctime] if k == 'file' and None not in (ino, size, mtime, ctime) else None
                out.append((os.fsdecode(name), k, ident))
    finally: os.close(fd)
    return out


def _listing(path):
    if _bulk():
        try: return _bulk_listing(path)
        except OSError: pass   # a file system without getattrlistbulk: as below
    out = []
    with os.scandir(path) as it:
        for e in it:
            k = 'dir' if e.is_dir(follow_symlinks=False) else 'link' if e.is_symlink() else 'file' if e.is_file(follow_symlinks=False) else 'other'
            out.append((e.name, k, None))
    return out


def listing(path):   # a folder's entries: [(name, 'dir' | 'file' | 'link' | 'other', file_identity or None)], without the files macOS adds on other file systems
    ents = _listing(path)
    names = {e[0] for e in ents}
    return [e for e in ents if not macos_litter(e[0], names)]


def macos_litter(name, names):
    """Files macOS writes beside a game's own on a drive that is not APFS or HFS+ (exFAT, FAT, SMB): ._<name>, the AppleDouble file holding <name>'s extended attributes
    (a Mario Kart World dump copied to an exFAT drive had 140,640, and the image's format check refused them), and .DS_Store. A RomFS has neither."""
    return name == '.DS_Store' or (name.startswith('._') and name[2:] in names)


def tree_size(d):   # (files, bytes) under d, symbolic links counted as themselves; (0, 0) when it does not exist yet
    n = b = 0; todo = [os.fspath(d)]
    while todo:
        path = todo.pop()
        try: ents = listing(path)
        except OSError: continue
        for name, kind, ident in ents:
            p = os.path.join(path, name)
            if kind == 'dir': todo.append(p); continue
            n += 1
            try: b += ident[1] if ident else os.lstat(p).st_size
            except OSError: pass
    return n, b


def children(path):
    out = []
    for name, kind, ident in listing(path):
        p = os.path.join(path, name)
        if ident is not None: _IDS[p] = ident
        gname, isdir = guest(path, name).encode(), kind == 'dir' or (kind == 'link' and os.path.isdir(p))
        if isdir or gname not in ARTIFACTS: out.append((gname, p, isdir))   # a dump tool's .listing files are not the game's
    out.sort()
    return out


def entries(src):
    ents = [[b'', src, True, 0, 0]]   # name, host path, is dir, a, b
    i = 0
    while i < len(ents):   # breadth-first: each directory's children land as one consecutive run
        name, path, isdir, _, _ = ents[i]
        if isdir:
            kids = children(path)
            ents[i][3], ents[i][4] = len(ents), len(kids)
            ents.extend([n, p, d, 0, 0] for n, p, d in kids)
        i += 1
    return ents


def file_identity(path):   # not st_dev: macOS numbers a volume when it mounts it, so a reboot moved the Data volume from 16777234 to 16777232 and a 24 GB image was packed again, 8 minutes over SMB
    s = os.stat(path)
    return [s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns]


def source_digest(src, ents):
    h = hashlib.sha256(Path(__file__).read_bytes())
    h.update(os.fsencode(os.path.realpath(src)) + b'\0')
    for name, path, isdir, _, _ in ents:
        h.update(struct.pack('<I?', len(name), isdir)); h.update(name)
        h.update(json.dumps(_IDS.pop(path, None) or file_identity(path)).encode() + b'\0')
    return h.hexdigest()


def reusable(dst, digest):   # whether dst is the image the stamp beside it says was made from inputs with this digest; a stamp from before file_identity left st_dev out has it first
    try:
        stamp = json.loads(Path(dst + '.inputs.json').read_text())
        return stamp['source'] == digest and stamp['image'][-4:] == file_identity(dst)
    except (OSError, ValueError, KeyError, TypeError): return False


def layout(ents, end):
    """The header and the index (entries, then the name pool) of an image of ents whose files' a and b are filled in, the file data ending at end.
    write() writes these bytes and a check of an existing image compares them, so the two cannot disagree on the format."""
    pool, idx = bytearray(), bytearray()
    for name, _, isdir, a, b in ents:
        idx += ENT.pack(a, b, len(pool), len(name), 0 if isdir else 1, 0); pool += name
    idx += pool
    return HEAD.pack(MAGIC, end, len(idx), len(ents)), bytes(idx)


def write(ents, dst, copy):
    """ents (entries(): [name, source, is dir, a, b], breadth-first) → dst + '.part'; copy(source, out) writes one file's bytes to out and returns how many. Fills in each file's a and b"""
    part = dst + '.part'
    with open(part, 'wb') as out:
        out.write(b'\0' * HEAD.size)
        off = HEAD.size
        for e in ents:
            if e[2]: continue
            e[3], e[4] = off, copy(e[1], out); off += e[4]
        head, idx = layout(ents, off)
        out.write(idx)
        out.seek(0); out.write(head)
    return part


def stamp(dst, digest, image):   # the stamp reusable() checks: dst, with identity image, is the image of inputs with this digest
    Path(dst + '.inputs.json.part').write_text(json.dumps({'source': digest, 'image': image}))
    os.replace(dst + '.inputs.json.part', dst + '.inputs.json')


def publish(part, dst, digest):   # the written image in place, with its stamp
    os.replace(part, dst)
    stamp(dst, digest, file_identity(dst))


def copy_file(path, out):
    n = 0
    with open(path, 'rb') as f:
        while b := f.read(8 << 20): out.write(b); n += len(b)
    return n


class Prefetch:
    """copy() for write() that reads the small files ahead on a few threads, in the order write() asks for them: each file read costs a round trip to the file
    system (most on an exFAT drive or a network share), and a RomFS is mostly small files. Files over SMALL, or of unknown size, are copied as copy_file does."""
    SMALL, WINDOW, THREADS = 1 << 20, 512, 16   # Mario Kart World's Tex/ (107,232 files) on an exFAT drive: 12 ms a file read in turn, 2.3 ms on 16 threads

    def __init__(self, paths, sizes):
        import collections
        from concurrent.futures import ThreadPoolExecutor
        self.paths, self.sizes, self.next = paths, sizes, 0
        self.pool = ThreadPoolExecutor(self.THREADS)
        self.ahead = collections.deque()
        self.fill()

    def fill(self):
        while len(self.ahead) < self.WINDOW and self.next < len(self.paths):
            p = self.paths[self.next]; self.next += 1
            small = self.sizes.get(p) is not None and self.sizes[p] <= self.SMALL
            self.ahead.append((p, self.pool.submit(Path(p).read_bytes) if small else None))

    def copy(self, path, out):
        if not self.ahead or self.ahead[0][0] != path: return copy_file(path, out)   # not the order planned: no read ahead
        _, f = self.ahead.popleft(); self.fill()
        if f is None: return copy_file(path, out)
        data = f.result(); out.write(data)
        return len(data)

    def close(self):
        for _, f in self.ahead:
            if f: f.cancel()
        self.pool.shutdown(wait=True)


def pack(src, dst, reuse=False):
    src, dst = os.fspath(src), os.fspath(dst)
    ents = entries(src)
    sizes = {e[1]: _IDS[e[1]][1] for e in ents if not e[2] and e[1] in _IDS}
    digest = source_digest(src, ents)
    if reuse and reusable(dst, digest): return len(ents)
    pre = Prefetch([e[1] for e in ents if not e[2]], sizes)
    try: part = write(ents, dst, pre.copy)
    finally: pre.close()
    # A changing source must not publish a mixed image or a reuse stamp for stale data.
    if source_digest(src, entries(src)) != digest:
        os.unlink(part)
        raise RuntimeError('RomFS changed while packing; run the packer again when its files are stable')
    publish(part, dst, digest)
    return len(ents)


def read_index(img):   # for tests and checks: {guest path: (is dir, offset, size)}
    with open(img, 'rb') as f:
        magic, ioff, isz, n = HEAD.unpack(f.read(HEAD.size))
        assert magic == MAGIC
        f.seek(ioff); raw = f.read(isz)
    pool = raw[n * ENT.size:]
    e = [ENT.unpack_from(raw, k * ENT.size) for k in range(n)]
    out, todo = {}, [(0, '')]
    while todo:
        k, path = todo.pop()
        a, b, no, nl, t, _ = e[k]
        if t == 0:
            if path: out[path] = (True, 0, 0)
            todo.extend((c, (path + '/' if path else '') + pool[e[c][2]:e[c][2] + e[c][3]].decode()) for c in range(a, a + b))
        else: out[path] = (False, a, b)
    return out


# File names that promise a format, and the first bytes that format starts with. A file whose name promises one and whose bytes start with none of its heads is damaged:
# a NUP or a dump folder carries no NCA hashes, so this is the check its extraction has. A zstd stream starts with a frame (28 b5 2f fd) or a skippable frame (5? 2a 4d 18).
# Found on a NUP of Ocarina of Time whose three .zs textures began with 12,288 zero bytes: the game asked for one again on every pass of its background loader (PR #1530).
FORMAT_HEADS = {'.zs': ((b'\x28\xb5\x2f\xfd', b'\xff\xff\xff\xff'), (b'\x50\x2a\x4d\x18', b'\xf0\xff\xff\xff'))}   # suffix: ((bytes, mask), ...)


def format_mismatches(img, progress=None):   # [(guest path, size, first 4 bytes)] of the image's files whose bytes do not start as their name promises (FORMAT_HEADS); empty files are left out. progress(done, total): every 4,096 files
    files = sorted((off, size, p) for p, (d, off, size) in read_index(img).items() if not d and size and os.path.splitext(p)[1].lower() in FORMAT_HEADS)
    bad = []
    with open(img, 'rb') as f:
        for k, (off, size, p) in enumerate(files):   # in image order: one pass forward over the disk
            if progress and not k % 4096: progress(k, len(files))
            f.seek(off); head = f.read(min(size, 4))   # not into the next file's bytes
            if not any(len(head) == 4 and all(h & m == w & m for h, w, m in zip(head, want, mask)) for want, mask in FORMAT_HEADS[os.path.splitext(p)[1].lower()]):
                bad.append((p, size, head))
    return bad


ID_MAGIC = 'DMROMFSID1'
_FNV_OFFSET, _FNV_PRIME, _MASK = 0xcbf29ce484222325, 0x100000001b3, (1 << 64) - 1


def _clean(text):   # one token of the identity line: no spaces, no newlines
    return ''.join(c if c.isalnum() or c in '._-+' else '_' for c in str(text)) or '-'


def identity(img, title='', version='', build=''):
    """The identity line of a complete image (dm/host/romfs_identity.h defines the format and the C reader): its size and an FNV-1a 64 hash of its header and index
    (the file data is not read, so a 14 GB image takes a moment). Raises ValueError for a cut off or invalid image."""
    size = os.path.getsize(img)
    with open(img, 'rb') as f:
        head = f.read(HEAD.size)
        if len(head) != HEAD.size: raise ValueError(f'not a RomFS image: {img}')
        magic, ioff, isz, _ = HEAD.unpack(head)
        if magic != MAGIC or ioff < HEAD.size or ioff > size or isz != size - ioff: raise ValueError(f'incomplete or invalid RomFS image: {img}')
        h, rest = _FNV_OFFSET, b''
        f.seek(ioff)
        def mix(h, data):
            for w in struct.unpack(f'<{len(data) // 8}Q', data): h = ((h ^ w) * _FNV_PRIME) & _MASK
            return h
        h = mix(h, head)
        left = isz
        while left:
            chunk = f.read(min(left, 8 << 20))
            if not chunk: raise ValueError(f'incomplete RomFS image: {img}')
            left -= len(chunk)
            chunk = rest + chunk
            keep = len(chunk) % 8 if left else 0
            rest = chunk[len(chunk) - keep:]; chunk = chunk[:len(chunk) - keep]
            if not left and len(chunk) % 8: chunk += b'\0' * (8 - len(chunk) % 8)
            h = mix(h, chunk)
    return f'{ID_MAGIC} title={_clean(title)} version={_clean(version)} build={_clean(build)} size={size} index={h:016x}'


def parse_identity(text):   # {field: value} of an identity line; size is an int
    parts = text.split()
    if not parts or parts[0] != ID_MAGIC: raise ValueError('not an identity line')
    d = dict(p.split('=', 1) for p in parts[1:] if '=' in p)
    if 'size' not in d or 'index' not in d: raise ValueError('identity line without size or index')
    d['size'] = int(d['size']); return d


def same_identity(a, b):   # two lines name the same image when size and index agree (title, version and build only describe it)
    x, y = parse_identity(a), parse_identity(b)
    return (x['size'], x['index']) == (y['size'], y['index'])


if __name__ == '__main__':
    import sys
    if sys.argv[1:2] == ['--identity']:   # romfs_image.py --identity IMAGE [TITLE [VERSION [BUILD]]]: the identity line of IMAGE
        try: print(identity(*sys.argv[2:6]))
        except (OSError, ValueError, TypeError) as e: sys.exit(f'[RED] {e}')
        sys.exit(0)
    ap = argparse.ArgumentParser(description='Pack a RomFS folder into an indexed image')
    ap.add_argument('--reuse', action='store_true', help='keep the image only while its source tree, packer and image are unchanged')
    ap.add_argument('source'); ap.add_argument('image')
    args = ap.parse_args()
    n = pack(args.source, args.image, reuse=args.reuse)
    print(f'{args.image}: {n} entries, {os.path.getsize(args.image)} bytes')
