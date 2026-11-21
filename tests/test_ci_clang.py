"""scripts/ci_clang.py: which clang commands are split into cached one-file compiles, and how. No compiler needed."""
from pathlib import Path
import importlib.util
import unittest

REPO = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ci_clang', REPO / 'scripts/ci_clang.py')
assert spec and spec.loader
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)


class Split(unittest.TestCase):
    def test_test_binary_command(self):
        args = ['-O1', '-g', '-I../nvn/include', '-fobjc-arc', '-o', 't_x', 't_x.m', '../nvn/hle_nvn.c',
                '-framework', 'Metal', '-lz', 'libvpx.a']
        flags, sources, link, out = cc.split(args)
        self.assertEqual(flags, ['-O1', '-g', '-I../nvn/include', '-fobjc-arc'])
        self.assertEqual(sources, ['t_x.m', '../nvn/hle_nvn.c'])
        self.assertEqual(link, ['-framework', 'Metal', '-lz', 'libvpx.a'])
        self.assertEqual(out, 't_x')

    def test_left_alone(self):
        self.assertIsNone(cc.split(['-c', 'a.c', '-o', 'a.o']))           # already one file
        self.assertIsNone(cc.split(['-o', 't', 'a.c']))                   # one source
        self.assertIsNone(cc.split(['-E', 'a.c', 'b.c', '-o', 'x']))      # preprocess
        self.assertIsNone(cc.split(['a.c', 'b.c']))                       # no -o: a.out next to the call
        self.assertIsNone(cc.split(['-x', 'c', '-o', 't', 'a', 'b.c']))   # a language override


if __name__ == '__main__':
    unittest.main()
