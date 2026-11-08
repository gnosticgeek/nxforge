"""scripts/release_check.py: the CHANGELOG and BACKLOG rules a release is checked against (UPSTREAM.md, Versions), on the
repository's own files and on small made-up ones. No git or network."""
from pathlib import Path
import importlib.util
import unittest

REPO = Path(__file__).resolve().parents[1]
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

    def test_sidebar_changelog_and_version_pass_lint(self):
        problems = rc.lint_sidebar((REPO / rc.SIDEBAR_LOG).read_text(), (REPO / rc.SIDEBAR_SWIFT).read_text())
        self.assertEqual(problems, [])

    def test_converter_changelog_and_version_pass_lint(self):
        c = rc.COMPONENTS['converter']
        self.assertEqual(rc.lint_component(c, (REPO / c.log).read_text(), (REPO / c.swift).read_text()), [])

    def test_lint_command_covers_everything(self):
        self.assertEqual(rc.main(['lint']), 0)


SWIFT = 'import SwiftUI\n\nlet SIDEBAR_VERSION = "0.2.0"\n'
SIDE_LOG = LOG.replace('0.8.0', '0.2.0').replace('0.7.1', '0.1.0')


class Sidebar(unittest.TestCase):
    def test_good_sidebar_release(self):
        self.assertEqual(rc.check_sidebar('0.2.0', SIDE_LOG, SWIFT), [])

    def test_swift_constant_must_match_the_tag(self):
        problems = rc.check_sidebar('0.2.0', SIDE_LOG, SWIFT.replace('0.2.0', '0.3.0'))
        self.assertTrue(any('SIDEBAR_VERSION is 0.3.0, not 0.2.0' in p for p in problems))

    def test_swift_constant_may_run_ahead_but_not_behind(self):
        self.assertEqual(rc.lint_sidebar(SIDE_LOG, SWIFT.replace('0.2.0', '0.3.0')), [])
        self.assertTrue(any('older than' in p for p in rc.lint_sidebar(SIDE_LOG, SWIFT.replace('0.2.0', '0.1.0'))))
        self.assertTrue(any('no line' in p for p in rc.lint_sidebar(SIDE_LOG, 'import SwiftUI\n')))

    def test_problems_name_the_sidebar_changelog(self):
        problems = rc.check_sidebar('0.3.0', SIDE_LOG, SWIFT)
        self.assertTrue(any(p.startswith(rc.SIDEBAR_LOG + ': the newest entry is 0.2.0') for p in problems))

    def test_tags(self):
        self.assertEqual(rc.parse_tag('sidebar-v0.1.0'), (True, '0.1.0'))
        self.assertEqual(rc.parse_tag('v0.16.0'), (False, '0.16.0'))
        self.assertEqual(rc.parse_tag('0.16.0'), (False, '0.16.0'))


CONV_SWIFT = 'import Foundation\n\nlet CONVERTER_VERSION = "0.2.0"\n'


class Converter(unittest.TestCase):
    c = rc.COMPONENTS['converter']

    def test_good_converter_release(self):
        self.assertEqual(rc.check_component(self.c, '0.2.0', SIDE_LOG, CONV_SWIFT), [])

    def test_swift_constant_must_match_the_tag(self):
        problems = rc.check_component(self.c, '0.2.0', SIDE_LOG, CONV_SWIFT.replace('0.2.0', '0.3.0'))
        self.assertTrue(any('CONVERTER_VERSION is 0.3.0, not 0.2.0' in p for p in problems))
        self.assertTrue(any('no line' in p for p in rc.lint_component(self.c, SIDE_LOG, SWIFT)))

    def test_tags(self):
        self.assertEqual(rc.component_of('converter-v0.1.0'), (self.c, '0.1.0'))
        self.assertEqual(rc.component_of('sidebar-v0.1.0'), (rc.COMPONENTS['sidebar'], '0.1.0'))
        self.assertEqual(rc.component_of('v0.16.0'), (None, '0.16.0'))
        self.assertEqual(rc.parse_tag('converter-v0.1.0'), (False, '0.1.0'))


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
