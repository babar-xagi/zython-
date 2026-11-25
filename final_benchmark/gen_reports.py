#!/usr/bin/env python3
"""Generate the data-driven markdown reports from results/*.json (no hand-copied numbers)."""
import json, math, os

HERE = os.path.dirname(os.path.abspath(__file__))
R = os.path.join(HERE, "results")


def load(n):
    return json.load(open(os.path.join(R, n)))


def geomean(xs):
    return math.exp(sum(math.log(x) for x in xs) / len(xs))


# ------------------------------------------------------------------ benchmark results
b = load("bench.json")
rows = []
sp = []
lines = []
lines.append("# BENCHMARK_RESULTS.md - 15 complex math/logic programs, Zython vs CPython\n")
lines.append("Interpreter versions: Zython 0.10.0 (ReleaseFast, Zig 0.17.1) vs `%s`.  " % b["python"].split("\n")[0])
lines.append("Each program ran **%d times per interpreter** as a fresh process; table shows the **median wall time** "
             "(min-max in brackets) and **peak RSS** (via `/usr/bin/time`). Output of every program was compared "
             "byte-for-byte with CPython's.\n" % b["reps"])
lines.append("| # | Program | CPython median (s) | Zython median (s) | Zython speed vs CPython | Output identical | CPython RSS | Zython RSS |")
lines.append("|---|---|---:|---:|---:|:---:|---:|---:|")
wins = 0
for e in b["results"]:
    c, z = e["cpython"], e["zython"]
    s = e.get("speedup_median")
    if s:
        sp.append(s)
        if s > 1.05:
            wins += 1
    verdict = "n/a" if not s else ("**%.2fx faster**" % s if s >= 1.05 else ("**%.2fx slower**" % (1 / s) if s <= 0.95 else "~equal (%.2fx)" % s))
    lines.append("| %s | `%s` | %.4f (%.4f-%.4f) | %.4f (%.4f-%.4f) | %s | %s | %.1f MB | %.1f MB |" % (
        e["name"][1:3], e["name"][4:-3], c["wall_median"], c["wall_min"], c["wall_max"],
        z["wall_median"], z["wall_min"], z["wall_max"], verdict, "YES" if e["output_match"] else "**NO**",
        c["rss_kb"] / 1024, z["rss_kb"] / 1024))
lines.append("")
lines.append("## Aggregate\n")
lines.append("* Programs where Zython is clearly faster (>1.05x): **%d / %d**" % (wins, len(sp)))
lines.append("* Programs where Zython is clearly slower (<0.95x): **%d / %d**" % (sum(1 for s in sp if s < 0.95), len(sp)))
lines.append("* Geometric-mean speed ratio (CPython time / Zython time): **%.2fx**  (1.0 = parity)" % geomean(sp))
lines.append("* Best case: **%.2fx**   Worst case: **%.2fx**" % (max(sp), min(sp)))
lines.append("* Programs with output identical to CPython: **%d / %d**" % (sum(1 for e in b["results"] if e["output_match"]), len(b["results"])))
lines.append("")
lines.append("> Repo claim being tested: *\"39x-55x faster on compute, 1.46x-2.12x on loops\"*. "
             "On general workloads the geometric mean is **%.2fx** - i.e. Zython is on average *slightly slower* than CPython 3.14, not 40x faster. "
             "See `CLAIMS_VERIFICATION.md` for why the repo's headline numbers do not generalise." % geomean(sp))
lines.append("")
lines.append("## Adjustments I had to make so Zython could run the programs at all\n")
lines.append("Zython could not run the first drafts of several programs (see `BUGS_FOUND.md`). To still get a timing I made the "
             "*minimum* source edits, listed here so the comparison stays transparent:\n")
lines.append("* `p01`: `ackermann(2, 300)` -> `ackermann(2, 200)`; Zython segfaults for recursion deeper than ~500 frames (BUG-Z01).")
lines.append("* `p02`, `p14`, `p15`: `return a, b` (tuple return) is a **ParseError** in Zython -> rewritten `return (a, b)`; `n, l = f()` tuple-unpack of a call result -> indexed access; `x not in d` is a ParseError -> `not (x in d)`.")
lines.append("* `p14`: shrunk workload (memo-collatz limit 60000 -> 2500, histogram 150000 -> 60000 samples over 400 keys instead of 5000). "
             "At the original size Zython **did not finish in 120 s** (CPython: 0.15 s) because int-keyed dicts are O(n) linear scans (BUG-Z05).")
lines.append("* `p11`: uses hand-written sorts because `list.sort()`, `sorted(key=,reverse=)` are missing / silently ignore arguments (BUG-Z08).")
lines.append("* All programs keep every intermediate value below 2**63 because Zython silently wraps on int64 overflow (BUG-Z02); "
             "using Python's real big-int semantics would give **wrong answers** on Zython.")
lines.append("* No program uses the names `fib`, `count_primes`, `insertion_sort`, `taylor_exp`, `compute_step`, which Zython's JIT special-cases by *name* (BUG-Z03).")
open(os.path.join(HERE, "BENCHMARK_RESULTS.md"), "w").write("\n".join(lines) + "\n")

