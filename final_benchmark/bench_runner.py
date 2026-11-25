#!/usr/bin/env python3
"""Head-to-head benchmark harness: Zython vs CPython.

For every programs/*.py file:
  * run it N times on each interpreter as a fresh subprocess
  * measure wall time (perf_counter around fork/exec/wait) + user/sys CPU + peak RSS (wait4 ru_maxrss)
  * verify stdout is byte-identical to CPython's (CPython is the oracle)
Writes results/bench.json. Usage: bench_runner.py [reps] [name-filter]
"""
import json
import os
import resource
import statistics
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ZY = os.path.join(HERE, "..", "zig-out", "bin", "zython")
PY = sys.executable
PROG = os.path.join(HERE, "programs")
TIMEOUT = 120


def run_once(exe, path):
    t0 = time.perf_counter()
    p = subprocess.Popen([exe, path], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = p.communicate(timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        p.kill()
        out, err = p.communicate()
        return {"rc": -999, "wall": TIMEOUT, "rss_kb": 0, "out": out.decode(errors="replace"), "err": "TIMEOUT"}
    wall = time.perf_counter() - t0
    # RUSAGE_CHILDREN max is cumulative-max, so use wait4 via a second path: measure with a tiny wrapper
    return {"rc": p.returncode, "wall": wall, "out": out.decode(errors="replace"),
            "err": err.decode(errors="replace")[-300:]}


def run_measured(exe, path):
    """Run once using os.wait4 so we get this child's *own* ru_maxrss."""
    r_out, w_out = os.pipe()
    r_err, w_err = os.pipe()
    t0 = time.perf_counter()
    pid = os.fork()
    if pid == 0:
        os.dup2(w_out, 1)
        os.dup2(w_err, 2)
        for fd in (r_out, w_out, r_err, w_err):
            os.close(fd)
        try:
            os.execv(exe, [exe, path])
        finally:
            os._exit(127)
    os.close(w_out)
    os.close(w_err)
    chunks_o, chunks_e = [], []
    import selectors
    sel = selectors.DefaultSelector()
    sel.register(r_out, selectors.EVENT_READ, chunks_o)
    sel.register(r_err, selectors.EVENT_READ, chunks_e)
    open_fds = 2
    deadline = t0 + TIMEOUT
    timed_out = False
    while open_fds:
        left = deadline - time.perf_counter()
        if left <= 0:
            os.kill(pid, 9)
            timed_out = True
            break
        for key, _ in sel.select(timeout=min(left, 1.0)):
            data = os.read(key.fd, 65536)
            if data:
                key.data.append(data)
            else:
                sel.unregister(key.fd)
                open_fds -= 1
    _, status, ru = os.wait4(pid, 0)
    wall = time.perf_counter() - t0
    os.close(r_out)
    os.close(r_err)
    if os.WIFSIGNALED(status):
        rc = -os.WTERMSIG(status)
    else:
        rc = os.WEXITSTATUS(status)
    return {"rc": -999 if timed_out else rc, "wall": wall, "user": ru.ru_utime, "sys": ru.ru_stime,
            "rss_kb": ru.ru_maxrss, "out": b"".join(chunks_o).decode(errors="replace"),
            "err": b"".join(chunks_e).decode(errors="replace")[-300:]}


def measure_rss_kb(exe, path):
    """Peak RSS via /usr/bin/time (a tiny launcher, so it does not inherit our big RSS floor)."""
    p = subprocess.run(["/usr/bin/time", "-f", "@@RSS %M", exe, path], capture_output=True, timeout=TIMEOUT + 30)
    for ln in reversed(p.stderr.decode(errors="replace").splitlines()):
        if ln.startswith("@@RSS"):
            return int(ln.split()[1])
    return 0


def bench(exe, path, reps):
    runs = [run_measured(exe, path) for _ in range(reps)]
    ok = [r for r in runs if r["rc"] == 0]
    res = {"rc": runs[0]["rc"], "out": runs[0]["out"], "err": runs[0]["err"], "reps": reps}
    if ok:
        walls = [r["wall"] for r in ok]
        res.update({
            "wall_min": min(walls), "wall_median": statistics.median(walls), "wall_max": max(walls),
            "user_median": statistics.median(r["user"] for r in ok),
            "sys_median": statistics.median(r["sys"] for r in ok),
            "rss_kb": max(measure_rss_kb(exe, path) for _ in range(2)),
        })
    return res


def main():
    reps = int(sys.argv[1]) if len(sys.argv) > 1 else 5
    flt = sys.argv[2] if len(sys.argv) > 2 else None
    names = sorted(f for f in os.listdir(PROG) if f.endswith(".py"))
    results = []
    for name in names:
        if flt and flt not in name:
            continue
        path = os.path.join(PROG, name)
        print("==", name, flush=True)
        py = bench(PY, path, reps)
        zy = bench(ZY, path, reps)
        same = (py["out"] == zy["out"]) and zy["rc"] == 0
        entry = {"name": name, "cpython": py, "zython": zy, "output_match": same}
        if "wall_median" in py and "wall_median" in zy:
            entry["speedup_median"] = py["wall_median"] / zy["wall_median"]
        results.append(entry)
        def fmt(x):
            return "%.4fs rss=%dKB" % (x["wall_median"], x["rss_kb"]) if "wall_median" in x else "FAILED rc=%s %s" % (x["rc"], x["err"][-80:])
        print("   cpython:", fmt(py))
        print("   zython :", fmt(zy), "| match:", same,
              ("| speedup x%.2f" % entry["speedup_median"]) if "speedup_median" in entry else "")
    outp = os.path.join(HERE, "results", "bench.json" if not flt else "bench_partial.json")
    os.makedirs(os.path.dirname(outp), exist_ok=True)
    with open(outp, "w") as fh:
        json.dump({"python": sys.version, "reps": reps, "results": results}, fh, indent=1)
    print("wrote", outp)


if __name__ == "__main__":
    main()
