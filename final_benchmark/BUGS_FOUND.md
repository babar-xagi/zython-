# BUGS_FOUND.md - defects found while benchmarking Zython 0.10.0

All bugs were reproduced on the repo's own `ReleaseFast` binary (`zig-out/bin/zython`, byte-identical to a fresh `zig build -Doptimize=ReleaseFast`).
CPython 3.14.4 is the oracle. Repro files are in `final_benchmark/probes/`; the 223-snippet differential run is in `CORRECTNESS_RESULTS.md` / `results/correctness.json`; the 255-feature probe is in `results/feature_matrix.txt`.

Severity: **CRITICAL** = silent wrong answer, crash, or integrity problem. **HIGH** = common Python feature missing or very slow. **MEDIUM/LOW** = smaller gaps.

| ID | Severity | Summary |
|---|---|---|
| Z01 | CRITICAL | Segfault on recursion deeper than ~500 frames (no `RecursionError`) |
| Z02 | CRITICAL | Integers silently wrap at 64 bits - "arbitrary precision" only works in a few special cases |
| Z03 | CRITICAL | JIT is a **name lookup**: functions called `fib`, `count_primes`, `insertion_sort`, `taylor_exp`, `compute_step` are replaced by pre-compiled Zig code, even if the Python body is different |
| Z04 | CRITICAL | Loop closed-form folding wraps on overflow |
| Z05 | CRITICAL (perf) | Dict with non-string keys and `set` are O(n) linear scans -> O(n^2) |
| Z06 | CRITICAL (perf) | Memory is never freed (one process-wide arena) |
| Z07 | CRITICAL | 3-argument `pow(a, b, m)` gives wrong answers |
| Z08 | CRITICAL | Keyword arguments/`key=`/`reverse=`/`start=` silently ignored by builtins |
| Z09 | CRITICAL | User-defined dunder methods (`__add__`, `__eq__`, `__repr__`...) ignored |
| Z10 | CRITICAL | Builtin containers are not thread-safe: lost updates in "GIL-free" threads |
| Z11 | HIGH | Many core syntax forms are `ParseError` |
| Z12 | HIGH | Most of the builtin string/list/dict/set methods are missing |
| Z13 | HIGH | Standard library essentially absent (`collections`, `itertools`, `re`, `functools`, ...) |
| Z14 | HIGH | Exceptions lose message/type; custom exceptions impossible; no traceback |
| Z15 | MEDIUM | String formatting broken (`%`, `format`, f-string format specs) |
| Z16 | MEDIUM | `str +=` is O(n) per append (quadratic loops) |
| Z17 | MEDIUM | Float `repr` differs from Python for exponent forms |
| Z18 | MEDIUM | Strings are byte strings (`len('héllo') == 6`, ASCII-only `upper`) |
| Z19 | MEDIUM | `round()` is not banker's/exact; `bool` arithmetic and tuple ordering broken |
| Z20 | MEDIUM | Binary is dynamically linked and not stripped (README says fully static) |
| Z21 | LOW | `str.split()` without args does not split on `\n`; `bytes` indexing returns chars; `random.seed` differs |

---

## Z01 - Segfault on deep recursion (CRITICAL)
```python
def r(n):
    if n == 0:
        return 0
    return 1 + r(n - 1)
print(r(500))   # 500   OK
print(r(600))   # Segmentation fault (exit 139)
```
`probes/depth_probe.sh`: 500 ok, 600+ crash. CPython raises `RecursionError` at ~1000; it never crashes. Realistic recursive algorithms (DFS on 1000 nodes, naive recursive sum, deep memoised recursion) crash the interpreter hard. `tests` in this folder: `control/recursion_900`, `control/recursion_limit_error`.

