"""docs/settings.md, Quick settings on the Mac: every preference key the Mac app's Quick settings and front end save (DMQuickSettings.<what>.<game>,
DMPresentFilter.<what>.<game>, launcher.<variable>) is in its table, and every Mac row of dm/games/settings.tsv is named there or in the settings-file
table, so the settings window, the sidebar and env.txt stay documented together. No Mac needed: it reads the sources."""
from pathlib import Path
import re
import unittest

REPO = Path(__file__).resolve().parents[3]
SOURCES = ['dm/host/front_mac.m', 'dm/host/quick_settings_mac.swift', 'dm/host/cheats_host.c']
NOT_SETTINGS = {'DMQuickSettings.section'}   # which sidebar section is open: remembered, not a setting


def saved_keys():
    keys = set()
    for f in SOURCES:
        src = (REPO / f).read_text()
        keys |= {f'DMQuickSettings.{w}' for w in re.findall(r'(?:opt_key\(@|optKey\()"(\w+)"', src)}
        keys |= {f'DMPresentFilter.{w}' for w in re.findall(r'(?:pfx_key\(@|pfxKey\()"(\w+)"', src)}
        keys |= {f'DMQuickSettings.{w}' for w in re.findall(r'"DMQuickSettings\.(\w+)\." DM_GAME_NAME', src)}
        keys |= set(re.findall(r'"(launcher\.DM_\w+)"', src))
    return keys - NOT_SETTINGS


class QuickSettingsTable(unittest.TestCase):
    def setUp(self):
        doc = (REPO / 'docs/settings.md').read_text()
        m = re.search(r'^## Quick settings on the Mac\n(.*?)^## ', doc, re.S | re.M)
        self.assertIsNotNone(m, 'docs/settings.md has no "Quick settings on the Mac" section')
        assert m is not None
        self.table, self.doc = m.group(1), doc

    def test_every_saved_key_is_in_the_table(self):
        keys = saved_keys()
        self.assertGreater(len(keys), 10, 'found too few keys: the patterns no longer match the sources')
        missing = sorted(k for k in keys if f'`{k}.<game>`' not in self.table and f'`{k}`' not in self.table)
        self.assertEqual(missing, [], 'saved by the Mac app but not in docs/settings.md, Quick settings on the Mac')

    def test_every_mac_setting_is_documented(self):
        rows = [ln.split('\t') for ln in (REPO / 'dm/games/settings.tsv').read_text().splitlines() if ln.startswith('DM_')]
        mac = [r[0] for r in rows if len(r) > 4 and r[4] != 'platform:ios']
        missing = [v for v in mac if f'`{v}`' not in self.doc]
        self.assertEqual(missing, [], 'Mac settings (dm/games/settings.tsv) named nowhere in docs/settings.md')


if __name__ == '__main__':
    unittest.main()
