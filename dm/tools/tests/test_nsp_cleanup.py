"""NSP script: --cleanup after a successful build (cleanup). 'unused' deletes other versions' extracted files and rewritten modules, *.partial folders, tmp/ and the survey;
'all' deletes everything in <id>_build but logs/, profile/ and run/. Neither touches the NSPs, the keys or the built app. No game files needed."""
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('build_ipa_from_nsp', REPO / 'scripts/build_ipa_from_nsp.py')
assert spec and spec.loader
nsp = importlib.util.module_from_spec(spec); spec.loader.exec_module(nsp)

DIRS = ('extract/v0/RomFS', 'extract/v1179648/RomFS', 'extract/v1507328/RomFS', 'extract/v65536.partial', 'patched_v1507328', 'patched_v1179648', 'nro_v1507328', 'nro_v1179648',
        'patched_v1507328.partial', 'logs', 'profile/X', 'run/save', 'shader/cache', 'tools', 'tmp', 'nsp', 'aoc/1')
FILES = ('patched_v1507328.key', 'patched_v1179648.key', 'shader/pkg.key')


class Cleanup(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp()); self.addCleanup(shutil.rmtree, self.tmp)
        self.work, self.survey = self.tmp / 'X_build', self.tmp / 'X_survey'
        for d in DIRS: (self.work / d).mkdir(parents=True)
        for f in FILES: (self.work / f).touch()
        self.survey.mkdir()
        self.outside = [self.tmp / 'Game [v0].nsp', self.tmp / 'Game [v1507328].nsp', self.tmp / 'prod.keys', self.tmp / 'Game.app/Contents/MacOS/nxnative']
        for f in self.outside: f.parent.mkdir(parents=True, exist_ok=True); f.touch()

    def left(self):
        return sorted(str(p.relative_to(self.work)) for p in self.work.iterdir()) + sorted('extract/' + p.name for p in (self.work / 'extract').glob('*'))

    def test_unused_keeps_what_the_build_used(self):
        nsp.cleanup('unused', self.work, ['v1507328'], 'v1507328', self.survey)
        self.assertEqual(self.left(), sorted(['aoc', 'extract', 'logs', 'nro_v1507328', 'nsp', 'patched_v1507328', 'patched_v1507328.key', 'profile', 'run', 'shader', 'tools'])
                         + ['extract/v1507328'])
        self.assertFalse(self.survey.exists())
        self.assertTrue(all(f.exists() for f in self.outside))

    def test_all_keeps_logs_profile_and_save(self):
        nsp.cleanup('all', self.work, ['v1507328'], 'v1507328', self.survey, everything=True)
        self.assertEqual(sorted(p.name for p in self.work.iterdir()), ['logs', 'profile', 'run'])
        self.assertTrue((self.work / 'run/save').is_dir())
        self.assertTrue(all(f.exists() for f in self.outside))

    def test_provisional_survey_is_kept(self):
        nsp.cleanup('unused', self.work, ['v0'], 'v0', None)
        self.assertTrue(self.survey.is_dir())


if __name__ == '__main__':
    unittest.main()
