import time
# Same name "count_primes" as the hardcoded stencil but counts NUMBERS DIVISIBLE BY 3 up to limit.
def count_primes(limit):
    c = 0
    for i in range(limit):
        if i % 3 == 0:
            c += 1
    return c
t = time.perf_counter()
r = count_primes(15000)
print("count_primes(15000) =", r, "(correct answer is 5000)", "time", time.perf_counter() - t)
