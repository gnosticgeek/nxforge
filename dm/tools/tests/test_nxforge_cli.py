#!/usr/bin/env python3
# scripts/nxforge.py and scripts/nxforge_mcp.py: what the cleanup categories take and leave, the guards, and the MCP protocol, on a fake home folder (nothing real is touched)
import importlib.util, io, json, os, sys, tempfile, time, unittest
from pathlib import Path
from unittest import mock

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO / 'scripts'))
spec = importlib.util.spec_from_file_location('nxforge', REPO / 'scripts/nxforge.py')
assert spec is not None and spec.loader is not None
nx = importlib.util.module_from_spec(spec); sys.modules['nxforge'] = nx; spec.loader.exec_module(nx)
import nxforge_mcp as mcp  # noqa: E402  # pyright: ignore[reportMissingImports]

DAY = 86400


def write(p, n=4096, age=0):
    p = Path(p); p.parent.mkdir(parents=True, exist_ok=True); p.write_bytes(b'x' * n)
    if age: t = time.time() - age; os.utime(p, (t, t))
    return p


class Fake(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory(); h = self.home = Path(self.td.name)
        self.sup = h / 'Library/Application Support/NXForge Converter'; self.sup.mkdir(parents=True)
        self.game = h / 'Documents/Cyber Shadow'
        self.app = self.game / 'Cyber Shadow.app'; write(self.app / 'Contents/MacOS/x')
        write(self.game / 'base.nsp'); write(self.game / 'prod.keys')
        b = self.build = self.game / '0100C1F0141AA000_build'
        for f in ('tmp/a', 'tmp.noindex/b', 'shader.partial/c', 'extract/v0/x', 'patched_v196608/m', 'patched_v131072/m', 'logs/l', 'profile/p', 'run/save'): write(b / f)
        write(b / 'patched_v196608.key'); write(b / 'patched_v131072.key', age=DAY)
        bk = self.game / 'app-backups'
        self.bk_new = write(bk / 'Cyber Shadow (0.2.0, 2026-10-30-16-58).app/Contents/x', age=10 * DAY).parents[1]
        self.bk_old = write(bk / 'Cyber Shadow (pre-0.1.0, 2026-10-01-10-00).app/Contents/x', age=30 * DAY).parents[1]
        self.bk_recent = write(bk / ('Cyber Shadow (0.3.0, %s).app/Contents/x' % time.strftime('%Y-%m-%d-%H-%M')), age=0).parents[1]
        self.loose = h / 'Documents/0400486024DEC000_build'; write(self.loose / 'tmp.noindex/t'); write(self.loose / 'extract/v0/x')
        write(h / 'Library/Logs/nxnative/old.log', age=40 * DAY); write(h / 'Library/Logs/nxnative/new.log')
        (self.sup / 'settings.json').write_text(json.dumps({'game_dir': str(self.game)}))
        (self.sup / 'builds.json').write_text(json.dumps([{'app': str(self.app), 'game_dir': str(self.game), 'engine': {'commit': 'abc'}, 'repo': '/nowhere', 'built_at': '2026-11-01 10:00'},
                                                          {'app': str(h / 'Documents/Gone/Gone.app'), 'game_dir': str(h / 'Documents/Gone')}]))
        self.patches = [mock.patch.object(nx, 'HOME', h), mock.patch.dict(os.environ, {'NXC_SUPPORT_DIR': str(self.sup)}),
                        mock.patch.object(nx, 'processes', list), mock.patch.object(nx, 'gpuarchiver_dir', lambda: h / 'gpu'),
                        mock.patch.object(nx, 'find_repo', lambda s=None: None)]
        for p in self.patches: p.start()

    def tearDown(self):
        for p in self.patches: p.stop()
        self.td.cleanup()

    def paths(self, res, cat): return {Path(i['path']) for i in res['categories'][cat]['items']}


class CleanTest(Fake):
    def test_safe_dry_run_lists_and_keeps(self):
        res = nx.clean(nx.SAFE, dry_run=True)
        self.assertEqual(self.paths(res, 'build-temp'), {self.build / 'tmp', self.build / 'tmp.noindex', self.build / 'shader.partial', self.loose / 'tmp.noindex'})
        self.assertEqual(self.paths(res, 'app-backups'), {self.bk_old, self.bk_new})   # the newest (and recent) one stays
        self.assertEqual(self.paths(res, 'old-logs'), {self.home / 'Library/Logs/nxnative/old.log'})
        self.assertTrue((self.build / 'tmp').exists() and self.bk_old.exists())

    def test_safe_deletes_only_safe(self):
        res = nx.clean(nx.SAFE)
        self.assertFalse(res['errors'])
        self.assertFalse((self.build / 'tmp').exists() or self.bk_old.exists() or (self.loose / 'tmp.noindex').exists())
        for keep in (self.app, self.bk_recent, self.game / 'base.nsp', self.game / 'prod.keys', self.build / 'extract/v0', self.build / 'patched_v131072', self.loose / 'extract'):
            self.assertTrue(keep.exists(), keep)
        self.assertIn('deleted', (self.sup / 'cli-clean.log').read_text())

    def test_backups_keep_count(self):
        res = nx.clean(['app-backups'], dry_run=True, ctx=nx.context(backup_days=0, backup_keep=0))
        self.assertEqual(self.paths(res, 'app-backups'), {self.bk_old, self.bk_new, self.bk_recent})

    def test_build_running_skips_build_categories(self):
        with mock.patch.object(nx, 'processes', lambda: [(42, 60, '/usr/bin/python3 scripts/build_ipa_from_nsp.py x')]):
            res = nx.clean(nx.SAFE, dry_run=True)
        self.assertTrue(res['categories']['build-temp'].get('skipped'))
        self.assertTrue(res['categories']['metal-cache'].get('skipped'))
        self.assertTrue(res['categories']['app-backups']['items'])

    def test_build_unused_and_cache(self):
        res = nx.clean(['build-unused', 'build-cache'], dry_run=True, ctx=nx.context(game='0100C1F0141AA000', idle_hours=0))
        self.assertEqual(self.paths(res, 'build-unused'), {self.build / 'patched_v131072', self.build / 'patched_v131072.key'})
        cache = self.paths(res, 'build-cache')
        self.assertIn(self.build / 'extract', cache)
        self.assertFalse({self.build / n for n in ('logs', 'profile', 'run')} & cache)
        self.assertFalse(any(self.loose in p.parents for p in cache))   # --game: only that game

    def test_recent_build_folders_stay(self):
        res = nx.clean(['build-unused', 'build-cache'], dry_run=True)   # every build folder here changed just now
        self.assertFalse(res['categories']['build-cache']['items'])
        self.assertTrue(any('kept: changed' in n for n in res['categories']['build-cache']['notes']))

    def test_gpuarchiver_one_item(self):
        idle = [write(self.home / f'gpu/gpuarchiver-{i}/r', age=2 * 3600).parent for i in range(3)]
        for d in idle: t = time.time() - 2 * 3600; os.utime(d, (t, t))
        fresh = write(self.home / 'gpu/gpuarchiver-new/r').parent
        res = nx.clean(['gpuarchiver'])
        self.assertEqual(len(res['categories']['gpuarchiver']['items']), 1)
        self.assertFalse(any(d.exists() for d in idle)); self.assertTrue(fresh.exists()); self.assertFalse(res['errors'])

    def test_release_name(self):
        self.assertEqual(nx.release_name('v0.2.0-2-g4ad5093'), '0.2.0+2'); self.assertEqual(nx.release_name('v0.11.0-0-gabc1234'), '0.11.0')

    def test_guard(self):
        ctx = nx.context()
        for p in (self.app, self.game / 'base.nsp', self.game / 'prod.keys', self.home / 'Documents'):
            with self.assertRaises(nx.Refused): nx.guard({'path': str(p)}, ctx)
        nx.guard({'path': str(self.bk_old)}, ctx)

    def test_lock(self):
        held = nx.lock()
        try:
            with self.assertRaises(nx.Refused): nx.clean(nx.SAFE)
        finally: held.close()

    def test_metal_cache_folder_trim(self):
        root = self.home / 'Library/Caches/NXForge/metallib'
        old, new = write(root / 'mac/aa/old.metallib', 2**20, age=DAY), write(root / 'mac/bb/new.metallib', 2**20)
        res = nx.clean(['metal-cache'], ctx=nx.context(mtlcache_gb=1.5 / 1024))
        self.assertFalse(old.exists()); self.assertTrue(new.exists()); self.assertFalse(res['errors'])

    def test_cli_json(self):
        out = io.StringIO()
        with mock.patch('sys.stdout', out): code = nx.main(['--json', 'clean', '--safe', '--dry-run'])
        self.assertEqual(code, 0); self.assertTrue(json.loads(out.getvalue())['dry_run'])
        with mock.patch('sys.stdout', io.StringIO()), mock.patch('sys.stderr', io.StringIO()), self.assertRaises(SystemExit): nx.main(['clean'])


class McpTest(Fake):
    def rpc(self, method, params=None, mid=1):
        return mcp.handle({'jsonrpc': '2.0', 'id': mid, 'method': method, 'params': params or {}})

    def test_protocol(self):
        r = self.rpc('initialize', {'protocolVersion': '2025-06-18', 'capabilities': {}, 'clientInfo': {'name': 't'}})
        self.assertEqual(r['result']['protocolVersion'], '2025-06-18')
        self.assertIsNone(mcp.handle({'jsonrpc': '2.0', 'method': 'notifications/initialized'}))
        names = {t['name'] for t in self.rpc('tools/list')['result']['tools']}
        self.assertTrue({'nxforge_status', 'nxforge_disk_report', 'nxforge_clean', 'nxforge_build', 'nxforge_job'} <= names)
        self.assertIn('error', self.rpc('nope'))

    def test_clean_defaults_to_dry_run(self):
        r = self.rpc('tools/call', {'name': 'nxforge_clean', 'arguments': {}})
        self.assertFalse(r['result']['isError'])
        self.assertTrue(json.loads(r['result']['content'][0]['text'])['dry_run'])
        self.assertTrue(self.bk_old.exists())
        r = self.rpc('tools/call', {'name': 'nxforge_clean', 'arguments': {'dry_run': False, 'categories': ['app-backups']}})
        self.assertFalse(self.bk_old.exists()); self.assertTrue(self.bk_recent.exists())

    def test_errors_are_tool_errors(self):
        r = self.rpc('tools/call', {'name': 'nxforge_clean', 'arguments': {'categories': ['everything']}})
        self.assertTrue(r['result']['isError'])
        r = self.rpc('tools/call', {'name': 'nxforge_job', 'arguments': {'id': 'none'}})
        self.assertTrue(r['result']['isError'])


class StatusLines(unittest.TestCase):   # status printed the interpreter's path (cut at 100 characters, before the script's name) and the converter's caffeinate wrapper as a second build
    def test_a_build_reads_from_its_script_once(self):
        py = '/opt/homebrew/Cellar/python@3.15/3.15.0/Frameworks/Python.framework/Versions/3.15/Resources/Python.app/Contents/MacOS/Python'
        args = 'scripts/build_ipa_from_nsp.py --mac /Users/tom/Documents/Game/base.nsp --keys /Users/tom/Documents/Game/prod.keys'
        procs = [(10, 480, f'caffeinate -is /Users/tom/Library/venv/bin/python3 {args}'), (11, 479, f'{py} {args}'),
                 (12, 60, '/Users/tom/Documents/Game/Game.app/Contents/MacOS/dmhost --x')]
        r = nx.running(procs)
        builds = nx.shown(r['builds'])
        self.assertEqual([(p['pid'], p['brief']) for p in builds], [(11, 'build_ipa_from_nsp.py --mac base.nsp --keys prod.keys')])
        self.assertEqual([p['brief'] for p in nx.shown(r['games'])], ['dmhost --x'])
        self.assertEqual(len(r['builds']), 2)   # --json still lists both processes


if __name__ == '__main__':
    unittest.main()
