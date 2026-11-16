#!/usr/bin/env python3
# scripts/ci_changes.py: which tests.yml jobs a change runs; unknown changes run everything
import importlib.util, os, subprocess, sys, tempfile, unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_changes', REPO / 'scripts/ci_changes.py')
assert spec is not None and spec.loader is not None
cc = importlib.util.module_from_spec(spec); sys.modules['ci_changes'] = cc; spec.loader.exec_module(cc)


class Jobs(unittest.TestCase):
    def test_unknown_runs_everything(self):
        self.assertEqual(cc.jobs(None), {'engine': True, 'converter': True})

    def test_converter_release(self):   # a converter-only release: the app, its changelog, NXForge's changelog
        self.assertEqual(cc.jobs(['app/Sources/NXForgeConverter/Engine.swift', 'app/Sources/NXForgeConverter/Version.swift', 'CONVERTER_CHANGELOG.md', 'CHANGELOG.md']),
                         {'engine': False, 'converter': True})

    def test_scripts_and_docs(self):
        self.assertEqual(cc.jobs(['scripts/nxforge.py', 'tests/test_nxforge_cli.py', 'docs/automation.md', 'README.md']), {'engine': False, 'converter': False})

    def test_engine_paths(self):
        for p in ('layer/patches/0001-host-player.patch', 'layer/ENGINE', 'layer/files/dm/host/quick_settings_mac.swift', 'scripts/layer.py',
                  '.github/workflows/tests.yml', '.github/requirements/tools.txt', '.gitattributes', 'newfolder/x'):
            self.assertTrue(cc.jobs([p])['engine'], p)

    def test_layer_runs_the_converter_too(self):   # its tests read docs/nxforge-games.tsv from the layer
        self.assertTrue(cc.jobs(['layer/files/docs/nxforge-games.tsv'])['converter'])

    def test_nothing_changed(self):
        self.assertEqual(cc.jobs([]), {'engine': False, 'converter': False})


class Git(unittest.TestCase):
    def test_diff_and_bad_base(self):
        with tempfile.TemporaryDirectory() as td:
            def git(*a): subprocess.run(['git', '-C', td, *a], check=True, capture_output=True,
                                        env={'GIT_AUTHOR_NAME': 't', 'GIT_AUTHOR_EMAIL': 't@t', 'GIT_COMMITTER_NAME': 't', 'GIT_COMMITTER_EMAIL': 't@t', 'PATH': '/usr/bin:/bin:/usr/local/bin'})
            git('init', '-q'); (Path(td) / 'a.md').write_text('a'); git('add', '.'); git('commit', '-qm', 'a')
            (Path(td) / 'app').mkdir(); (Path(td) / 'app/x.swift').write_text('x'); git('add', '.'); git('commit', '-qm', 'b')
            here = Path.cwd()
            try:
                os.chdir(td)
                self.assertEqual(cc.changed('HEAD^1'), ['app/x.swift'])
                self.assertIsNone(cc.changed('0' * 40))
            finally:
                os.chdir(here)


if __name__ == '__main__':
    unittest.main()
