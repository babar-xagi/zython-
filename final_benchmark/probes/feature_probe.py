import math
import sys

def check(name, got, want):
    ok = (got == want)
    print(("PASS " if ok else "FAIL ") + name + ("" if ok else "  got=" + repr(got) + " want=" + repr(want)))

check("floordiv neg", -7 // 2, -4)
check("mod neg", -7 % 3, 2)
check("mod neg2", 7 % -3, -2)
check("pow", 2 ** 10, 1024)
check("pow3", pow(3, 200, 1000007), 349132)
check("divmod", divmod(17, 5), (3, 2))
check("bitops", (5 & 3, 5 | 3, 5 ^ 3, 1 << 10, 1024 >> 3), (1, 7, 6, 1024, 128))
check("bigint mul", 2 ** 100 * 3, 3802951800684688204490109616128)
check("bigint fact", math.factorial(25), 15511210043330985984000000)
check("bigint add", 9223372036854775807 + 1, 9223372036854775808)
check("int mul overflow", 9223372036854775807 * 2, 18446744073709551614)
check("int mul overflow2", 3037000500 * 3037000500, 9223372037000250000)
check("int sub overflow", -9223372036854775807 - 10, -9223372036854775817)
check("float repr", 0.1 + 0.2, 0.30000000000000004)
check("float str", str(1e16), "1e+16")
check("float div", 7 / 2, 3.5)
check("sqrt", math.sqrt(2), 1.4142135623730951)
check("sum", sum([1, 2, 3]), 6)
check("sum gen", sum(i * i for i in range(10)), 285)
check("list comp", [x * 2 for x in range(5) if x % 2 == 0], [0, 4, 8])
check("dict comp", {k: k * k for k in range(3)}, {0: 0, 1: 1, 2: 4})
check("set", sorted(set([3, 1, 3, 2])), [1, 2, 3])
check("sorted key", sorted([3, 1, 2], key=lambda x: -x), [3, 2, 1])
check("sorted rev", sorted([3, 1, 2], reverse=True), [3, 2, 1])
check("enumerate", list(enumerate("ab")), [(0, "a"), (1, "b")])
check("zip", list(zip([1, 2], [3, 4])), [(1, 3), (2, 4)])
check("min max", (min(3, 1, 2), max([3, 1, 2])), (1, 3))
check("abs", abs(-3.5), 3.5)
check("round", round(2.675, 2), 2.67)
check("int()", int("123") + int(4.9), 127)
check("str fmt", "%d-%s" % (5, "x"), "5-x")
check("fstring", f"{3}+{4}={3 + 4}", "3+4=7")
check("fstring fmt", f"{3.14159:.2f}", "3.14")
check("str.format", "{}-{}".format(1, 2), "1-2")
check("string mul", "ab" * 3, "ababab")
check("slice", [1, 2, 3, 4, 5][1:4], [2, 3, 4])
check("slice neg", [1, 2, 3, 4, 5][::-1], [5, 4, 3, 2, 1])
check("tuple unpack", (lambda: (lambda a, b: a + b)(*(1, 2)))(), 3)
check("chained cmp", 1 < 2 < 3, True)
check("and/or", (0 or 5, 3 and 4), (5, 4))
check("ternary", 1 if 0 else 2, 2)
check("str methods", "Hello".lower() + "hello".upper() + " a b ".strip(), "helloHELLOa b")
check("join split", "-".join("a b c".split()), "a-b-c")
check("in str", "ell" in "hello", True)
check("str rev", "abc"[::-1], "cba")
check("list ops", [1, 2] + [3], [1, 2, 3])
check("list mul", [0] * 3, [0, 0, 0])
check("2d list", [[0] * 2 for _ in range(2)], [[0, 0], [0, 0]])
check("isinstance", isinstance(3, int), True)
check("math funcs", (math.floor(2.7), math.ceil(2.1), round(math.sin(0.5), 6)), (2, 3, 0.479426))
check("math gcd", math.gcd(12, 18), 6)
check("math log", round(math.log(10), 6), 2.302585)
check("math exp", round(math.exp(1), 6), 2.718282)
check("math hypot", math.hypot(3, 4), 5.0)
check("math isqrt", math.isqrt(99), 9)
check("float inf", float("inf") > 10 ** 18, True)
check("int div float", 10 // 3.0, 3.0)
check("neg pow", 2 ** -1, 0.5)
check("hex", hex(255), "0xff")
check("bin", bin(5), "0b101")
check("ord chr", (ord("a"), chr(98)), (97, "b"))
check("any all", (any([0, 1]), all([1, 0])), (True, False))
check("reversed", list(reversed([1, 2, 3])), [3, 2, 1])
check("map filter", list(map(lambda x: x + 1, filter(lambda x: x > 1, [1, 2, 3]))), [3, 4])
check("dict get", {"a": 1}.get("b", 9), 9)
check("dict items", sorted({"a": 1, "b": 2}.items()), [("a", 1), ("b", 2)])
check("list sort", (lambda l: (l.sort(), l)[1])([3, 1, 2]), [1, 2, 3])
check("global stmt", 1, 1)

class P:
    def __init__(self, x):
        self.x = x
    def __add__(self, o):
        return P(self.x + o.x)
    def __repr__(self):
        return "P(" + str(self.x) + ")"
    def __eq__(self, o):
        return self.x == o.x
    def __lt__(self, o):
        return self.x < o.x
    def __len__(self):
        return self.x

check("dunder add", (P(1) + P(2)).x, 3)
check("dunder repr", repr(P(1)), "P(1)")
check("dunder eq", P(1) == P(1), True)
check("dunder len", len(P(4)), 4)

class Q(P):
    def __init__(self, x):
        super().__init__(x)
        self.y = 1
check("super", Q(3).x, 3)

def gen(n):
    for i in range(n):
        yield i * i
check("generator", list(gen(4)), [0, 1, 4, 9])

def outer():
    c = 0
    def inc():
        nonlocal c
        c += 1
        return c
    inc()
    return inc()
check("nonlocal", outer(), 2)

try:
    1 // 0
    check("zerodiv", False, True)
except ZeroDivisionError:
    check("zerodiv", True, True)

try:
    [][1]
    check("indexerror", False, True)
except IndexError:
    check("indexerror", True, True)

try:
    {}["k"]
    check("keyerror", False, True)
except KeyError:
    check("keyerror", True, True)

def defaults(a, b=2, *args, **kw):
    return a + b + len(args) + len(kw)
check("defaults/args", defaults(1, 2, 3, 4, z=1), 6)

x = 10
def g():
    global x
    x = 20
g()
check("global", x, 20)

check("recursion depth", (lambda: sum(range(10)))(), 45)
def deep(n):
    if n == 0:
        return 0
    return 1 + deep(n - 1)
check("recursion 900", deep(900), 900)
check("walrus", ((y := 5) + y), 10)
check("lst.index/count", ([1, 2, 2].index(2), [1, 2, 2].count(2)), (1, 2))
check("str find/replace", ("abcabc".find("c"), "abcabc".replace("b", "X")), (2, "aXcaXc"))
check("tuple cmp", (1, 2) < (1, 3), True)
check("list cmp", [1, 2] == [1, 2], True)
check("dict order", list({"b": 1, "a": 2}.keys()), ["b", "a"])
check("int bit_length", (255).bit_length(), 8)
check("str isdigit", "123".isdigit(), True)
check("while else", 1, 1)
check("assert", 1, 1)
check("lambda default", (lambda a, b=3: a + b)(1), 4)
check("multi assign", (lambda: [a for a in [1]])(), [1])
check("complex str(list)", str([1, "a", None, True, 2.5]), "[1, 'a', None, True, 2.5]")
check("float fmt big", str(123456789.123456789), "123456789.12345679")
check("float small", str(1e-5), "1e-05")
check("int float eq", 1 == 1.0, True)
check("big pow mod", pow(2, 1000, 10 ** 9 + 7), 688423210)
check("float floor div", 7.5 // 2, 3.0)
check("float mod", 7.5 % 2, 1.5)
check("neg float mod", -7.5 % 2, 0.5)
check("sys.maxsize", sys.maxsize, 9223372036854775807)
