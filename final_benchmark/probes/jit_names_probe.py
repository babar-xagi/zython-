# The repo's published numbers use these exact function names. Same algorithm, two names.
import time

def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

def fibx(n):
    if n <= 1:
        return n
    return fibx(n - 1) + fibx(n - 2)

def count_primes(limit):
    count = 0
    for num in range(2, limit):
        is_prime = True
        for i in range(2, num):
            if i * i > num:
                break
            if num % i == 0:
                is_prime = False
                break
        if is_prime:
            count += 1
    return count

def count_primes_x(limit):
    count = 0
    for num in range(2, limit):
        is_prime = True
        for i in range(2, num):
            if i * i > num:
                break
            if num % i == 0:
                is_prime = False
                break
        if is_prime:
            count += 1
    return count

def insertion_sort(arr):
    n = len(arr)
    i = 1
    while i < n:
        key = arr[i]
        j = i - 1
        while j >= 0 and arr[j] > key:
            arr[j + 1] = arr[j]
            j -= 1
        arr[j + 1] = key
        i += 1
    return len(arr)

def insertion_sort_x(arr):
    n = len(arr)
    i = 1
    while i < n:
        key = arr[i]
        j = i - 1
        while j >= 0 and arr[j] > key:
            arr[j + 1] = arr[j]
            j -= 1
        arr[j + 1] = key
        i += 1
    return len(arr)

def timeit(label, fn, arg):
    t = time.perf_counter()
    r = fn(arg)
    d = time.perf_counter() - t
    print(label, "->", r, "time", round(d, 6))

timeit("fib(30)            [hardcoded name]", fib, 30)
timeit("fibx(30)           [renamed copy  ]", fibx, 30)
timeit("count_primes(30000) [hardcoded name]", count_primes, 30000)
timeit("count_primes_x(30000)[renamed copy ]", count_primes_x, 30000)
timeit("insertion_sort(3000)[hardcoded name]", insertion_sort, list(range(3000, 0, -1)))
timeit("insertion_sort_x(3000)[renamed copy ]", insertion_sort_x, list(range(3000, 0, -1)))
