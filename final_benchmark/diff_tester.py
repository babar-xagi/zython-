#!/usr/bin/env python3
"""Differential correctness tester: Zython vs CPython.

Every snippet runs in its OWN process on both interpreters. stdout is compared
byte-for-byte (CPython is the oracle). Results go to results/correctness.json.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ZY = os.path.join(HERE, "..", "zig-out", "bin", "zython")
PY = sys.executable
TMP = os.path.join(HERE, "results", "_snippets")
os.makedirs(TMP, exist_ok=True)

# (category, name, program)  -- expressions are wrapped as print(expr)
def E(cat, name, expr):
    pre = ""
    if "math." in expr:
        pre += "import math\n"
    if "sys." in expr:
        pre += "import sys\n"
    return (cat, name, pre + "print(" + expr + ")\n")

S = []
# ---------------- integer / arithmetic semantics ----------------
S += [
    E("arith", "floordiv_neg", "-7 // 2"),
    E("arith", "mod_neg", "-7 % 3"),
    E("arith", "mod_neg_divisor", "7 % -3"),
    E("arith", "pow_basic", "2 ** 10"),
    E("arith", "pow_neg_exp", "2 ** -1"),
    E("arith", "pow_mod3", "pow(3, 200, 1000007)"),
    E("arith", "pow_mod_big", "pow(2, 1000, 10 ** 9 + 7)"),
    E("arith", "divmod", "divmod(17, 5)"),
    E("arith", "divmod_neg", "divmod(-17, 5)"),
    E("arith", "bitops", "(5 & 3, 5 | 3, 5 ^ 3, 1 << 10, 1024 >> 3)"),
    E("arith", "bit_not", "~5"),
    E("arith", "bit_length", "(255).bit_length()"),
    E("arith", "int_div_float", "10 // 3.0"),
    E("arith", "float_floordiv", "7.5 // 2"),
    E("arith", "float_mod", "7.5 % 2"),
    E("arith", "float_mod_neg", "-7.5 % 2"),
    E("arith", "true_div", "7 / 2"),
    E("arith", "true_div_exact", "6 / 3"),
    E("arith", "int_float_eq", "1 == 1.0"),
    E("arith", "abs_float", "abs(-3.5)"),
    E("arith", "round_banker", "(round(0.5), round(1.5), round(2.5))"),
    E("arith", "round_digits", "round(2.675, 2)"),
    E("arith", "int_from_str", "int('123') + int(4.9)"),
    E("arith", "int_neg_trunc", "int(-4.9)"),
    E("arith", "hex_bin_oct", "(hex(255), bin(5), oct(8))"),
    E("arith", "ord_chr", "(ord('a'), chr(98))"),
    E("arith", "min_max", "(min(3, 1, 2), max([3, 1, 2]))"),
    E("arith", "sum_list", "sum([1, 2, 3])"),
    E("arith", "sum_genexp", "sum(i * i for i in range(10))"),
]
# ---------------- integer overflow / bignum ----------------
S += [
    E("bignum", "add_overflow", "9223372036854775807 + 1"),
    E("bignum", "mul_overflow", "3037000500 * 3037000500"),
    E("bignum", "mul_overflow2", "9223372036854775807 * 2"),
    E("bignum", "sub_overflow", "-9223372036854775807 - 10"),
    E("bignum", "neg_overflow", "-(-9223372036854775807 - 1)"),
    E("bignum", "pow_big", "2 ** 100"),
    E("bignum", "pow_big_mul", "2 ** 100 * 3"),
    E("bignum", "pow_1000_digits", "len(str(3 ** 1000))"),
    E("bignum", "factorial_25", "math.factorial(25)"),
    ("bignum", "factorial_loop_30", "f = 1\nfor i in range(1, 31):\n    f *= i\nprint(f)\n"),
    ("bignum", "fib_big_loop", "a, b = 0, 1\nfor _ in range(200):\n    a, b = b, a + b\nprint(a)\n"),
    ("bignum", "accumulate_overflow", "x = 1\nfor i in range(70):\n    x = x * 2\nprint(x)\n"),
    ("bignum", "accumulate_add_overflow", "x = 9223372036854775000\nfor i in range(1000):\n    x += 1\nprint(x)\n"),
    E("bignum", "big_floordiv", "(10 ** 30) // 7"),
    E("bignum", "big_mod", "(10 ** 30) % 97"),
    E("bignum", "big_cmp", "10 ** 30 > 10 ** 29"),
    E("bignum", "big_str_to_int", "int('123456789012345678901234567890') + 1"),
    E("bignum", "sys_maxsize", "sys.maxsize"),
]
# ---------------- floats / math ----------------
S += [
    E("float", "float_add_repr", "0.1 + 0.2"),
    E("float", "float_big_str", "str(1e16)"),
    E("float", "float_small_str", "str(1e-5)"),
    E("float", "float_long_repr", "str(123456789.123456789)"),
    E("float", "float_third", "1 / 3"),
    E("float", "float_int_valued", "float(3)"),
    E("float", "float_inf", "float('inf') > 10 ** 18"),
    E("float", "float_nan_ne", "float('nan') == float('nan')"),
    E("float", "math_sqrt", "math.sqrt(2)"),
    E("float", "math_floor_ceil", "(math.floor(2.7), math.ceil(2.1))"),
    E("float", "math_sin", "math.sin(0.5)"),
    E("float", "math_cos", "math.cos(0.5)"),
    E("float", "math_exp", "math.exp(1)"),
    E("float", "math_log", "math.log(10)"),
    E("float", "math_log2", "math.log2(8)"),
    E("float", "math_atan2", "math.atan2(1, 2)"),
    E("float", "math_hypot", "math.hypot(3, 4)"),
    E("float", "math_gcd", "math.gcd(12, 18)"),
    E("float", "math_isqrt", "math.isqrt(99)"),
    E("float", "math_pi", "math.pi"),
    E("float", "math_fabs_pow", "math.pow(2, 0.5)"),
    E("float", "format_2f", "f'{3.14159:.2f}'"),
    E("float", "format_pad", "f'{42:>8}|{42:<8}|{42:08d}'"),
    E("float", "format_pct", "'%5.1f|%d|%s' % (3.14159, 5, 'x')"),
    E("float", "format_comma", "f'{1234567:,}'"),
]
# ---------------- strings ----------------
S += [
    E("string", "methods_basic", "'Hello'.lower() + 'hello'.upper() + ' a b '.strip()"),
    E("string", "join_split", "'-'.join('a b c'.split())"),
    E("string", "split_sep", "'a,b,,c'.split(',')"),
    E("string", "in_str", "'ell' in 'hello'"),
    E("string", "reverse", "'abc'[::-1]"),
    E("string", "mul", "'ab' * 3"),
    E("string", "find_replace", "('abcabc'.find('c'), 'abcabc'.replace('b', 'X'))"),
    E("string", "startswith", "('hello'.startswith('he'), 'hello'.endswith('lo'))"),
    E("string", "isdigit_isalpha", "('123'.isdigit(), 'abc'.isalpha())"),
    E("string", "str_format", "'{}-{}'.format(1, 2)"),
    E("string", "str_format_named", "'{a}-{b}'.format(a=1, b=2)"),
    E("string", "fstring_expr", "f'{3}+{4}={3 + 4}'"),
    E("string", "repr_quotes", "repr(\"it's\")"),
    E("string", "str_list", "str([1, 'a', None, True, 2.5])"),
    E("string", "str_dict", "str({'a': 1, 2: [3]})"),
    E("string", "str_tuple1", "str((1,))"),
    E("string", "count_str", "'banana'.count('an')"),
    E("string", "center_zfill", "('ab'.center(6, '*'), '42'.zfill(5))"),
    E("string", "title_cap", "('hello world'.title(), 'hello'.capitalize())"),
    E("string", "unicode_len", "len('héllo')"),
    E("string", "unicode_upper", "'héllo'.upper()"),
    E("string", "slice_step", "'abcdef'[::2]"),
    E("string", "cmp", "'abc' < 'abd'"),
    E("string", "ljust_rjust", "('a'.ljust(3, '.'), 'a'.rjust(3, '.'))"),
    E("string", "partition", "'a=b=c'.partition('=')"),
    E("string", "splitlines", "'a\\nb\\nc'.splitlines()"),
    E("string", "strip_chars", "'xxhixx'.strip('x')"),
    E("string", "encode", "'abc'.encode()"),
]
# ---------------- containers ----------------
S += [
    E("container", "list_add_mul", "([1, 2] + [3], [0] * 3)"),
    E("container", "list_2d", "[[0] * 2 for _ in range(2)]"),
    E("container", "slice_basic", "[1, 2, 3, 4, 5][1:4]"),
    E("container", "slice_neg_step", "[1, 2, 3, 4, 5][::-1]"),
    E("container", "slice_neg_idx", "[1, 2, 3, 4, 5][-2:]"),
    E("container", "list_index_count", "([1, 2, 2].index(2), [1, 2, 2].count(2))"),
    ("container", "list_methods", "l = [3, 1, 2]\nl.append(5)\nl.extend([9, 8])\nl.insert(0, 7)\nl.remove(1)\nx = l.pop()\nl.sort()\nl.reverse()\nprint(l, x)\n"),
    ("container", "list_slice_assign", "l = [1, 2, 3, 4]\nl[1:3] = [9, 9, 9]\nprint(l)\n"),
    ("container", "list_del", "l = [1, 2, 3, 4]\ndel l[1]\nprint(l)\n"),
    E("container", "sorted_key", "sorted([3, 1, 2], key=lambda x: -x)"),
    E("container", "sorted_rev", "sorted([3, 1, 2], reverse=True)"),
    E("container", "sorted_str", "sorted(['b', 'a', 'C'])"),
    E("container", "sorted_stable", "sorted([(1, 'b'), (0, 'z'), (1, 'a')], key=lambda t: t[0])"),
    E("container", "enumerate_start", "list(enumerate('ab', 1))"),
    E("container", "zip3", "list(zip([1, 2], [3, 4], [5, 6]))"),
    E("container", "reversed", "list(reversed([1, 2, 3]))"),
    E("container", "map_filter", "list(map(lambda x: x + 1, filter(lambda x: x > 1, [1, 2, 3])))"),
    E("container", "any_all", "(any([0, 1]), all([1, 0]))"),
    E("container", "tuple_cmp", "(1, 2) < (1, 3)"),
    E("container", "list_cmp", "[1, 2] == [1, 2]"),
    E("container", "dict_get", "{'a': 1}.get('b', 9)"),
    E("container", "dict_items", "sorted({'a': 1, 'b': 2}.items())"),
    E("container", "dict_order", "list({'b': 1, 'a': 2}.keys())"),
    E("container", "dict_comp", "{k: k * k for k in range(3)}"),
    ("container", "dict_mutation", "d = {}\nfor i in range(5):\n    d[i] = i * i\ndel d[2]\nd.update({9: 1})\nprint(d, len(d), d.pop(3), 9 in d)\n"),
    ("container", "dict_setdefault", "d = {}\nd.setdefault('a', []).append(1)\nd.setdefault('a', []).append(2)\nprint(d)\n"),
    ("container", "dict_tuple_key", "d = {(1, 2): 'a'}\nprint(d[(1, 2)])\n"),
    ("container", "dict_str_keys_many", "d = {}\nfor i in range(1000):\n    d['k' + str(i)] = i\nprint(sum(d.values()), len(d))\n"),
    E("container", "set_ops", "sorted({1, 2, 3} | {3, 4}), sorted({1, 2, 3} & {2, 3, 9}), sorted({1, 2, 3} - {2})"),
    E("container", "set_dedupe", "sorted(set([3, 1, 3, 2]))"),
    E("container", "set_comp", "sorted({x % 3 for x in range(10)})"),
    E("container", "list_comp_cond", "[x * 2 for x in range(5) if x % 2 == 0]"),
    E("container", "list_comp_nested", "[(i, j) for i in range(2) for j in range(2)]"),
    E("container", "tuple_unpack_star", "(lambda a, *b: (a, b))(1, 2, 3)"),
    ("container", "unpack_star_assign", "a, *b, c = [1, 2, 3, 4, 5]\nprint(a, b, c)\n"),
    ("container", "swap", "a, b = 1, 2\na, b = b, a\nprint(a, b)\n"),
    E("container", "max_key", "max(['aa', 'b', 'cccc'], key=len)"),
    E("container", "list_of_lists_alias", "(lambda a: (a.append(1), a)[1])([[]] * 2)"),
    E("container", "range_len_index", "(len(range(10)), range(10)[3], list(range(10, 0, -3)))"),
    ("container", "deque_like_pop0", "l = list(range(5))\nl.pop(0)\nprint(l)\n"),
]
# ---------------- control flow / functions / classes ----------------
S += [
    E("control", "chained_cmp", "1 < 2 < 3"),
    E("control", "and_or", "(0 or 5, 3 and 4)"),
    E("control", "ternary", "1 if 0 else 2"),
    E("control", "walrus", "((y := 5) + y)"),
    ("control", "while_else", "i = 0\nwhile i < 3:\n    i += 1\nelse:\n    print('else', i)\n"),
    ("control", "for_else_break", "for i in range(5):\n    if i == 3:\n        break\nelse:\n    print('no')\nprint(i)\n"),
    ("control", "continue", "s = 0\nfor i in range(10):\n    if i % 2:\n        continue\n    s += i\nprint(s)\n"),
    ("control", "nested_break", "c = 0\nfor i in range(5):\n    for j in range(5):\n        if j > i:\n            break\n        c += 1\nprint(c)\n"),
    ("control", "try_except_finally", "try:\n    1 // 0\nexcept ZeroDivisionError as e:\n    print('zde', e)\nfinally:\n    print('fin')\n"),
    ("control", "try_else", "try:\n    x = 1\nexcept Exception:\n    print('no')\nelse:\n    print('else')\n"),
    ("control", "raise_custom", "class E(Exception):\n    pass\ntry:\n    raise E('boom')\nexcept E as e:\n    print('caught', e)\n"),
    ("control", "indexerror", "try:\n    [][1]\nexcept IndexError:\n    print('ie')\n"),
    ("control", "keyerror", "try:\n    {}['k']\nexcept KeyError:\n    print('ke')\n"),
    ("control", "valueerror", "try:\n    int('x')\nexcept ValueError:\n    print('ve')\n"),
    ("control", "typeerror", "try:\n    1 + 'a'\nexcept TypeError:\n    print('te')\n"),
    ("control", "assert_fail", "try:\n    assert 1 == 2, 'msg'\nexcept AssertionError as e:\n    print('ae', e)\n"),
    ("control", "defaults_args_kwargs", "def f(a, b=2, *args, **kw):\n    return a + b + len(args) + len(kw)\nprint(f(1, 2, 3, 4, z=1))\n"),
    ("control", "kwonly", "def f(a, *, b=1):\n    return a + b\nprint(f(1, b=5))\n"),
    ("control", "closure_nonlocal", "def outer():\n    c = 0\n    def inc():\n        nonlocal c\n        c += 1\n        return c\n    inc()\n    return inc()\nprint(outer())\n"),
    ("control", "global_stmt", "x = 10\ndef g():\n    global x\n    x = 20\ng()\nprint(x)\n"),
    ("control", "closure_loop_capture", "fs = [lambda i=i: i for i in range(3)]\nprint([f() for f in fs])\n"),
    ("control", "recursion_900", "def deep(n):\n    if n == 0:\n        return 0\n    return 1 + deep(n - 1)\nprint(deep(900))\n"),
    ("control", "recursion_limit_error", "def deep(n):\n    return 1 + deep(n + 1)\ntry:\n    deep(0)\nexcept RecursionError:\n    print('recursion error')\n"),
    ("control", "generator", "def gen(n):\n    for i in range(n):\n        yield i * i\nprint(list(gen(4)))\n"),
    ("control", "generator_send_next", "def g():\n    yield 1\n    yield 2\nit = g()\nprint(next(it), next(it))\n"),
    ("control", "generator_expr_lazy", "g = (x * 2 for x in range(3))\nprint(next(g), list(g))\n"),
    ("control", "yield_from", "def a():\n    yield from [1, 2]\n    yield 3\nprint(list(a()))\n"),
    ("control", "decorator", "def deco(f):\n    def w(*a):\n        return f(*a) + 1\n    return w\n@deco\ndef g(x):\n    return x\nprint(g(1))\n"),
    ("control", "with_ctx", "class C:\n    def __enter__(self):\n        print('in')\n        return self\n    def __exit__(self, *a):\n        print('out')\nwith C():\n    print('body')\n"),
    ("control", "lambda_default", "print((lambda a, b=3: a + b)(1))\n"),
    ("control", "match_stmt", "x = 2\nmatch x:\n    case 1:\n        print('one')\n    case 2:\n        print('two')\n    case _:\n        print('other')\n"),
    ("control", "star_call", "def f(a, b):\n    return a - b\nprint(f(*[5, 2]), f(**{'a': 9, 'b': 1}))\n"),
    ("control", "string_in_loop_build", "s = ''\nfor i in range(100):\n    s += str(i)\nprint(len(s))\n"),
    ("control", "many_locals", "a1=1;a2=2;a3=3;a4=4;a5=5;a6=6;a7=7;a8=8;a9=9;a10=10\nfor i in range(3):\n    a9 = i\n    a10 += a9\nprint(a9, a10)\n"),
    ("control", "int_attr_aug", "class C:\n    def __init__(self):\n        self.n = 0\nc = C()\nfor i in range(5):\n    c.n += i\nprint(c.n)\n"),
]
CLS = """
class P:
    def __init__(self, x):
        self.x = x
    def __add__(self, o):
        return P(self.x + o.x)
    def __repr__(self):
        return 'P(' + str(self.x) + ')'
    def __eq__(self, o):
        return self.x == o.x
    def __lt__(self, o):
        return self.x < o.x
    def __len__(self):
        return self.x
    def __getitem__(self, i):
        return self.x + i
    def __hash__(self):
        return hash(self.x)
