"""dmsh_build.py finish_all (NXForge): a paired vertex shader starts only after the pixel shaders of it built in this run, without waiting for every other shader;
the shaders to compile go before cache hits; the results come back in the order of the two phases before (unpaired in key order, then paired)."""
import ast
import collections
import heapq
from pathlib import Path
import random
import threading
import time
import unittest

TOOLS = Path(__file__).resolve().parents[1] / 'tools'


def finish_all_with(fin, pairs, hits, nj=4):
    tree = ast.parse((TOOLS / 'dmsh_build.py').read_text())
    fn = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'finish_all']
    ns = dict(heapq=heapq, collections=collections, threading=threading, PAIRS=pairs, cache_hits=hits, NJ=nj, fin=fin)
    exec(compile(ast.Module(body=fn, type_ignores=[]), str(TOOLS / 'dmsh_build.py'), 'exec'), ns)
    return ns['finish_all']


class FinishOrder(unittest.TestCase):
    def setUp(self):
        self.keys = [f'k{i:03d}' for i in range(240)]
        self.pairs = collections.defaultdict(set)
        for i in range(0, 240, 4): self.pairs[self.keys[i]] = {self.keys[i + 1], self.keys[(i + 2) % 240], 'not-built'}
        self.hits = {k for i, k in enumerate(self.keys) if i % 5 == 0}

    def test_pairs_wait_for_their_pixel_shaders_only(self):
        done, lock, started = set(), threading.Lock(), []
        def fin(k):
            with lock:
                started.append(k)
                for p in self.pairs.get(k, ()):
                    if p in self.keys and k not in self.pairs.get(p, ()): self.assertIn(p, done, f'{k} started before its pixel shader {p}')
            time.sleep(random.random() / 2000)
            with lock: done.add(k)
            return (k, 'ok', '', None)
        res = finish_all_with(fin, self.pairs, self.hits)(self.keys)
        unpaired = [k for k in self.keys if k not in self.pairs]; paired = [k for k in self.keys if k in self.pairs]
        self.assertEqual([r[0] for r in res], unpaired + paired)
        self.assertLess(min(started.index(k) for k in paired), max(started.index(k) for k in unpaired), 'paired shaders waited for every unpaired one')

    def test_compiles_before_cache_hits(self):
        order = []
        def fin(k): order.append(k); return (k, 'ok', '', None)
        finish_all_with(fin, collections.defaultdict(set), self.hits, nj=1)(self.keys)
        self.assertEqual(order, [k for k in self.keys if k not in self.hits] + [k for k in self.keys if k in self.hits])

    def test_a_failure_stops_the_others(self):
        def fin(k):
            if k == 'k010': raise ValueError('broken')
            return (k, 'ok', '', None)
        with self.assertRaises(ValueError): finish_all_with(fin, self.pairs, self.hits)(self.keys)


if __name__ == '__main__':
    unittest.main()
