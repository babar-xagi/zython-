import time
import math

print("=== STARTING FULL BENCHMARK SUITE ===")

# Benchmark 1: 1M While Loop
def bench_1m_while():
    i = 0
    s = 0
    t0 = time.time()
    while i < 1000000:
        s += i
        i += 1
    t1 = time.time()
    print("BENCH_1M_WHILE:", round(t1 - t0, 6), "s, sum =", s)

# Benchmark 2: 10M For Loop
def bench_10m_for():
    s = 0
    t0 = time.time()
    for i in range(10000000):
        s += i
    t1 = time.time()
    print("BENCH_10M_FOR:", round(t1 - t0, 6), "s, sum =", s)

# Benchmark 3: 50M Math Loop
def bench_50m_loop():
    s = 0
    t0 = time.time()
    for i in range(50000000):
        s += 1
    t1 = time.time()
    print("BENCH_50M_LOOP:", round(t1 - t0, 6), "s, sum =", s)

# Benchmark 4: Fibonacci(30) Recursion
def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

def bench_fib():
    t0 = time.time()
    res = fib(30)
    t1 = time.time()
    print("BENCH_FIB_30:", round(t1 - t0, 6), "s, res =", res)

# Benchmark 5: Prime Calculation up to 25,000
def bench_primes():
    t0 = time.time()
    count = 0
    for num in range(2, 25000):
        is_p = True
        for i in range(2, num):
            if i * i > num:
                break
            if num % i == 0:
                is_p = False
                break
        if is_p:
            count += 1
    t1 = time.time()
    print("BENCH_PRIMES_25K:", round(t1 - t0, 6), "s, count =", count)

# Benchmark 6: OOP 100k Object Instances & Methods
class Item:
    def __init__(self, val):
        self.val = val

    def compute(self, mul):
        return self.val * mul

def bench_oop():
    t0 = time.time()
    acc = 0
    for i in range(100000):
        obj = Item(i)
        acc += obj.compute(2)
    t1 = time.time()
    print("BENCH_OOP_100K:", round(t1 - t0, 6), "s, acc =", acc)

# Benchmark 7: 100k List Append & Access
def bench_list():
    t0 = time.time()
    items = []
    for i in range(100000):
        items.append(i * 2)
    s = 0
    for x in items:
        s += x
    t1 = time.time()
    print("BENCH_LIST_100K:", round(t1 - t0, 6), "s, sum =", s)

# Benchmark 8: 50k Dict Key-Value Operations
def bench_dict():
    t0 = time.time()
    d = {}
    for i in range(50000):
        d[str(i)] = i * 3
    s = 0
    for i in range(50000):
        s += d.get(str(i), 0)
    t1 = time.time()
    print("BENCH_DICT_50K:", round(t1 - t0, 6), "s, sum =", s)

bench_1m_while()
bench_10m_for()
bench_50m_loop()
bench_fib()
bench_primes()
bench_oop()
bench_list()
bench_dict()

print("=== BENCHMARK SUITE FINISHED ===")
