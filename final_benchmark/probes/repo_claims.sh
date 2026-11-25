#!/bin/sh
cd "$(dirname "$0")/../.."
for f in 01_compute_and_algorithms 02_data_structures_and_collections 03_oop_polymorphism 04_loop_mechanics_ground_reality; do
  echo "##### $f  ZYTHON"
  ./zig-out/bin/zython tests/final_pure_tests/$f.py 2>&1 | grep -v '^$' | cut -c1-140
  echo "##### $f  CPYTHON"
  python3 tests/final_pure_tests/$f.py 2>&1 | grep -v '^$' | cut -c1-140
done
