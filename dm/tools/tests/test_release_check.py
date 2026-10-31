"""scripts/release_check.py: the CHANGELOG and BACKLOG rules a release is checked against (UPSTREAM.md, Versions), on the
repository's own files and on small made-up ones. No git or network."""
from pathlib import Path
import importlib.util
import unittest

REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('release_check', REPO / 'scripts/release_check.py')
assert spec and spec.loader
rc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(rc)

BACKLOG = 'x\nLast updated 2026-10-31 (0.8.0).\n'
LOG = """# Changelog

## 0.8.0 (2026-10-31)

- New thing.

## 0.7.1 (2026-10-30)

**Fixes**
- Old thing.
"""


class RepoFiles(unittest.TestCase):
    def test_changelog_and_backlog_pass_lint(self):
        problems = rc.lint((REPO / 'CHANGELOG.md').read_text(), (REPO / 'BACKLOG.md').read_text())
        self.assertEqual(problems, [])


class Rules(unittest.TestCase):
    def test_good_release(self):
        self.assertEqual(rc.check('0.8.0', LOG, BACKLOG), [])

    def test_notes_are_the_entry_without_heading(self):
        self.assertEqual(rc.notes('0.7.1', LOG), '**Fixes**\n- Old thing.\n')
        self.assertIsNone(rc.notes('0.6.0', LOG))

    def test_wrong_top_version(self):
        self.assertTrue(any('newest entry is 0.8.0' in p for p in rc.check('0.8.1', LOG, BACKLOG)))

    def test_unreleased_on_top_lints_but_does_not_check(self):
        log = LOG.replace('# Changelog\n', '# Changelog\n\n## Unreleased\n\n- Coming.\n')
        self.assertEqual(rc.lint(log, BACKLOG), [])
        self.assertTrue(any('Unreleased' in p for p in rc.check('0.8.0', log, BACKLOG)))

    def test_versions_must_go_down(self):
        log = LOG.replace('## 0.7.1', '## 0.9.0')
        self.assertTrue(any('not newer' in p for p in rc.lint(log, BACKLOG)))

    def test_dates_must_not_go_up(self):
        log = LOG.replace('0.7.1 (2026-10-30)', '0.7.1 (2026-11-02)')
        self.assertTrue(any('dated before' in p for p in rc.lint(log, BACKLOG)))

    def test_bad_heading_and_empty_entry(self):
        problems = rc.lint(LOG.replace('## 0.8.0 (2026-10-31)', '## v0.8.0 - Oct 31').replace('- New thing.', ''), BACKLOG)
        self.assertTrue(any('heading is not' in p for p in problems))
        problems = rc.lint(LOG.replace('- New thing.', ''), BACKLOG)
        self.assertTrue(any('entry is empty' in p for p in problems))

    def test_stale_backlog(self):
        problems = rc.check('0.8.0', LOG, 'Last updated 2026-10-28.\n')
        self.assertTrue(any('BACKLOG.md: last updated 2026-10-28' in p for p in problems))

    def test_backlog_without_date(self):
        self.assertTrue(any('BACKLOG.md' in p for p in rc.lint(LOG, 'nothing here')))


if __name__ == '__main__':
    unittest.main()
