import time
def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)
t = time.perf_counter()
r = fib(27)
print("fib(27) =", r, "time", time.perf_counter() - t)