## Z02 - Silent int64 wrap-around (CRITICAL)
README/summary: *"Arbitrary Precision ... 100% Exact Parity (PyBigInt)"*. Reality (all from `CORRECTNESS_RESULTS.md`, category `bignum`: **3/18 pass**):
```python
print(9223372036854775807 + 1)        # CPython 9223372036854775808   Zython -9223372036854775808
print(3037000500 * 3037000500)        # CPython 9223372037000250000   Zython -9223372036709301616
print(3 ** 40)                         # CPython 12157665459056928801  Zython -6289078614652622815
print(10 ** 19)                        # CPython 10000000000000000000  Zython -8446744073709551616
f = 1
for i in range(1, 31): f *= i          # CPython 265252859812191058636308480000000
print(f)                               #   Zython -8764578968847253504
print(10**30 > 10**29)                 # CPython True   Zython False
print((10**30) // 7)                   # CPython 142857142857142857142857142857   Zython 725277752900751945
print(int('123456789012345678901234567890'))   # Zython: RuntimeError: Overflow
```
Only a few special paths promote to bignum (`2**64`, `2**100`, `x*2` for `x = 2**62`), which is exactly what the README demos show. Ordinary `+`, `-`, `*`, `**` wrap, `//` and `%` and comparisons on bignums are wrong, and big integer literals fail at parse time. `BUGS.md` BUG-09 admits "64-bit integer overflow wrapping" is an "architectural tradeoff" while the README simultaneously claims arbitrary precision parity.
Any number-theory/factorial/Fibonacci/cryptography-style program produces **wrong answers with no warning**.

