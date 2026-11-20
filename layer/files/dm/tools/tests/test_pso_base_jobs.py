"""NXForge: pso_offline.py --base-jobs (batches of bases compiled several at a time) and --scratch (metal-tt's temporary files and library copies in a folder of their own).
The archive and the batches kept for the next run are the same as a sequential run's. No game files, no Metal tools (test_pso_offline.py's fake compiler)."""
import unittest
from pathlib import Path
from unittest import mock

from test_pso_offline import BuildCase, po


class BaseJobs(BuildCase):
    def run_batched(self, *extra):
        bases = [('v_bp', f'vertex{i}', 'f_b', 'main0') for i in range(7)]
        runner, observed = self.batched_runner()
        with mock.patch.object(self, 'fake_run', runner), mock.patch.object(po, 'plan', return_value=(bases, [], {})):
            self.main('--batch-size', '2', '--os-min', '27.0', *extra)
        return observed

    batched_runner = __import__('test_pso_offline').Build.batched_runner

    def test_batches_together_give_the_same_pieces_and_merge(self):
        observed = self.run_batched('--base-jobs', '3')
        self.assertEqual(sorted(names for kind, names in observed if kind == 'compile'), [['vertex0', 'vertex1'], ['vertex2', 'vertex3'], ['vertex4', 'vertex5'], ['vertex6']])
        self.assertEqual(observed[-1], ('merge', 4))
        self.assertTrue(list(self.out.glob('*.mtl4a')))
        observed = self.run_batched()   # a sequential run after it reuses everything
        self.assertEqual(observed, [])

    def test_scratch_takes_the_temporary_files(self):
        scratch = self.t / 'scratch'
        seen = []
        bases = [('v_bp', f'vertex{i}', 'f_b', 'main0') for i in range(3)]
        runner, _ = self.batched_runner()
        def spy(cmd, **kw):
            if 'metal-tt' in [str(c) for c in cmd] and '-o' in [str(c) for c in cmd]: seen.append(kw.get('env', {}).get('TMPDIR'))
            return runner(cmd, **kw)
        with mock.patch.object(self, 'fake_run', spy), mock.patch.object(po, 'plan', return_value=(bases, [], {})):
            self.main('--batch-size', '2', '--os-min', '27.0', '--scratch', str(scratch))
        self.assertEqual(len(seen), 2)
        self.assertTrue(all(t and Path(t).parent == scratch for t in seen))
        self.assertEqual(len(set(seen)), 2)   # one folder per batch
        self.assertFalse(list(self.work.rglob('libraries')))
        self.assertTrue(list(self.out.glob('*.mtl4a')))


if __name__ == '__main__':
    unittest.main()
