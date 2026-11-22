"""scripts/layer.py carried: which patches carry nxnative work, read from file names and patch headers. No network."""
from pathlib import Path
import importlib.util
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('layer', REPO / 'scripts/layer.py')
assert spec and spec.loader
layer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(layer)

HEADER = """From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001
Subject: a fix

Forwarded upstream as seedds/nxnative#2101, see also seedds/nxnative/pull/2102.

Origin: seedds/nxnative commit 9b03dee5 (PR #3081), landed after the pin.
---
 dm/x.c | 2 +-

Origin: seedds/nxnative commit deadbeef in the diff body is not read
"""


class CarriedRefs(unittest.TestCase):
    def test_name_and_header(self):
        prs, commits = layer.carried_refs('0040-upstream-pr-3081.patch', HEADER)
        self.assertEqual(prs, [2101, 2102, 3081])
        self.assertEqual(commits, ['9b03dee5'])

    def test_plain_patch_carries_nothing(self):
        self.assertEqual(layer.carried_refs('0012-fstep-stall.patch', 'Subject: x\n\nPR #12 elsewhere\n---\n'), ([], []))

    def test_repo_patches_offline(self):
        """The repository's own patches: every upstream-pr-N file is found, nothing fetched, nothing called droppable."""
        seen = []
        out = layer.carried(offline=True, log=seen.append, state=lambda repo, n: self.fail('no network offline'))
        names = {name for name, ref, _, _ in out if ref.startswith('PR #')}
        for p in layer.patch_files():
            if 'upstream-pr-' in p.name:
                self.assertIn(p.name, names)
        self.assertTrue(all(not drop for _, ref, _, drop in out if ref.startswith('PR #')))
        self.assertTrue(seen)

    def test_merged_pr_is_droppable(self):
        out = layer.carried(offline=False, log=lambda _: None, state=lambda repo, n: 'merged', fetch=False)
        self.assertTrue(any(drop for _, ref, _, drop in out if ref.startswith('PR #')))


if __name__ == '__main__':
    unittest.main()
