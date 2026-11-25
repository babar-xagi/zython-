#!/bin/sh
cd "$(dirname "$0")"
Z=../../zig-out/bin/zython
echo "--- dict.pop bug"
echo ZY; $Z dict_remove_bug.py; echo PY; python3 dict_remove_bug.py
echo "--- memory churn (garbage-only workload)"
for n in 100000 1000000 5000000; do
  sed "s/NNN/$n/" mem_probe.py > /tmp/_mem.py
  echo "N=$n"
  /usr/bin/time -f "zython  %es  peakRSS=%MKB" $Z /tmp/_mem.py
  /usr/bin/time -f "cpython %es  peakRSS=%MKB" python3 /tmp/_mem.py
done
