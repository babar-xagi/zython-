# BENCHMARK_RESULTS.md - 15 complex math/logic programs, Zython vs CPython

Interpreter versions: Zython 0.10.0 (ReleaseFast, Zig 0.17.1) vs `3.14.4 (main, Aug 20 2026, 10:41:58) [GCC 15.2.0]`.  
Each program ran **5 times per interpreter** as a fresh process; table shows the **median wall time** (min-max in brackets) and **peak RSS** (via `/usr/bin/time`). Output of every program was compared byte-for-byte with CPython's.

| # | Program | CPython median (s) | Zython median (s) | Zython speed vs CPython | Output identical | CPython RSS | Zython RSS |
|---|---|---:|---:|---:|:---:|---:|---:|
| 01 | `recursive_fibonacci` | 0.1380 (0.1315-0.1506) | 0.1738 (0.1686-0.1824) | **1.26x slower** | YES | 9.6 MB | 4.3 MB |
| 02 | `collatz_longest_chain` | 0.7482 (0.7252-0.8063) | 0.8898 (0.8615-0.9411) | **1.19x slower** | YES | 9.5 MB | 4.2 MB |
| 03 | `sieve_and_prime_sums` | 0.4530 (0.4525-0.4743) | 0.3776 (0.3664-0.3965) | **1.20x faster** | YES | 24.8 MB | 90.6 MB |
| 04 | `mandelbrot_float` | 0.1178 (0.1095-0.1220) | 0.1366 (0.1128-0.1439) | **1.16x slower** | YES | 9.9 MB | 4.3 MB |
| 05 | `matrix_multiply_mod` | 0.1096 (0.1055-0.1241) | 0.0959 (0.0943-0.1010) | **1.14x faster** | YES | 10.6 MB | 10.8 MB |
| 06 | `miller_rabin_modpow` | 0.1680 (0.1608-0.1778) | 0.1191 (0.1102-0.1298) | **1.41x faster** | YES | 9.7 MB | 9.1 MB |
| 07 | `monte_carlo_lcg_pi` | 0.4665 (0.4431-0.4869) | 0.2426 (0.2419-0.2954) | **1.92x faster** | YES | 9.8 MB | 4.3 MB |
| 08 | `numerical_calculus` | 0.2259 (0.2091-0.2443) | 0.1963 (0.1719-0.2000) | **1.15x faster** | YES | 10.4 MB | 5.1 MB |
| 09 | `dynamic_programming` | 0.2080 (0.2009-0.2255) | 0.2928 (0.2800-0.2947) | **1.41x slower** | YES | 19.2 MB | 66.4 MB |
| 10 | `nqueens_backtracking` | 0.0518 (0.0499-0.0596) | 0.0581 (0.0579-0.0603) | **1.12x slower** | YES | 9.7 MB | 5.7 MB |
| 11 | `sorting_algorithms` | 1.4526 (1.4156-1.5085) | 2.6732 (2.3713-2.7742) | **1.84x slower** | YES | 19.4 MB | 641.7 MB |
| 12 | `number_theory_gcd_totient` | 1.0643 (1.0484-1.3798) | 0.9903 (0.9829-1.0230) | **1.07x faster** | YES | 21.2 MB | 27.8 MB |
| 13 | `oop_particle_simulation` | 0.1199 (0.1172-0.1345) | 0.1694 (0.1649-0.1705) | **1.41x slower** | YES | 10.0 MB | 5.1 MB |
| 14 | `dict_and_string_workload` | 0.0763 (0.0742-0.0819) | 0.6556 (0.6162-0.7489) | **8.59x slower** | YES | 12.2 MB | 204.1 MB |
| 15 | `gameoflife_and_grid` | 0.1358 (0.1328-0.1447) | 0.2391 (0.2130-0.2704) | **1.76x slower** | YES | 11.1 MB | 78.7 MB |

## Aggregate

* Programs where Zython is clearly faster (>1.05x): **6 / 15**
* Programs where Zython is clearly slower (<0.95x): **9 / 15**
* Geometric-mean speed ratio (CPython time / Zython time): **0.81x**  (1.0 = parity)
* Best case: **1.92x**   Worst case: **0.12x**
* Programs with output identical to CPython: **15 / 15**

> Repo claim being tested: *"39x-55x faster on compute, 1.46x-2.12x on loops"*. On general workloads the geometric mean is **0.81x** - i.e. Zython is on average *slightly slower* than CPython 3.14, not 40x faster. See `CLAIMS_VERIFICATION.md` for why the repo's headline numbers do not generalise.

## Adjustments I had to make so Zython could run the programs at all

Zython could not run the first drafts of several programs (see `BUGS_FOUND.md`). To still get a timing I made the *minimum* source edits, listed here so the comparison stays transparent:

* `p01`: `ackermann(2, 300)` -> `ackermann(2, 200)`; Zython segfaults for recursion deeper than ~500 frames (BUG-Z01).
* `p02`, `p14`, `p15`: `return a, b` (tuple return) is a **ParseError** in Zython -> rewritten `return (a, b)`; `n, l = f()` tuple-unpack of a call result -> indexed access; `x not in d` is a ParseError -> `not (x in d)`.
* `p14`: shrunk workload (memo-collatz limit 60000 -> 2500, histogram 150000 -> 60000 samples over 400 keys instead of 5000). At the original size Zython **did not finish in 120 s** (CPython: 0.15 s) because int-keyed dicts are O(n) linear scans (BUG-Z05).
* `p11`: uses hand-written sorts because `list.sort()`, `sorted(key=,reverse=)` are missing / silently ignore arguments (BUG-Z08).
* All programs keep every intermediate value below 2**63 because Zython silently wraps on int64 overflow (BUG-Z02); using Python's real big-int semantics would give **wrong answers** on Zython.
* No program uses the names `fib`, `count_primes`, `insertion_sort`, `taylor_exp`, `compute_step`, which Zython's JIT special-cases by *name* (BUG-Z03).
