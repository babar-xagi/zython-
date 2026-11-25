# FINAL REPORT - Is the "huge faster than CPython" claim of Zython true?

**Short answer: No, not as stated.** The headline numbers (39x-55x faster) are real *measurements*, but they are produced by a lookup table of pre-written Zig functions keyed on five benchmark function names, not by a fast interpreter. On general code Zython is, on average, **slightly slower than CPython 3.14** (geometric mean **0.81x**), uses far more memory under load, silently returns wrong answers in many common situations, and implements only about 42% of the Python features I probed.

What *is* genuinely good: process startup (~9-13x faster), idle memory (57% smaller), and tight integer/float loops (1.2x-2.3x faster). Those are real engineering wins, but they are an order of magnitude smaller than the claims.

Environment: WSL2 Linux 6.18 x86_64, 8 cores, 15.8 GB RAM. Zython 0.10.0 built with Zig 0.17.1 `-Doptimize=ReleaseFast` (rebuilt from source, byte-identical to the shipped `zig-out/bin/zython`). Baseline: CPython 3.14.4 (GCC 15.2.0). All timings: fresh process per run, 5 repetitions, median.

## 1. What I did

1. Read the repo: 12.1k lines of Zig in `src/` (lexer, Pratt parser, bytecode compiler, quickening VM, AST interpreter fallback, 194-line `jit.zig`), README, `BUGS.md`, `benchmark.md`, `final_summary.md`, `developer_doc/`, `tests/`.
2. Wrote **15 complex math/logic programs** (`programs/`): recursion (fib/ackermann/tak), Collatz, sieve to 2M, Mandelbrot, matrix multiply, Miller-Rabin + modpow, Monte-Carlo pi, numerical calculus (Simpson/Newton/Taylor/Leibniz), DP (LCS/edit distance/knapsack/coins), N-Queens, 4 sorting algorithms, number theory (gcd/totient/perfect numbers), OOP particle sim, dict/string workload, game of life + BFS. Output of each program was compared with CPython byte-for-byte.
3. Ran the repo's own tests/benchmarks on both interpreters (`REPO_TESTS_RESULTS.md`).
4. Wrote a 223-snippet **differential correctness suite** (`diff_tester.py`) and a 255-item **feature matrix** (`probes/method_matrix.py`).
5. Probed every suspicious thing I found (JIT names, loop folding, memory, dict complexity, threads, recursion) with minimal repros (`probes/`).
6. Rebuilt the binary, measured startup/RSS/linkage, ran `zig build test` (3/3 pass).

## 2. Scoreboard - 15 general-purpose programs (BENCHMARK_RESULTS.md)

| Program | CPython (s) | Zython (s) | Zython vs CPython | RSS CPython / Zython |
|---|---:|---:|---:|---:|
| p01 recursion (fib 30, ackermann, tak) | 0.138 | 0.174 | 1.26x slower | 9.6 / 4.3 MB |
| p02 Collatz longest chain <100k | 0.748 | 0.890 | 1.19x slower | 9.5 / 4.2 |
| p03 sieve 2M + prime stats | 0.453 | 0.378 | 1.20x faster | 24.8 / 90.6 |
| p04 Mandelbrot 160x120x200 | 0.118 | 0.137 | 1.16x slower (noise: min 0.113 vs 0.110) | 9.9 / 4.3 |
| p05 matrix multiply 90^3 x2 | 0.110 | 0.096 | 1.14x faster | 10.6 / 10.8 |
| p06 Miller-Rabin + modpow | 0.168 | 0.119 | 1.41x faster | 9.7 / 9.1 |
| p07 Monte-Carlo pi (LCG) | 0.467 | 0.243 | **1.92x faster** | 9.8 / 4.3 |
| p08 numerical calculus | 0.226 | 0.196 | 1.15x faster | 10.4 / 5.1 |
| p09 dynamic programming | 0.208 | 0.293 | 1.41x slower | 19.2 / 66.4 |
| p10 N-Queens + subset sum | 0.052 | 0.058 | 1.12x slower | 9.7 / 5.7 |
| p11 4 sorting algorithms | 1.453 | 2.673 | 1.84x slower | 19.4 / **641.7** |
| p12 number theory | 1.064 | 0.990 | 1.07x faster | 21.2 / 27.8 |
| p13 OOP particle simulation | 0.120 | 0.169 | 1.41x slower | 10.0 / 5.1 |
| p14 dict + string (*shrunk 25x*) | 0.076 | 0.656 | **8.6x slower** | 12.2 / 204.1 |
| p15 game of life + BFS | 0.136 | 0.239 | 1.76x slower | 11.1 / 78.7 |

* Faster on 6/15, slower on 9/15; **geometric mean 0.81x**; best 1.92x; worst 0.12x (and ~1000x on large int-key dicts).
* All 15 produce output identical to CPython - but only after I rewrote constructs Zython can't parse and kept all integers < 2^63 (BENCHMARK_RESULTS.md lists every adjustment).

## 3. The repo's own headline claims (CLAIMS_VERIFICATION.md)