# ------------------------------------------------------------------ correctness
c = load("correctness.json")
L = ["# CORRECTNESS_RESULTS.md - differential test, Zython vs CPython 3.14\n",
     "%d tiny snippets, each run in its **own process** on both interpreters; CPython is the oracle; stdout must match byte-for-byte.\n" % len(c["results"]),
     "Status legend: PASS = identical output, WRONG = ran but printed something different (silent wrong answer), ERROR = Zython raised/exited non-zero where CPython succeeded, CRASH = segfault.\n",
     "| Category | Total | PASS | WRONG output | Zython error | CRASH | Pass rate |", "|---|---:|---:|---:|---:|---:|---:|"]
tot = {"PASS": 0, "WRONG": 0, "ZY_ERROR": 0, "CRASH": 0}
n_all = 0
for cat, v in c["counts"].items():
    n = sum(v.values())
    n_all += n
    for k in tot:
        tot[k] += v.get(k, 0)
    L.append("| %s | %d | %d | %d | %d | %d | %.0f%% |" % (cat, n, v.get("PASS", 0), v.get("WRONG", 0), v.get("ZY_ERROR", 0), v.get("CRASH", 0), 100.0 * v.get("PASS", 0) / n))
L.append("| **TOTAL** | **%d** | **%d** | **%d** | **%d** | **%d** | **%.0f%%** |" % (n_all, tot["PASS"], tot["WRONG"], tot["ZY_ERROR"], tot["CRASH"], 100.0 * tot["PASS"] / n_all))
L.append("")
L.append("**Silent wrong answers (`WRONG`) are the most dangerous category** - the program keeps running and prints a plausible but incorrect result.\n")
for status, title in (("WRONG", "Silent wrong output"), ("CRASH", "Crashes (segfault)"), ("ZY_ERROR", "Zython errors where CPython works")):
    L.append("## %s\n" % title)
    L.append("| Snippet | CPython printed | Zython printed / error |")
    L.append("|---|---|---|")
    for r in c["results"]:
        if r["status"] != status:
            continue
        cp = r["cpython_out"].strip().replace("\n", " / ").replace("|", "\\|")[:70]
        zp = (r["zython_out"].strip().replace("\n", " / ").replace("|", "\\|")[:50] or "") + ((" `" + r["zython_err"].strip().split("\n")[-1][:40] + "`") if r["zython_err"] and status != "WRONG" else "")
        if status == "CRASH":
            zp = "segfault (rc=%s)" % r["zython_rc"]
        L.append("| `%s/%s` | `%s` | %s |" % (r["cat"], r["name"], cp, ("`%s`" % zp.strip()) if status == "WRONG" else zp))
    L.append("")
open(os.path.join(HERE, "CORRECTNESS_RESULTS.md"), "w").write("\n".join(L) + "\n")

# ------------------------------------------------------------------ repo tests
t = load("repo_tests.json")
L = ["# REPO_TESTS_RESULTS.md - the repo's own tests/benchmarks run on both interpreters\n",
     "Source files: `tests/*.py` and `tests/final_pure_tests/*.py`. Wall time / RSS are for the whole process (includes startup). "
     "`diff lines` = output lines that differ after dropping lines that contain timings.\n",
     "| File | CPython rc | CPython time | CPython RSS | Zython rc | Zython time | Zython RSS | diff lines | Note |",
     "|---|---:|---:|---:|---:|---:|---:|---:|---|"]
notes = {"tests/billion_loop_bench.py": "CPython killed at the 90 s timeout; Zython finishes in ms via closed-form loop folding (not execution)",
         "tests/final_pure_tests/06_multithreading_and_concurrency.py": "Zython: thread name `Thread` instead of `Thread-1 (worker_task)`; `executor.map` returns list not iterator",
         "tests/final_pure_tests/07_c_extensions_and_ctypes.py": "CPython cannot import `sample_ext` (a Zython-flavoured .so in the repo root) - expected; Zython loads it",
         "tests/final_pure_tests/08_io_os_socket_and_json.py": "CPython correctly raises `TypeError: Strings must be encoded before hashing` for `hashlib.sha256('hello world')`; Zython accepts a str (test bug that Zython hides)"}
for e in t:
    L.append("| `%s` | %s | %.3fs | %.1f MB | %s | %.3fs | %.1f MB | %d | %s |" % (
        e["file"], e["cpython"]["rc"], e["cpython"]["wall"], e["cpython"]["rss_kb"] / 1024,
        e["zython"]["rc"], e["zython"]["wall"], e["zython"]["rss_kb"] / 1024, e["line_diffs"], notes.get(e["file"], "")))
L.append("")
L.append("RSS in this table is measured through a forked harness and therefore has a ~10 MB floor inherited from the Python harness; use `MEMORY_AND_STARTUP.md` for clean memory numbers.\n")
open(os.path.join(HERE, "REPO_TESTS_RESULTS.md"), "w").write("\n".join(L) + "\n")
print("reports generated; geomean speed ratio = %.3f" % geomean(sp))
