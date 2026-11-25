import time
def fibonacci(n):
    if n <= 1:
        return n
    return fibonacci(n - 1) + fibonacci(n - 2)
t = time.perf_counter()
r = fibonacci(27)
print("fibonacci(27) =", r, "time", time.perf_counter() - t)