| Claim | Result |
|---|---|
| fib(26) 39-55x faster | **Reproduces (52x) only for a function literally named `fib`**. Same code named `fibx`: 1.45x *slower*. A different function named `fib` returns the wrong answer (6765 vs 76622). |
| Insertion sort 26-42x, primes 15x, Taylor sub-µs | Same: hardcoded names `insertion_sort`, `count_primes`, `taylor_exp`. Renamed copies are 1.17x-1.35x slower than CPython. |
| "Copy-and-patch JIT" | `src/jit.zig`: `if (std.mem.eql(u8, func.name, "fib")) -> stencil_fib` ... Not a JIT. |
| Loops 1.46-2.12x faster | **Reproduces: 1.26x-1.89x** on the repo's loop micro-benchmarks, up to 2.3x on other tight loops. Real programs: mixed. |
| 1 billion loop in 1 µs | Closed-form substitution for two exact loop shapes; wraps on overflow. |
| Startup < 1 ms vs 10 ms | **True**: 1.6 ms vs 14.0 ms (8.7x). |
| 67% less RAM | **True idle** (4.1 vs 9.7 MB, -57%). **False under load** (up to 33x more; nothing is ever freed - 1.17 GB for 5M garbage iterations). |
| Fully static, 0 deps | **False** (dynamic libc, not stripped). |
| Arbitrary-precision parity | **False**: int64 wraps on `+ - *`; `3**40`, `30!`, `10**19` wrong. |
| ~98% feature completeness / full parity | **False**: 42% of snippets match CPython; `nonlocal`, tuple `return`, `super()`, `sort`, `__eq__`... missing. |
| GIL-free threads | Real 2.5x CPU speed-up, **but** shared `list.append` / `+=` lose updates. |

## 4. Correctness (CORRECTNESS_RESULTS.md): 223 differential snippets
**94 pass (42%)**, **41 silently wrong**, **86 error out**, **2 segfault**.
By area: arith 69%, floats 44%, strings 43%, containers 42%, control flow 54%, **bignum 17%, OOP 15%**, stdlib 32%.

## 5. Top bugs (BUGS_FOUND.md has 21, with repros)
1. **Z03** JIT keyed on function *name* - wrong answers + fake speed-ups.
2. **Z02** Silent int64 wrap; no real bignum arithmetic.
3. **Z06** No memory reclamation: RSS = total ever allocated.
4. **Z05** Dict/set with non-string keys are O(n) -> O(n^2) (~1,000x slower at 64k keys).
5. **Z01** Segfault at recursion depth ~600.
6. **Z07/Z08/Z09** `pow(a,b,m)`, `sorted(key=)`, `max(key=)`, `enumerate(start)`, slice assignment, `__eq__/__repr__/__add__/...` silently wrong.
7. **Z10** Thread-unsafe builtin containers.
8. **Z11-Z14** Missing syntax (tuple return, `nonlocal`, dict/set comprehensions, `not in`, `f(*args)`), 148 of 255 probed features, nearly no stdlib, exceptions lose their messages.

## 6. Verdict

| Question | Answer |
|---|---|
| Is Zython "huge faster" than CPython? | **No.** 0.81x geometric mean on general programs; 39-55x only for five hardcoded function names. |
| Is the startup/idle-memory advantage real? | **Yes** (8.7x faster start, 57% less idle RAM) - useful for tiny scripts. |
| Are tight integer loops faster? | **Yes**, 1.2x-2.3x. |
| Is it a drop-in Python 3.15 replacement? | **No.** ~42% parity; silent wrong answers (overflow, kwargs ignored, dunders ignored). |
| Can the published benchmark numbers be trusted? | They are reproducible, but they measure special-cased code paths, so they should not be cited as interpreter performance. |
| Is it a promising research prototype? | Yes - compact VM, quickening, fast startup, real threads. With the name-based "JIT" removed, the honest story is "CPython-class speed, tiny footprint, early-stage language coverage".

## 7. Recommendations for the author
1. Delete name-matching in `jit.zig`, or JIT from bytecode; re-run all published numbers.
2. Implement real bignum promotion in every arithmetic op (overflow checks `@addWithOverflow`...), or document "int64 only".
3. Add a freeing strategy (refcounts or tracing GC) before claiming memory advantages.
4. Hash-based dict/set for all hashable keys.
5. Add a recursion limit that raises `RecursionError`.
6. Replace "98% / 100% parity" with the differential suite in `diff_tester.py` and track the pass rate (currently 42%).

## 8. Files in this folder

| File | Content |
|---|---|
| `FINAL_REPORT.md` | this report |
| `BENCHMARK_RESULTS.md` | 15-program timing + memory table (generated from `results/bench.json`) |
| `CLAIMS_VERIFICATION.md` | claim-by-claim verdicts |
| `MEMORY_AND_STARTUP.md` | startup, idle RSS, RSS under load, binary linkage |
| `BUGS_FOUND.md` | 21 bugs with repros |
| `CORRECTNESS_RESULTS.md` | 223-snippet differential results (generated) |
| `REPO_TESTS_RESULTS.md` | the repo's own tests on both runtimes (generated) |
| `programs/` | the 15 benchmark programs |
| `probes/` | minimal repro scripts (JIT names, bignum, threads, dict, memory, recursion, loop folding, feature matrix) |
| `diff_tester.py`, `bench_runner.py`, `startup_probe.py`, `run_repo_tests.py`, `gen_reports.py` | harness |
| `results/` | raw JSON/text outputs |
| `run_all.sh` | reproduce everything |

## 9. Limitations of this study
* One machine (WSL2), one CPython version; WSL2 timing noise is ~5-10% (visible in min/max columns), so ratios between 0.9x and 1.1x should be read as parity.
* My programs are a sample, not a standard suite; and had to be restricted to the Python subset Zython supports (this favours Zython: the programs it cannot run at all are not scored).
* CPython was the stock build (no JIT/PGO tuning flags beyond the distro build); Zython was ReleaseFast without further tuning.
