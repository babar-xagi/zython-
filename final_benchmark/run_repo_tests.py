#!/usr/bin/env python3
"""Run the repo's OWN tests/benchmarks (tests/*.py, tests/final_pure_tests/*.py) on both runtimes.
Records exit code, wall time, peak RSS, and whether stdout matches after dropping timing lines."""
import glob
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench_runner as B  # noqa

B.TIMEOUT = 90
ROOT = os.path.join(B.HERE, "..")
files = sorted(glob.glob(os.path.join(ROOT, "tests", "*.py"))) + sorted(glob.glob(os.path.join(ROOT, "tests", "final_pure_tests", "*.py")))
TIMING = re.compile(r"(time|Time|elapsed|sec|ms|\bs\b|\d\.\d{4,})", re.I)


def normalise(out):
    keep = []
    for ln in out.splitlines():
        if re.search(r"\d+\.\d{3,}", ln) and TIMING.search(ln):
            continue
        keep.append(ln.strip())
    return keep


os.chdir(os.path.abspath(ROOT))  # tests load ./sample_ext.so relative to the repo root
res = []
for f in files:
    rel = os.path.relpath(f, ROOT)
    print("==", rel, flush=True)
    py = B.run_measured(B.PY, f)
    zy = B.run_measured(B.ZY, f)
    a, b = normalise(py["out"]), normalise(zy["out"])
    diff = [(x, y) for x, y in zip(a, b) if x != y]
    entry = {"file": rel,
             "cpython": {k: py[k] for k in ("rc", "wall", "rss_kb")},
             "zython": {k: zy[k] for k in ("rc", "wall", "rss_kb")},
             "zython_err": zy["err"][-200:],
             "lines_cpython": len(a), "lines_zython": len(b),
             "line_diffs": len(diff) + abs(len(a) - len(b)),
             "first_diffs": diff[:4],
             "cpython_out_tail": py["out"][-300:], "zython_out_tail": zy["out"][-300:]}
    res.append(entry)
    print("  py rc=%s %.3fs %dKB | zy rc=%s %.3fs %dKB | diffs=%d" % (
        py["rc"], py["wall"], py["rss_kb"], zy["rc"], zy["wall"], zy["rss_kb"], entry["line_diffs"]), flush=True)
with open(os.path.join(B.HERE, "results", "repo_tests.json"), "w") as fh:
    json.dump(res, fh, indent=1)