class Q(P):
    def __init__(self, x):
        super().__init__(x)
        self.y = 1
    def who(self):
        return 'Q'
"""
S += [
    ("oop", "dunder_add", CLS + "print((P(1) + P(2)).x)\n"),
    ("oop", "dunder_repr", CLS + "print(repr(P(1)), [P(2)])\n"),
    ("oop", "dunder_eq_lt", CLS + "print(P(1) == P(1), P(1) < P(2), sorted([P(3), P(1)]))\n"),
    ("oop", "dunder_len_getitem", CLS + "print(len(P(4)), P(4)[2])\n"),
    ("oop", "dunder_hash_dict", CLS + "d = {P(1): 'a'}\nprint(d[P(1)])\n"),
    ("oop", "super_init", CLS + "q = Q(3)\nprint(q.x, q.y, q.who(), isinstance(q, P))\n"),
    ("oop", "class_attr", "class C:\n    n = 5\n    def m(self):\n        return self.n\nprint(C().m(), C.n)\n"),
    ("oop", "staticmethod", "class C:\n    @staticmethod\n    def f(x):\n        return x + 1\nprint(C.f(1))\n"),
    ("oop", "classmethod", "class C:\n    k = 3\n    @classmethod\n    def f(cls):\n        return cls.k\nprint(C.f())\n"),
    ("oop", "property", "class C:\n    def __init__(self):\n        self._v = 4\n    @property\n    def v(self):\n        return self._v * 2\nprint(C().v)\n"),
    ("oop", "str_dunder", "class C:\n    def __str__(self):\n        return 'cee'\nprint(str(C()), f'{C()}')\n"),
    ("oop", "default_obj_repr_prefix", "class C:\n    pass\nprint(repr(C())[:10])\n"),
    ("oop", "getattr_setattr", "class C:\n    pass\nc = C()\nsetattr(c, 'a', 3)\nprint(getattr(c, 'a'), hasattr(c, 'b'))\n"),
    ("oop", "multi_inherit", "class A:\n    def f(self):\n        return 'A'\nclass B:\n    def g(self):\n        return 'B'\nclass C(A, B):\n    pass\nprint(C().f() + C().g())\n"),
    ("oop", "iter_protocol", "class It:\n    def __init__(self):\n        self.i = 0\n    def __iter__(self):\n        return self\n    def __next__(self):\n        self.i += 1\n        if self.i > 3:\n            raise StopIteration\n        return self.i\nprint(list(It()))\n"),
    ("oop", "dunder_call", "class C:\n    def __call__(self, x):\n        return x * 2\nprint(C()(4))\n"),
    ("oop", "dunder_contains_bool", "class C:\n    def __contains__(self, x):\n        return x == 1\n    def __bool__(self):\n        return False\nprint(1 in C(), bool(C()))\n"),
    ("oop", "slots_dataclass_like", "class C:\n    __slots__ = ('a',)\n    def __init__(self):\n        self.a = 1\nprint(C().a)\n"),
    ("oop", "type_name", "print(type(3).__name__, type('a').__name__, type([]).__name__)\n"),
    ("oop", "isinstance_tuple", "print(isinstance(3, (str, int)), isinstance(True, int))\n"),
]
# ---------------- stdlib ----------------
S += [
    ("stdlib", "import_json", "import json\nprint(json.dumps({'a': [1, 2, None, True], 'b': 1.5}))\nprint(json.loads('{\"a\": [1, 2, {\"b\": null}]}'))\n"),
    ("stdlib", "import_random_seed", "import random\nrandom.seed(42)\nprint(random.random())\n"),
    ("stdlib", "import_collections", "from collections import Counter, defaultdict, deque\nprint(Counter('aabbbc').most_common(1))\n"),
    ("stdlib", "import_itertools", "import itertools\nprint(list(itertools.permutations([1, 2, 3]))[:2])\n"),
    ("stdlib", "import_functools", "import functools\nprint(functools.reduce(lambda a, b: a + b, [1, 2, 3]))\n"),
    ("stdlib", "import_re", "import re\nprint(re.findall(r'\\d+', 'a12b345'))\n"),
    ("stdlib", "import_heapq", "import heapq\nh = [5, 1, 3]\nheapq.heapify(h)\nprint(heapq.heappop(h))\n"),
    ("stdlib", "import_bisect", "import bisect\nprint(bisect.bisect_left([1, 2, 4], 3))\n"),
    ("stdlib", "import_string", "import string\nprint(string.ascii_lowercase[:3])\n"),
    ("stdlib", "import_hashlib", "import hashlib\nprint(hashlib.sha256(b'abc').hexdigest())\n"),
    ("stdlib", "import_hashlib_md5", "import hashlib\nprint(hashlib.md5(b'abc').hexdigest())\n"),
    ("stdlib", "import_os_path", "import os\nprint(os.path.join('a', 'b'))\n"),
    ("stdlib", "import_time", "import time\nprint(time.time() > 0)\n"),
    ("stdlib", "import_threading", "import threading\nr = []\nt = threading.Thread(target=lambda: r.append(1))\nt.start()\nt.join()\nprint(r)\n"),
    ("stdlib", "import_asyncio", "import asyncio\nasync def f():\n    return 5\nprint(asyncio.run(f()))\n"),
    ("stdlib", "import_dataclasses", "from dataclasses import dataclass\n@dataclass\nclass C:\n    a: int\nprint(C(1).a)\n"),
    ("stdlib", "import_typing", "from typing import List\ndef f(x: List[int]) -> int:\n    return sum(x)\nprint(f([1, 2]))\n"),
    ("stdlib", "file_io", "f = open('/tmp/_zy_probe.txt', 'w')\nf.write('hi\\nthere\\n')\nf.close()\nprint(open('/tmp/_zy_probe.txt').read().split())\n"),
    ("stdlib", "sys_argv_len", "import sys\nprint(len(sys.argv) >= 1)\n"),
    ("stdlib", "print_sep_end", "print(1, 2, 3, sep='-', end='!\\n')\n"),
    ("stdlib", "print_file_stderr", "import sys\nprint('x', file=sys.stderr)\nprint('ok')\n"),
    ("stdlib", "input_absent", "print(type(input).__name__)\n"),
    ("stdlib", "bytes_ops", "b = b'abc'\nprint(len(b), b[0], list(b))\n"),
    ("stdlib", "complex_num", "print(complex(1, 2) * complex(0, 1))\n"),
    ("stdlib", "fractions", "from fractions import Fraction\nprint(Fraction(1, 3) + Fraction(1, 6))\n"),
    ("stdlib", "decimal", "from decimal import Decimal\nprint(Decimal('0.1') + Decimal('0.2'))\n"),
    ("stdlib", "statistics", "import statistics\nprint(statistics.mean([1, 2, 3, 4]))\n"),
    ("stdlib", "array_module", "import array\nprint(array.array('i', [1, 2])[1])\n"),
]

# ----------------------------------------------------------------------------

def run(exe, path):
    try:
        p = subprocess.run([exe, path], capture_output=True, timeout=20, text=True, errors="replace")
        return p.returncode, p.stdout, p.stderr.strip()[-300:]
    except subprocess.TimeoutExpired:
        return -999, "", "TIMEOUT"


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    out = []
    counts = {}
    for cat, name, prog in S:
        if only and cat != only:
            continue
        path = os.path.join(TMP, cat + "__" + name + ".py")
        with open(path, "w") as fh:
            fh.write(prog)
        prc, pout, perr = run(PY, path)
        zrc, zout, zerr = run(ZY, path)
        if prc != 0:
            status = "ORACLE_ERR"
        elif zrc < 0 or zrc >= 128:
            status = "CRASH"
        elif zrc != 0:
            status = "ZY_ERROR"
        elif zout == pout:
            status = "PASS"
        else:
            status = "WRONG"
        counts.setdefault(cat, {}).setdefault(status, 0)
        counts[cat][status] += 1
        out.append({"cat": cat, "name": name, "status": status,
                    "program": prog, "cpython_out": pout[:400], "zython_out": zout[:400],
                    "zython_rc": zrc, "zython_err": zerr, "cpython_err": perr})
        mark = {"PASS": ".", "WRONG": "W", "ZY_ERROR": "E", "CRASH": "C", "ORACLE_ERR": "O"}[status]
        print(mark, end="", flush=True)
    print()
    with open(os.path.join(HERE, "results", "correctness.json"), "w") as fh:
        json.dump({"results": out, "counts": counts}, fh, indent=1)
    tot = sum(sum(v.values()) for v in counts.values())
    ok = sum(v.get("PASS", 0) for v in counts.values())
    print("TOTAL", tot, "PASS", ok)
    for cat, v in counts.items():
        print(cat, v)


if __name__ == "__main__":
    main()
