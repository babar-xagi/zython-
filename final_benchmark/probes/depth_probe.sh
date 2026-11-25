#!/bin/sh
Z=../../zig-out/bin/zython
for n in 200 300 400 500 600 700 800 1000 2000; do
  printf 'depth %s: ' $n
  cat > /tmp/_depth.py <<EOF
def r(n):
    if n == 0:
        return 0
    return 1 + r(n - 1)
print(r($n))
EOF
  $Z /tmp/_depth.py 2>&1 | head -2
  echo
done
echo "--- method recursion"
cat > /tmp/_depth2.py <<EOF
def r(n):
    if n == 0:
        return 0
    return 1 + r(n - 1)
print(r(150))
EOF
$Z /tmp/_depth2.py 2>&1 | head -2
