import time

# 1. loop variable must be left at n-1 after the loop
s = 0
for i in range(1000):
    s += 1
print("after loop i =", i, "(CPython: 999) s =", s)

# 2. overflow: sum of 1,000,000 consecutive ints near 2**62 does not fit in int64
s = 0
for i in range(4611686018427387904, 4611686018427387904 + 1000000):
    s += i
print("sum near 2**62 =", s, "(CPython: 4611686018427387904000000+499999500000 = 4611686018427887903500000 )")

# 3. float accumulator
s = 0.5
for i in range(1000000):
    s += 1
print("float acc =", s, "(CPython: 1000000.5)")

# 4. accumulator type string-ish / list should not be folded
s = 0
for i in range(100000):
    s += 2
print("s+=2:", s, "(CPython: 200000)")

# 5. other fold pattern: s += i * i  (not a known closed form to the peephole?)
t = time.perf_counter()
s = 0
for i in range(5000000):
    s += i * i
d1 = time.perf_counter() - t
print("s += i*i  =", s, "took", round(d1, 4), "(CPython: 41666654166667500000 -> bignum)")

# 6. s += i % 3 (non-closed-form)
t = time.perf_counter()
s = 0
for i in range(5000000):
    s += i % 3
d2 = time.perf_counter() - t
print("s += i % 3 =", s, "took", round(d2, 4), "(CPython: 7500000 - wait check)")

# 7. same simple loop but with an extra statement -> pattern breaks
t = time.perf_counter()
s = 0
c = 0
for i in range(5000000):
    s += 1
    c += 1
d3 = time.perf_counter() - t
print("two accumulators:", s, c, "took", round(d3, 4))

# 8. while-loop fold with side effect
i = 0
s = 0
while i < 3000000:
    s += i
    i += 1
print("while fold s =", s, "i =", i)

# 9. loop body with an if
t = time.perf_counter()
s = 0
for i in range(5000000):
    if i % 2 == 0:
        s += 1
d4 = time.perf_counter() - t
print("if-branch loop:", s, "took", round(d4, 4))
