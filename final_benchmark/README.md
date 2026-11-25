# final_benchmark - independent ground-reality audit of Zython vs CPython

Start with **[FINAL_REPORT.md](FINAL_REPORT.md)** (verdict). Details:

* [BENCHMARK_RESULTS.md](BENCHMARK_RESULTS.md) - 15 math/logic programs, time + RSS
* [CLAIMS_VERIFICATION.md](CLAIMS_VERIFICATION.md) - each README claim: true / misleading / false
* [MEMORY_AND_STARTUP.md](MEMORY_AND_STARTUP.md) - startup latency, idle & loaded memory, binary linkage
* [BUGS_FOUND.md](BUGS_FOUND.md) - 21 bugs with reproductions
* [CORRECTNESS_RESULTS.md](CORRECTNESS_RESULTS.md) - 223-snippet differential test vs CPython
* [REPO_TESTS_RESULTS.md](REPO_TESTS_RESULTS.md) - the repo's own `tests/` on both interpreters

Reproduce: `sh run_all.sh` (about 10 minutes). Probes for individual bugs live in `probes/`.
