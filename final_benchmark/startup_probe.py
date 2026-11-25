#!/usr/bin/env python3
"""Startup latency + baseline RSS of an empty program. Also binary linkage info.

Latency: a shell loop launches the interpreter 300 times; per-launch = total/300 (shell fork cost included
for BOTH, and measured separately with /bin/true as a floor).
RSS: /usr/bin/time (tiny launcher => no inherited RSS floor).
"""
import os, subprocess, sys, json, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench_runner as B

empty = os.path.join(B.HERE, "results", "_empty.py")
open(empty, "w").write("pass\n")
hello = os.path.join(B.HERE, "results", "_hello.py")
open(hello, "w").write("print('hello')\n")
N = 300


def loop_ms(cmd):
    script = "i=0; while [ $i -lt %d ]; do %s >/dev/null 2>&1; i=$((i+1)); done" % (N, cmd)
    best = 1e9
    for _ in range(3):
        t = time.perf_counter()
        subprocess.run(["sh", "-c", script])
        best = min(best, (time.perf_counter() - t) * 1000 / N)
    return best


out = {"launch_floor_true_ms": loop_ms("/bin/true")}
for label, exe in (("cpython", B.PY), ("zython", B.ZY)):
    for pname, prog in (("empty", empty), ("hello", hello)):
        ms = loop_ms("%s %s" % (exe, prog))
        rss = B.measure_rss_kb(exe, prog)
        out[label + "_" + pname] = {"per_launch_ms": ms, "minus_floor_ms": ms - out["launch_floor_true_ms"], "rss_kb": rss}
        print(label, pname, out[label + "_" + pname], flush=True)
out["cpython_isolated_empty"] = {"per_launch_ms": loop_ms("%s -I -S %s" % (B.PY, empty)),
                                 "rss_kb": B.measure_rss_kb(B.PY, "-I -S") if False else 0}
out["zython_binary_bytes"] = os.path.getsize(B.ZY)
ldd = subprocess.run(["ldd", B.ZY], capture_output=True, text=True)
out["zython_ldd"] = ldd.stdout + ldd.stderr
out["zython_file"] = subprocess.run(["file", B.ZY], capture_output=True, text=True).stdout
print(out["zython_ldd"], out["zython_file"], out["cpython_isolated_empty"])
json.dump(out, open(os.path.join(B.HERE, "results", "startup.json"), "w"), indent=1)