## Z03 - The "JIT" matches function names (CRITICAL / benchmark integrity)
`src/jit.zig`, `JitEngine.tryCompile`:
```zig
if (std.mem.eql(u8, func.name, "fib")) { ... func.jit_entry = &stencil_fib ... }
else if (std.mem.eql(u8, func.name, "count_primes")) ...
else if (std.mem.eql(u8, func.name, "insertion_sort")) ...
else if (std.mem.eql(u8, func.name, "taylor_exp")) ...
else if (std.mem.eql(u8, func.name, "compute_step")) ...
```
The "compiler" never looks at the function body. If the Python function is *called* one of these five names, Zython runs a hand-written Zig function (`stencil_fib` is plain recursive Zig code, `memcpy`'d into an executable page) instead of the user's code. These five names are exactly the functions used in the repo's headline benchmarks (`tests/final_pure_tests/01_compute_and_algorithms.py`).

Evidence (`probes/jit_names_probe.py`, `probes/run.sh`):

| Same code, different name | CPython | Zython |
|---|---:|---:|
| `fib(30)` | 0.114 s | **0.0023 s** (49x faster) |
| `fibx(30)` (identical body) | 0.112 s | 0.162 s (**1.45x slower**) |
| `count_primes(30000)` | 0.0317 s | **0.0020 s** |
| `count_primes_x(30000)` | 0.0256 s | 0.0299 s (1.17x slower) |
| `insertion_sort(3000)` (reverse-sorted input) | 0.252 s | **0.0067 s** (38x faster) |
| `insertion_sort_x(3000)` | 0.257 s | 0.348 s (**1.35x slower**) |

In `jit_names_probe.py` I even edited both insertion-sort bodies to `return len(arr)`: the hardcoded-name one still returned the *list* (the Python body was never run), the renamed one returned `3000` as it should.

Worse - it produces **wrong results** when a user function reuses a hardcoded name with different behaviour:
```python
def fib(n):            # base case returns 7 -> true fib(20) here is 76622
    if n <= 1: return 7
    return fib(n-1) + fib(n-2)
print(fib(20))         # CPython 76622    Zython 6765   (ran the hardcoded stencil)

def count_primes(limit):           # actually counts multiples of 3
    ...
print(count_primes(15000))         # CPython 5000   Zython 1754
```
(`probes/fib_variant_same_name.py`, `probes/count_primes_variant.py`). Also, the jit_kind fast path is only taken when the arg types match, so e.g. `fib(5.0)` falls back to the VM.

## Z04 - Loop closed-form folding overflows (CRITICAL)
Zython recognises `for i in range(N): s += i` (and `s += 1`) and replaces the loop with a closed-form (`tests/billion_loop_bench.py`: "1 billion iterations in 0.000001 s"). That is a legitimate *idea*, but the formula is evaluated in wrapping int64:
```python
s = 0
for i in range(4611686018427387904, 4611686018427387904 + 1000000):
    s += i
print(s)   # CPython 4611686018427887903500000    Zython 499999500000
```
(`probes/loopfold_probe.py`). The folding only applies to a few exact shapes (`s += 1`, `s += i` with nothing else in the body); the very same loop with `s += i * i`, or with two accumulators, runs through the normal VM. So the "1 billion iterations in 1 microsecond" figures are not an interpreter-throughput result.

## Z05 - Non-string dict keys and sets are linear scans (CRITICAL performance)
`src/value.zig` `PyDict.get/put`: only `string` keys use `string_map`; every other key does `for (self.entries.items) |entry| if (entry.key.equals(key))`. `PySet.contains/add` are the same.
```
int-key dict, insert n keys then look all up (probes/dict_probe.py), seconds:
    n        Zython        CPython
 10,000      0.27 + 0.30   0.0009 + 0.0016
 20,000      1.02 + 1.03   0.0014 + 0.0016
 40,000      3.86 + 4.26   0.0034 + 0.0030     (>1000x slower, quadratic)
 64,000 inserts of i*7:  11.28 s   vs  CPython 0.0108 s
```
String keys are fine (0.017 s for 40k). Dict-of-int is the most common dict in algorithmic code (memoisation, counters, graph adjacency). `p14_dict_and_string_workload` had to be shrunk ~25x to finish; at original size it exceeded the 120 s timeout (CPython 0.15 s). The repo's own `02_data_structures` test uses `d[str(i)]` string keys, i.e. the one fast path, so its dict score (1.6x slower than CPython) hides this cliff.

## Z06 - Memory is never reclaimed (CRITICAL)
`src/main.zig` hands `init.arena.allocator()` to the `Interpreter`; nothing in the evaluator frees values (no refcount, no GC). Peak RSS therefore equals "total bytes ever allocated":

| Workload (`probes/mem_probe.py`: 4-element list + short string per iteration, all garbage) | Zython peak RSS | CPython peak RSS |
|---|---:|---:|
| 100,000 iterations | 26.9 MB | 9.7 MB |
| 1,000,000 iterations | 237.8 MB | 9.7 MB |
| 5,000,000 iterations | **1,175 MB** | 9.5 MB |

and in the benchmark programs: `p11_sorting_algorithms` **641.7 MB vs 19.4 MB** (33x), `p14` 204 MB vs 12 MB, `p15` 78.7 MB vs 11.1 MB, `p09` 66.4 MB vs 19.2 MB. A long-running Zython program will exhaust RAM. The README's "Zero GC pauses" is the absence of a collector, not a design that bounds memory. Also, `Value` is a 16-byte tagged union - a 2M-element list costs ~65 MB (`p03` 90.6 MB vs 24.8 MB).

## Z07 - 3-argument `pow` is wrong (CRITICAL)
```python
print(pow(3, 200, 1000007))      # CPython 959082     Zython 6627890308811632801  (not even < modulus)
print(pow(2, 1000, 10**9 + 7))   # CPython 688423210  Zython 0
```
Modular exponentiation is the core primitive of number-theory code; the result ignores/overflows the modulus. (The hand-written `mod_pow` loop in `p06` is correct.)

## Z08 - Keyword args to builtins silently ignored (CRITICAL: silent wrong results)
```python
sorted([3,1,2], key=lambda x: -x)     # CPython [3, 2, 1]          Zython [1, 2, 3]
sorted([3,1,2], reverse=True)         # CPython [3, 2, 1]          Zython [1, 2, 3]
max(['aa','b','cccc'], key=len)       # CPython cccc               Zython aa
list(enumerate('ab', 1))              # CPython [(1,'a'),(2,'b')]  Zython []
l = [1,2,3,4]; l[1:3] = [9,9,9]       # CPython [1,9,9,9,4]        Zython [1,2,3,4]  (slice assignment is a no-op)
sorted([(1,'b'),(0,'z'),(1,'a')], key=lambda t: t[0])   # Zython returns input order
(1, 2) < (1, 3)                       # CPython True  Zython False  (tuple ordering)
```
`list.sort()` does not exist at all (AttributeError). No error is raised in the wrong-answer cases.

## Z09 - Dunder methods ignored (CRITICAL)
```python
class P:
    def __init__(self, x): self.x = x
    def __add__(self, o): return P(self.x + o.x)
    def __eq__(self, o):  return self.x == o.x
    def __repr__(self):   return 'P(%d)' % self.x
print(P(1) == P(1))     # CPython True    Zython False
print(repr(P(1)))       # CPython P(1)    Zython <P object>
P(1) + P(2)             # Zython RuntimeError: TypeError
class C:
    def __contains__(self, x): return x == 1
    def __bool__(self):        return False
print(1 in C(), bool(C()))      # CPython True False     Zython False True   (inverted!)
```
Not supported: `__add__`, `__eq__`, `__lt__`, `__repr__`, `__str__`, `__len__`, `__getitem__`, `__iter__`/`__next__`, `__call__`, `__hash__`, `__bool__`, `__contains__`. Also missing: `super()`, `@staticmethod`, `@classmethod`, `@property`, `isinstance(x, (A, B))`, `isinstance(3, int)`, `getattr/hasattr/setattr`, `type(x).__name__`. The OOP category in the differential test passes **3/20**.

## Z10 - "GIL-free" threads corrupt shared containers (CRITICAL)
`probes/thread_probe.py`, `probes/thread_stress.sh` (4 threads):
```
                                         Zython           CPython
unsynchronised counter[0] += 1 (800000)  261,104          800,000
shared list.append x 4 x 50,000          173,508          200,000
list.append + dict[...] = ... x 4 x 30k  114,352 / 114,857   120,000 / 120,000   (6 runs, always lossy)
Lock-protected counter (400000)          400,000 (OK)     400,000
CPU-bound 4 threads vs serial            0.169 s vs 0.426 s (real parallelism, 2.5x)   0.431 s vs 0.416 s (GIL)
```
True parallelism exists, but `ArrayList`/dict mutation has no synchronisation: concurrent `append` loses elements (and risks memory corruption on reallocation). CPython programs that rely on the GIL for atomic `list.append`/`dict[k]=v` break. No crash was observed in 6 runs, but undefined behaviour is possible.

## Z11 - Missing/invalid syntax (HIGH)
`ParseError` in Zython (all valid Python): `return a, b` (tuple return!), `x not in d`, `nonlocal`, dict/set comprehensions, nested/multi-`for` comprehensions, generator expressions, `a, *b = ...`, keyword-only args, `lambda *a`, walrus `:=`, `match`, `yield from`, `del x[i]`, call-site unpacking `f(*args)` / `f(**kw)` / `print(*xs)` (so the classic `def wrapper(*a): return f(*a)` decorator fails), `[*a]`, `{**d}`, `if __name__ == '__main__':` (`__name__` is undefined), `3j`. Real programs hit one of these within a few lines; 4 of my 15 benchmark programs (`p01`, `p02`, `p14`, `p15`) needed rewrites just to run (see BENCHMARK_RESULTS.md).

## Z12 - Missing builtin methods/functions (HIGH)
From `results/feature_matrix.txt` (255 CPython-valid snippets: Zython runs **107**, fails **148**):
* `list`: `extend insert remove sort reverse index count copy clear`
* `str`: `strip lstrip rstrip find replace isdigit isalpha count title capitalize center ljust rjust zfill partition splitlines format encode index isupper rsplit`
* `dict`: `items pop update setdefault copy clear popitem`; `set`: `discard | & - union issubset`, `sorted(set)`
* builtins: `any all map filter divmod hex bin oct hash id isinstance getattr hasattr input complex bytes bytearray frozenset range(...)[i]`
* `math`: `tan atan atan2 exp log log10 log2 pow fabs gcd factorial hypot isqrt isnan trunc fmod degrees radians comb` (README only advertises `pi e tau inf nan sqrt sin cos floor ceil` so this is a *gap*, not a false claim - but it means essentially no "complex mathematical" program that needs `exp`/`log` can run).

## Z13 - Standard library absent (HIGH)
`ImportError` for: `collections itertools functools re string heapq bisect typing dataclasses fractions decimal statistics array copy operator abc enum pathlib datetime struct io csv subprocess argparse logging unittest queue multiprocessing`. Present: `math time sys os os.path json random hashlib threading concurrent.futures asyncio socket ctypes` (subset). The README's "~98% language feature completeness" has no support.

## Z14 - Exceptions (HIGH)
* Messages are lost: `except ZeroDivisionError as e: print(e)` prints `ZeroDivisionError` (CPython `division by zero`); `assert x, 'msg'` loses `msg`.
* `class MyErr(Exception)` -> `NameError` (no `Exception` base class); `raise ValueError('x')` with `as e` fails to run.
* `int('x')` escapes as a Zig error (`RuntimeError: InvalidCharacter`) that **cannot be caught** by `except ValueError`.
* Uncaught errors print `RuntimeError: ZeroDivisionError` - no traceback, no line number.

## Z15 - String formatting (MEDIUM)
`f'{3.14159:.2f}'` -> `3.14159`; `f'{42:>8}'` -> `42`; `f'{1234567:,}'` -> `1234567` (format specs ignored, silently). `'%d' % 5` and `'%5.1f' % x` -> `TypeError`. `'{}'.format(1)` -> AttributeError.

## Z16 - `str +=` quadratic (MEDIUM)
```
s += chr(97 + i % 26), n appends:  n=20,000 -> Zython 0.128 s  CPython 0.0074 s (17x)
                                   n=80,000 -> Zython 2.03 s   CPython 0.087 s  (23x)
```
Each `+=` copies the whole string (CPython resizes in place when the refcount is 1).

## Z17 - Float repr (MEDIUM)
`str(1e16)` -> `10000000000000000.0` (CPython `1e+16`); `str(1e-5)` -> `0.00001` (CPython `1e-05`).

## Z18 - Unicode (MEDIUM)
`len('héllo')` -> 6; `'héllo'.upper()` -> `HéLLO`. Strings are bytes.

## Z19 - Misc semantics (MEDIUM)
`round(0.5), round(1.5), round(2.5)` -> `(1, 2, 3)` (CPython `(0, 2, 2)`); `round(2.675, 2)` -> `2.68` (CPython `2.67`); `True + True` -> `TypeError`; `sum(i*i for i in range(10))` -> ParseError.

## Z20 - "Fully static, 0 dependencies" is false (MEDIUM, documentation)
`ldd zig-out/bin/zython` -> `libc.so.6`, `ld-linux-x86-64.so.2`; `file`: *dynamically linked ... with debug_info, not stripped* (`build.zig` sets `link_libc = true`, `rdynamic = true`; 6.5 MB).

## Z21 - Minor
* `'hi\nthere\n'.split()` -> `['hi\nthere\n']` (splits on spaces only). Breaks `open(f).read().split()`.
* `b'abc'[0]` -> `'a'` and `list(b'abc')` -> `['a','b','c']` (CPython `97`, `[97,98,99]`).
* `random.seed(42); random.random()` -> `0.6969...` (CPython `0.6394...`): not Mersenne Twister, so seeded sequences differ.
* `07_c_extensions_and_ctypes.py` exits 1 on both interpreters on this machine; `08_io_os_socket_and_json.py` exits 1 under CPython after item 6 (test-file issue) yet the summary says all passed.
* Repo hygiene: two nearly identical reports (`final_sumary.md`, `final_summary.md`); README tables mix "Zython 0.5.0" measurements under a "0.10.0" heading; only 3 Zig unit tests (they pass: `zig build test`).
