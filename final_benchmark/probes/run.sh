#!/bin/sh
cd "$(dirname "$0")"
for f in fib_named_fib fib_renamed fib_variant_same_name count_primes_variant; do
  echo "== $f"
  printf "zython: "; ../../zig-out/bin/zython $f.py 2>&1 | head -5
  printf "python: "; python3 $f.py
done
