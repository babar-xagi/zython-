# REPO_TESTS_RESULTS.md - the repo's own tests/benchmarks run on both interpreters

Source files: `tests/*.py` and `tests/final_pure_tests/*.py`. Wall time / RSS are for the whole process (includes startup). `diff lines` = output lines that differ after dropping lines that contain timings.

| File | CPython rc | CPython time | CPython RSS | Zython rc | Zython time | Zython RSS | diff lines | Note |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| `tests/billion_loop_bench.py` | -999 | 90.003s | 9.9 MB | 0 | 0.004s | 9.9 MB | 11 | CPython killed at the 90 s timeout; Zython finishes in ms via closed-form loop folding (not execution) |
| `tests/comprehensive_bench.py` | 0 | 2.706s | 16.8 MB | 0 | 1.969s | 130.8 MB | 0 |  |
| `tests/test_basic.py` | 0 | 0.020s | 9.9 MB | 0 | 0.004s | 9.9 MB | 0 |  |
| `tests/test_benchmark.py` | 0 | 0.095s | 9.9 MB | 0 | 0.007s | 9.9 MB | 0 |  |
| `tests/test_classes.py` | 0 | 0.022s | 9.9 MB | 0 | 0.004s | 9.9 MB | 0 |  |
| `tests/test_control.py` | 0 | 0.020s | 9.9 MB | 0 | 0.004s | 9.9 MB | 0 |  |
| `tests/test_functions.py` | 0 | 0.020s | 9.9 MB | 0 | 0.003s | 9.9 MB | 0 |  |
| `tests/final_pure_tests/01_compute_and_algorithms.py` | 0 | 0.150s | 10.2 MB | 0 | 0.008s | 9.9 MB | 0 |  |
| `tests/final_pure_tests/02_data_structures_and_collections.py` | 0 | 0.060s | 14.8 MB | 0 | 0.077s | 52.1 MB | 0 |  |
| `tests/final_pure_tests/03_oop_polymorphism.py` | 0 | 0.061s | 10.0 MB | 0 | 0.160s | 85.3 MB | 0 |  |
| `tests/final_pure_tests/04_loop_mechanics_ground_reality.py` | 0 | 0.785s | 9.9 MB | 0 | 0.584s | 9.9 MB | 0 |  |
| `tests/final_pure_tests/05_edge_cases_and_issues.py` | 0 | 0.123s | 20.3 MB | 0 | 0.004s | 9.9 MB | 0 |  |
| `tests/final_pure_tests/06_multithreading_and_concurrency.py` | 0 | 0.074s | 14.5 MB | 0 | 0.008s | 9.9 MB | 2 | Zython: thread name `Thread` instead of `Thread-1 (worker_task)`; `executor.map` returns list not iterator |
| `tests/final_pure_tests/07_c_extensions_and_ctypes.py` | 1 | 0.166s | 33.1 MB | 0 | 0.004s | 9.9 MB | 16 | CPython cannot import `sample_ext` (a Zython-flavoured .so in the repo root) - expected; Zython loads it |
| `tests/final_pure_tests/08_io_os_socket_and_json.py` | 1 | 0.159s | 32.8 MB | 0 | 0.055s | 9.9 MB | 5 | CPython correctly raises `TypeError: Strings must be encoded before hashing` for `hashlib.sha256('hello world')`; Zython accepts a str (test bug that Zython hides) |

RSS in this table is measured through a forked harness and therefore has a ~10 MB floor inherited from the Python harness; use `MEMORY_AND_STARTUP.md` for clean memory numbers.

