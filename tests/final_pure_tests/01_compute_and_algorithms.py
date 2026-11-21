import time

print("==========================================")
print("TEST 1: COMPUTE & ALGORITHMS BENCHMARK")
print("==========================================")

# 1. Prime Number Calculation (Trial Division up to 15,000)
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

def run_primes():
    t0 = time.time()
    c = count_primes(15000)
    t1 = time.time()
    print("1. Primes up to 15,000: Count =", c, "| Time:", round(t1 - t0, 5), "s")

# 2. Recursive Fibonacci fib(26)
def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

def run_fib():
    t0 = time.time()
    res = fib(26)
    t1 = time.time()
    print("2. Recursive fib(26): Result =", res, "| Time:", round(t1 - t0, 5), "s")

# 3. Insertion Sort on 1,500 elements (descending to ascending)
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
    return arr

def run_sort():
    test_arr = []
    for idx in range(1500, 0, -1):
        test_arr.append(idx)
    t0 = time.time()
    sorted_arr = insertion_sort(test_arr)
    t1 = time.time()
    print("3. Insertion Sort (1,500 items): First =", sorted_arr[0], "Last =", sorted_arr[1499], "| Time:", round(t1 - t0, 5), "s")

# 4. Taylor Series Approximation of e^x (x=3.5, 30 terms)
def taylor_exp(x, terms):
    total = 1.0
    num = 1.0
    den = 1.0
    for i in range(1, terms):
        num = num * x
        den = den * float(i)
        total = total + (num / den)
    return total

def run_taylor():
    t0 = time.time()
    e_val = taylor_exp(3.5, 30)
    t1 = time.time()
    print("4. Taylor Series exp(3.5, 30 terms): Result =", round(e_val, 6), "| Time:", round(t1 - t0, 5), "s")

run_primes()
run_fib()
run_sort()
run_taylor()
print("Compute & Algorithms benchmark complete.")
