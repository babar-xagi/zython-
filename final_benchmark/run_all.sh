#!/bin/sh
# Reproduce every result in this folder. Requires zig 0.17.x and python3 (3.14.4 used for the reports).
set -e
cd "$(dirname "$0")"
(cd .. && zig build -Doptimize=ReleaseFast)
mkdir -p results
python3 bench_runner.py 5            # -> results/bench.json
python3 diff_tester.py               # -> results/correctness.json
python3 run_repo_tests.py            # -> results/repo_tests.json
python3 startup_probe.py             # -> results/startup.json
(cd probes && python3 method_matrix.py > ../results/feature_matrix.txt 2>&1)
(cd probes && sh repo_claims.sh > ../results/repo_claims_output.txt 2>&1)
python3 gen_reports.py               # -> BENCHMARK_RESULTS.md, CORRECTNESS_RESULTS.md, REPO_TESTS_RESULTS.md
echo "done. Read FINAL_REPORT.md"
