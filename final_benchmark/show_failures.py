import json, sys, os
d = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "results", "correctness.json")))
want = sys.argv[1] if len(sys.argv) > 1 else None
for r in d["results"]:
    if r["status"] == "PASS":
        continue
    if want and r["cat"] != want:
        continue
    print("[%s] %s/%s rc=%s" % (r["status"], r["cat"], r["name"], r["zython_rc"]))
    print("   cpy:", repr(r["cpython_out"][:110]))
    print("   zy :", repr(r["zython_out"][:110]), "|", repr(r["zython_err"][-70:]))
