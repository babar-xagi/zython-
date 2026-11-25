#!/bin/sh
cd "$(dirname "$0")/.."
echo "pass" > /tmp/_empty.py
for i in 1 2 3; do
  /usr/bin/time -f "zython  empty  %MKB  %es" ../zig-out/bin/zython /tmp/_empty.py
  /usr/bin/time -f "cpython empty  %MKB  %es" python3 /tmp/_empty.py
done
/usr/bin/time -f "cpython -S -E empty %MKB %es" python3 -S -E /tmp/_empty.py
/usr/bin/time -f "cpython -I -S empty %MKB %es" python3 -I -S /tmp/_empty.py
