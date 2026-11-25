import time

def bench(label, keys_fn, n):
    t = time.perf_counter()
    d = {}
    for i in range(n):
        d[keys_fn(i)] = i
    t1 = time.perf_counter() - t
    t = time.perf_counter()
    s = 0
    for i in range(n):
        s += d[keys_fn(i)]
    t2 = time.perf_counter() - t
    print(label, n, "insert", round(t1, 4), "lookup", round(t2, 4), s)

def k_seq(i):
    return i

def k_x7(i):
    return i * 7

def k_x1000(i):
    return i * 1000

def k_str(i):
    return "k" + str(i)

for n in (10000, 20000, 40000):
    bench("seq    ", k_seq, n)
    bench("x7     ", k_x7, n)
    bench("x1000  ", k_x1000, n)
    bench("strkey ", k_str, n)
