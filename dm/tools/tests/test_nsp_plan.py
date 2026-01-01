"""NSP script --plan (scripts/build_ipa_from_nsp.py): what a Mac app's build would reuse and redo, from the stages' own reuse checks, with the last run's stage times;
and the stage times a normal build records. No game files, keys or Xcode needed (temporary files only in a temporary folder)."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[3] / 'scripts/build_ipa_from_nsp.py'
spec = importlib.util.spec_from_file_location('build_ipa_from_nsp', SCRIPT)
assert spec and spec.loader
nsp = importlib.util.module_from_spec(spec); spec.loader.exec_module(nsp)


class Plan(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()); self.out = io.StringIO()
        self.prog = nsp.Progress('lines')
        for cm in (contextlib.redirect_stdout(self.out), mock.patch.object(nsp, 'PROG', self.prog), mock.patch.object(nsp.threading, 'Thread'),
                   mock.patch.object(nsp, 'PLAN', []), mock.patch.object(nsp, 'STAGE_TIMES', self.tmp / 'logs/stage_times.json')):
            cm.__enter__(); self.addCleanup(cm.__exit__, None, None, None)

    def test_a_normal_build_records_only_stages_that_did_work(self):
        with mock.patch.object(nsp, 'PLAN', None):
            for name, summary in (('unpack v131072', '24.4 GB'), ('check v131072 files', '3 files'), ('rewrite', 'main, reused (inputs unchanged)'),
                                  ('Mac shaders', '42,848 of 42,848 shaders ready (Metal libraries: 9,807 reused, 33,041 compiled)'), ('Mac host', 'reused'),
                                  ('Pipeline archive', 'applegpu_g16s, 3.8 GB')):
                self.prog.stage(name); self.prog.cur.t0 -= 90; self.prog.end(summary)
        # a count of reused pieces is a stage that did its work (Mac shaders after a chain change); only a whole reused stage is left out
        self.assertEqual(json.loads(nsp.STAGE_TIMES.read_text()), {'unpack': 90, 'check files': 90, 'Mac shaders': 90, 'Pipeline archive': 90})

    def test_reused_stages_are_listed_and_the_first_redone_one_stops_the_plan(self):
        nsp.STAGE_TIMES.parent.mkdir(parents=True); nsp.STAGE_TIMES.write_text(json.dumps({'Mac shaders': 900, 'Pipeline archive': 1567, 'Mac app': 191}))
        self.prog.stage('rewrite'); self.prog.end('main, reused (inputs unchanged)')
        self.prog.stage('Mac shaders')
        with self.assertRaises(nsp.PlanStop): nsp.plan_redo('Mac shaders', 'the translator changed')
        self.assertIsNone(self.prog.cur)
        nsp.PLAN.append(('Mac host', 'reused', ''))   # checked after the stop (PLAN_LATER)
        nsp.plan_report(True)
        text = self.out.getvalue()
        self.assertIn('reused: rewrite, Mac host', text)
        self.assertIn('redone: Mac shaders, the translator changed (last time 15:00)', text)
        self.assertIn('then, each redone only if what it reads changed: shader split, Pipeline archive (last time 26:07), Mac app (last time 3:11)', text)
        self.assertNotIn('shader split (last', text)
        self.assertIn('about 15:00, up to 44:18', text)

    def test_a_host_only_change_carries_on_to_the_app(self):
        nsp.plan_redo('Mac host', 'its sources changed', stop=False)
        nsp.PLAN.append(('Pipeline archive', 'reused', ''))
        nsp.plan_redo('Mac app', 'it packs the new Mac host', stop=False)
        nsp.plan_report(False)
        text = self.out.getvalue()
        self.assertIn('redone: Mac host', text); self.assertIn('redone: Mac app', text); self.assertNotIn('then,', text)

    def test_nothing_to_redo(self):
        for st in nsp.MAC_APP_STAGES: nsp.PLAN.append((st, 'reused', ''))
        nsp.plan_report(False)
        self.assertIn('nothing to redo', self.out.getvalue())

    def test_plan_redo_does_nothing_in_a_normal_build(self):
        with mock.patch.object(nsp, 'PLAN', None): nsp.plan_redo('rewrite')

    def test_run_returns_an_allowed_exit_code(self):
        log = self.tmp / 'check.log'
        self.assertEqual(nsp.run([sys.executable, '-c', 'raise SystemExit(3)'], log, ok=(3,), fatal=False), 3)
        self.assertEqual(nsp.run([sys.executable, '-c', 'pass'], log), 0)

    def test_plan_needs_a_mac_app(self):
        args = nsp.parse_args(['--plan', '--platform', 'ios', str(self.tmp)])
        with self.assertRaises(nsp.BuildError) as e: nsp.main(args)
        self.assertIn('--platform mac-app', str(e.exception))


if __name__ == '__main__':
    unittest.main()
