# MEMORY_AND_STARTUP.md

Machine: WSL2 Linux 6.18, x86_64, 8 cores, 15.8 GB RAM. Zython 0.10.0 `ReleaseFast` (Zig 0.17.1) vs CPython 3.14.4 (GCC 15.2.0).
Raw data: `results/startup.json`, `results/bench.json`. Scripts: `startup_probe.py`, `bench_runner.py`, `probes/mem_probe.sh`, `probes/rss_check.sh`.

## 1. Startup latency (empty program / `print('hello')`)
Method: shell loop starting the interpreter 300 times (best of 3 loops); `/bin/true` measured as the fork+exec floor (0.58 ms).

| | per launch | minus fork/exec floor | 
|---|---:|---:|
| `/bin/true` (floor) | 0.58 ms | - |
| **Zython** `pass` | **1.62 ms** | **1.04 ms** |
| **Zython** `print('hello')` | 1.66 ms | 1.08 ms |
| **CPython 3.14** `pass` | 14.03 ms | 13.46 ms |
| **CPython 3.14** `print('hello')` | 14.05 ms | 13.47 ms |
| CPython 3.14 `-I -S` (no site/user dirs) | 9.03 ms | - |

* Zython starts **~8.7x faster** than default CPython (12.9x if the fork floor is subtracted) and ~5.6x faster than CPython with `-I -S`.
* README claim "< 1.0 ms vs 10 ms": the order of magnitude is right, the literal "< 1.0 ms" is not (1.04 ms net / 1.6 ms gross here). **Verdict: TRUE in spirit (real, large advantage for short scripts).**

## 2. Baseline memory (empty program, peak RSS from `/usr/bin/time -f %M`)

| | Peak RSS |
|---|---:|
| Zython | **4,164 KB (4.1 MB)** |
| CPython 3.14 | 9,736 KB (9.5 MB) |
| CPython `-S -E` | 8,244 KB |

* Zython uses **57% less** RAM at idle (README: "3,512 KB vs 10,528 KB, 67% less" - the direction is right; the measured Zython figure is 4.1 MB, not 3.5 MB). **Verdict: MOSTLY TRUE (idle only).**

## 3. Memory under real workloads - the claim flips

Peak RSS (MB), median-run program from `BENCHMARK_RESULTS.md`:

| Program | CPython | Zython | Zython / CPython |
|---|---:|---:|---:|
| p01 recursive fib/ackermann/tak | 9.6 | 4.3 | 0.45x |
| p02 collatz | 9.5 | 4.2 | 0.44x |
| p03 sieve 2M | 24.8 | 90.6 | **3.7x worse** |
| p04 mandelbrot | 9.9 | 4.3 | 0.43x |
| p05 matmul 90x90 | 10.6 | 10.8 | 1.0x |
| p06 Miller-Rabin | 9.7 | 9.1 | 0.9x |
| p07 Monte-Carlo | 9.8 | 4.3 | 0.44x |
| p08 numerical calculus | 10.4 | 5.1 | 0.49x |
| p09 DP tables | 19.2 | 66.4 | **3.5x worse** |
| p10 N-Queens | 9.7 | 5.7 | 0.59x |
| p11 sorting (150k elements) | 19.4 | **641.7** | **33x worse** |
| p12 number theory | 21.2 | 27.8 | 1.3x worse |
| p13 OOP particles | 10.0 | 5.1 | 0.51x |
| p14 dict/string | 12.2 | **204.1** | **16.7x worse** |
| p15 game of life / BFS | 11.1 | 78.7 | **7.1x worse** |

Pure scalar/float code (no heap allocation) is lighter than CPython. Anything that allocates lists, strings, tuples or dicts is much heavier, because:
1. `Value` is a 16-byte tagged union (CPython ints in lists are shared small ints, floats 24 B but freed).
2. **Nothing is ever freed** (the interpreter allocates from `init.arena`; `src/main.zig`). Garbage-only workload (`probes/mem_probe.py`, per iteration: build a 4-element list and a short string, discard):

| iterations | Zython peak RSS | CPython peak RSS | time Zython / CPython |
|---:|---:|---:|---|
| 100,000 | 26.9 MB | 9.7 MB | 0.05 s / 0.06 s |
| 1,000,000 | 237.8 MB | 9.7 MB | 0.57 s / 0.64 s |
| 5,000,000 | **1,175 MB** | 9.5 MB | 2.95 s / 2.77 s |

Linear growth (~235 bytes per iteration of pure garbage). A service or any long loop will eventually be OOM-killed. **Verdict on "67% less RAM": TRUE only for tiny/scalar scripts; FALSE (up to 33x more) for realistic data-structure workloads.**

## 4. Binary
| | |
|---|---|
| Size | 6.58 MB, **dynamically linked** (`libc.so.6`, `ld-linux`), `with debug_info, not stripped` |
| README claim | "100% Static Executable, 0 dynamic dependencies" -> **FALSE** |
