# CLAIMS_VERIFICATION.md - every performance/feature claim in the README, checked

Claims are quoted from `README.md`, `final_summary.md`, `benchmark.md`. Evidence file names refer to `final_benchmark/`.
Environment: WSL2 / x86_64 / 8 cores, Zig 0.17.1 `ReleaseFast` (rebuilt and byte-compared to `zig-out/bin/zython`), CPython 3.14.4.

Verdict legend: TRUE, PARTLY TRUE, MISLEADING (number reproducible, conclusion false), FALSE.

## A. Headline "39x-55x faster" compute claims

| Claim (README) | Reproduced with the repo's own test? | Reproduced with identical code under another name / general code? | Verdict |
|---|---|---|---|
| `fib(26)` **39.2x-55.2x** faster | YES: 0.00031 s vs 0.01612 s = **52x** (`results/repo_claims_output.txt`) | **NO**: same function named `fibx(30)`: Zython 0.162 s vs CPython 0.112 s = **1.45x slower**; `fibonacci_rec(30)`+ackermann+tak (p01): **1.26x slower** | **MISLEADING** (Z03: hardcoded by name) |
| Insertion sort 1,500: **26x-42x** | YES (0.0015 vs 0.063 = 41x) | NO: `insertion_sort_x(3000)` 0.348 s vs 0.257 s = **1.35x slower**; p11 sorts: **1.84x slower** | **MISLEADING** |
| Primes to 15,000: **15x** | YES (0.00079 vs 0.0105 = 13x) | NO: `count_primes_x(30000)` 0.0299 s vs 0.0256 s = **1.17x slower** | **MISLEADING** |
| Taylor series < 1 us | YES (prints `0.0 s`) | name `taylor_exp` hardcoded (`stencil_taylor_exp`); `taylor_exp_series` in p08 runs the normal VM: 1.15x faster in whole-program | **MISLEADING** |
| "Copy-and-Patch Native JIT Compiler", "direct machine code generation" | `src/jit.zig` is 194 lines: 5 stencils written in Zig and chosen by `std.mem.eql(u8, func.name, "fib")`. No bytecode -> machine code translation exists. | Same-name function with different body gives wrong answers: `fib` variant prints 6765 instead of 76622 | **FALSE** (not a JIT; it is a lookup table keyed on benchmark function names) |

Honest summary of A: on 15 general programs where none of the five magic names is used, Zython's geometric-mean speed vs CPython is **0.81x** (it is *slower*): `BENCHMARK_RESULTS.md`.

## B. "1.46x-2.12x faster loops"

| Claim | Reproduced? | Verdict |
|---|---|---|
| Function call in loop 400k: 2.12x | YES, repo test: 0.01147 vs 0.02169 = **1.89x** | TRUE for that micro-benchmark |
| Nested 2D 1000x1000: 1.63x | YES: 0.02829 vs 0.04267 = **1.51x** | TRUE |
| Multi-statement 1M: 1.56x | YES: 0.04498 vs 0.07065 = **1.57x** | TRUE |
| Branching 2M: 1.48x | YES: 0.09173 vs 0.1156 = **1.26x** | PARTLY TRUE |
| Unspecialised `s = s + 1` 2M: 1.50x | YES: 0.04273 vs 0.05371 = **1.26x** | PARTLY TRUE |
| Pattern-matched 10M `s += 1`: 1.46x | YES: 0.2111 vs 0.2715 = **1.29x** | PARTLY TRUE |
| `s += i % 3` 5M / two accumulators 5M (`probes/loopfold_probe.py`) | 0.187 vs 0.427 = **2.3x**; 0.286 vs 0.571 = **2.0x** | TRUE - this is the VM's genuine strength: tight integer loops are ~1.2-2.3x faster |
| Real programs mixing calls, lists, dicts | p01 1.26x slower, p02 1.19x slower, p04 1.16x slower, p09 1.41x slower, p13 1.41x slower, p15 1.76x slower, p14 8.6x slower; p07 1.92x faster, p06 1.41x faster | **Not generalisable**: function calls with args, list/dict heavy code are slower than CPython 3.14 |

