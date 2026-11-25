import time
# Same name "fib" but DIFFERENT semantics: base case returns 7 instead of n.
# Real fib(20) with base 7 is 7 * fib_std(21) = 7*10946 = 76622 ; stock fib(20)=6765.
def fib(n):
    if n <= 1:
        return 7
    return fib(n - 1) + fib(n - 2)
t = time.perf_counter()
r = fib(20)
print("variant fib(20) =", r, "(correct answer is 76622)", "time", time.perf_counter() - t)
