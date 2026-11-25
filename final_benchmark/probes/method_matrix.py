"""Runs under CPython only: for each method call snippet, run it on zython in a separate process and report availability."""
import subprocess, sys, os
ZY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "zig-out", "bin", "zython")
snips = {
 "list": ["[1,2].append(3)", "[1,2].extend([3])", "[1,2].insert(0,5)", "[1,2].remove(1)", "[1,2].pop()", "[1,2].pop(0)", "[2,1].sort()",
          "[1,2].reverse()", "[1,2].index(2)", "[1,2].count(1)", "[1,2].copy()", "[1,2].clear()"],
 "str": ["'a'.upper()", "'A'.lower()", "' a '.strip()", "' a '.lstrip()", "' a '.rstrip()", "'a b'.split()", "'a,b'.split(',')", "','.join(['a'])",
         "'abc'.find('b')", "'abc'.replace('a','b')", "'abc'.startswith('a')", "'abc'.endswith('c')", "'12'.isdigit()", "'ab'.isalpha()",
         "'a'.count('a')", "'a'.title()", "'a'.capitalize()", "'a'.center(5)", "'a'.ljust(5)", "'a'.rjust(5)", "'a'.zfill(5)", "'a=b'.partition('=')",
         "'a\\nb'.splitlines()", "'{}'.format(1)", "'a'.encode()", "'abc'.index('b')", "'a'.isupper()", "'a b'.rsplit()"],
 "dict": ["{'a':1}.get('a')", "{'a':1}.keys()", "{'a':1}.values()", "{'a':1}.items()", "{'a':1}.pop('a')", "{'a':1}.update({'b':2})",
          "{'a':1}.setdefault('b',2)", "{'a':1}.copy()", "{'a':1}.clear()", "{'a':1}.popitem()"],
 "set": ["{1}.add(2)", "{1}.remove(1)", "{1}.discard(1)", "{1}|{2}", "{1}&{1}", "{1}-{1}", "sorted({2,1})", "len({1})", "{1}.union({2})", "{1}.issubset({1,2})"],
 "builtin": ["abs(-1)", "min(1,2)", "max(1,2)", "sum([1])", "len([1])", "sorted([2,1])", "sorted([2,1], key=lambda x: x)", "sorted([1,2], reverse=True)",
             "reversed([1])", "enumerate([1])", "zip([1],[2])", "map(str,[1])", "filter(None,[1])", "any([1])", "all([1])", "isinstance(1,int)",
             "isinstance(1,(int,str))", "type(1)", "divmod(5,2)", "pow(2,3)", "pow(2,3,5)", "round(1.5)", "round(1.234,2)", "hex(5)", "bin(5)", "oct(5)",
             "chr(97)", "ord('a')", "int('5')", "float('1.5')", "str(1)", "bool(1)", "list(range(3))", "tuple([1])", "set([1])", "dict(a=1)", "repr(1)",
             "hash(1)", "id(1)", "callable(len)", "getattr(1,'real')", "hasattr(1,'real')", "iter([1])", "next(iter([1]))", "range(3)[1]", "len(range(3))",
             "print(end='')", "input", "open", "complex(1,2)", "bytes([1])", "bytearray(1)", "frozenset([1])", "super", "staticmethod", "classmethod", "property"],
 "math": ["math.sqrt(4)", "math.sin(1)", "math.cos(1)", "math.tan(1)", "math.atan(1)", "math.atan2(1,1)", "math.exp(1)", "math.log(2)", "math.log10(2)", "math.log2(2)",
          "math.pow(2,2)", "math.floor(1.5)", "math.ceil(1.5)", "math.fabs(-1)", "math.gcd(4,6)", "math.factorial(5)", "math.hypot(3,4)", "math.isqrt(9)",
          "math.pi", "math.e", "math.inf", "math.isnan(1.0)", "math.trunc(1.5)", "math.fmod(5,3)", "math.degrees(1)", "math.radians(1)", "math.comb(5,2)"],
 "syntax": ["(lambda *a: a)(1)", "[x for x in range(3) if x]", "{x: x for x in range(3)}", "{x for x in range(3)}", "(x for x in range(3))", "[(i,j) for i in range(2) for j in range(2)]",
            "(y := 3)", "1 if 1 else 2", "not 1", "1 in [1]", "1 not in [1]", "[1,2][::-1]", "'%d' % 5", "f'{1:>3}'", "f'{1.5:.2f}'", "True + 1", "-(-5) // 2", "1 < 2 < 3",
            "(lambda: (yield))", "[*range(3)]", "{**{'a':1}}", "print(*[1,2])", "2 ** 100", "7 // 2", "1_000", "0x10", "0b11", "0o7", "1e3", "3j", "b'a'", "'''a'''", "r'a\\n'"],
}
stmt = {
 "stmt": ["def f():\n    return 1, 2\nf()", "a, b = 1, 2", "a, *b = [1,2,3]", "def f(*, k=1):\n    pass", "def f():\n    x = 1\n    def g():\n        nonlocal x\n        x = 2\n    g()\nf()",
          "class A:\n    @staticmethod\n    def f():\n        return 1\nA.f()", "class A:\n    @property\n    def p(self):\n        return 1\nA().p", "class A:\n    def __init__(self):\n        pass\nclass B(A):\n    def __init__(self):\n        super().__init__()\nB()",
          "class A:\n    def __add__(self, o):\n        return 1\nA() + A()", "class A:\n    def __repr__(self):\n        return 'x'\nrepr(A())", "class A:\n    def __len__(self):\n        return 3\nlen(A())",
          "class A:\n    def __getitem__(self, i):\n        return i\nA()[1]", "class A:\n    def __eq__(self, o):\n        return True\nA() == A()", "class A:\n    def __iter__(self):\n        return iter([1])\nlist(A())",
          "class A:\n    def __call__(self):\n        return 1\nA()()", "class A:\n    def __str__(self):\n        return 'x'\nstr(A())", "class E(Exception):\n    pass\nraise E('x')", "try:\n    raise ValueError('x')\nexcept ValueError as e:\n    pass",
          "try:\n    int('x')\nexcept ValueError:\n    pass", "try:\n    pass\nfinally:\n    pass", "assert True", "with open('/dev/null') as f:\n    pass", "del [1][0:0]", "x = [1,2]\ndel x[0]", "x=[1,2,3]\nx[0:2] = [9]",
          "global_x = 1\ndef f():\n    global global_x\n    global_x = 2\nf()", "import collections", "import itertools", "import functools", "import re", "import string", "import heapq", "import bisect", "import typing", "import dataclasses",
          "import os", "import sys", "import json", "import random", "import hashlib", "import time", "import threading", "import asyncio", "import socket", "import ctypes", "import math", "import fractions", "import decimal", "import statistics", "import array", "import copy", "import operator", "import abc", "import enum", "import pathlib", "import datetime", "import struct", "import io", "import csv", "import subprocess", "import argparse", "import logging", "import unittest", "import queue", "import multiprocessing",
          "match 1:\n    case 1:\n        pass", "async def f():\n    pass", "x = lambda: 1", "def g():\n    yield 1\nlist(g())", "def g():\n    yield from [1]\nlist(g())", "@(lambda f: f)\ndef f():\n    pass",
          "x = 5\nx += 1\nx -= 1\nx *= 2\nx //= 2\nx %= 3\nx **= 2\nx <<= 1\nx >>= 1\nx |= 1\nx &= 1\nx ^= 1", "for i in range(3):\n    pass\nelse:\n    pass", "while False:\n    pass\nelse:\n    pass", "print(1, file=None)",
          "x = 1 if True else 2", "a = b = 1", "print(__name__)", "if __name__ == '__main__':\n    pass"],
}
def zy_ok(code):
    p = subprocess.run([ZY, "-c", code], capture_output=True, text=True, timeout=20)
    return p.returncode == 0 and "Error" not in p.stderr

def py_ok(code):
    import io, contextlib
    pre = "import math\n"
    try:
        r = subprocess.run([sys.executable, "-c", pre + code], capture_output=True, text=True, timeout=20)
        return r.returncode == 0
    except Exception:
        return False

missing = {}
total = 0
okc = 0
for cat, items in list(snips.items()) + list(stmt.items()):
    for s in items:
        code = s if cat in ("stmt",) else ("import math\nx = " + s + "\n")
        total_py = py_ok(code)
        if not total_py:
            continue
        total += 1
        if zy_ok(code):
            okc += 1
        else:
            missing.setdefault(cat, []).append(s.replace("\n", "\\n"))
print("Features valid in CPython probed:", total, " supported by Zython:", okc, " unsupported:", total - okc)
for cat, v in missing.items():
    print("\n[%s] %d unsupported:" % (cat, len(v)))
    for s in v:
        print("   ", s[:110])