CPython 3.14's specialising adaptive interpreter is already fairly quick; Zython's VM is in the same league, faster on integer-only loops, slower once allocation, calls or containers are involved.

## C. "1 billion iterations" (`tests/billion_loop_bench.py`)
Zython: all four loops finish in microseconds. CPython on this machine: `for i in range(10**8): s += 1` = **6.55 s**; the full file did not finish in 90 s (killed).
Why: Zython recognises the loop shape and substitutes a closed-form (`n`, `n(n-1)/2`). Not an execution-speed result, and the formula wraps at 64 bits (Z04: sum over `range(2**62, 2**62+10**6)` -> Zython `499999500000`, correct `4611686018427887903500000`). **Verdict: MISLEADING** (legit micro-optimisation, but narrow, and incorrect on overflow).

## D. Memory / startup / binary

| Claim | Measured | Verdict |
|---|---|---|
| Startup < 1 ms vs 10 ms | 1.62 ms vs 14.0 ms per launch (1.04 vs 13.5 ms net) | **TRUE (8.7x-13x faster)** |
| Peak RSS 3.5 MB vs 10.5 MB (67% less) | 4.16 MB vs 9.74 MB (57% less) at idle | **TRUE for idle**; see next row |
| Lower memory in general | Sorting 150k ints: 642 MB vs 19 MB; 5M garbage iterations: 1.17 GB vs 9.5 MB (never frees) | **FALSE under load** |
| "Zero GC pauses (deterministic arena)" | No GC and no freeing at all | **MISLEADING** (a leak, not a design) |
| "100% static executable, 0 deps" | `libc.so.6` dynamic, not stripped | **FALSE** |

## E. Feature / parity claims

| Claim | Measured | Verdict |
|---|---|---|
| "Arbitrary precision, 100% parity" | `bignum` correctness category 3/18; `+ - *` wrap at int64; `//`, `%`, `>` wrong on big values; big literals -> `Overflow` | **FALSE** (Z02) |
| "Language Feature Completeness ~98%", "100% exact parity" | 94/223 (42%) differential snippets identical; 107/255 (42%) feature probes supported | **FALSE** |
| "Python 3.15 compatibility" | No `nonlocal`, no tuple return, no dict comprehension, no `__name__`... | **FALSE** |
| "Native multi-threading, GIL-free, 100% parity" | Real parallel speed-up (2.5x on 4 threads) | **PARTLY TRUE** - but lost updates on shared list/dict/counter (Z10) |
| Generators (`yield`) / coroutines / `asyncio.run` | basic `yield` loop and `asyncio.run(async def)` give identical output; `yield from`, genexp unsupported | **PARTLY TRUE** |
| Decorators, context managers | simple cases identical | **TRUE (basic cases)** |
| Decorators/classes: `@property`, `@staticmethod`, `super()`, dunders | not supported | n/a (not claimed) but breaks OOP parity |
| Stackless/"no stack overflow" | segfault above ~500 recursion depth | **FALSE** (Z01) |
| Native `json`, `hashlib`, `socket`, `os`, `random`, `ctypes` | `json.dumps/loads`, `hashlib.sha256/md5`, `os.path.join`, threading, asyncio: match CPython in my snippets. `random.seed(42)` sequence differs. `collections`, `itertools`, `re`, `functools`... missing | **PARTLY TRUE** |
| Unit tests | `zig build test`: 3/3 pass | TRUE (but tiny) |
| "Zython is 2x faster at OOP" | repo's own OOP test: **2.0x-2.9x slower**; the repo's `final_summary.md` itself records CPython winning here | repo is honest on this one; README summary table omits it |

## F. What the repo's *own* data says (it already contains the contradictions)
`final_summary.md` Test 2 (data structures) and Test 3 (OOP) list CPython as the winner by 1.4x-2.4x; the README front table only shows the benchmarks Zython wins. Reproduced here: `REPO_TESTS_RESULTS.md`, `results/repo_claims_output.txt` (List 2.5x, dict 1.6x, tuple 1.6x, string 2.3x, OOP 2.0x-2.9x slower in Zython).
