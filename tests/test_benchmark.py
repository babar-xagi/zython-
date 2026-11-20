import time

print("=== Zython Performance Benchmark ===")

# Benchmark 1: Fibonacci (Recursion)
print("\n[1] Running Recursive Fibonacci(28)...")
def fib(n):
    if n <= 1:
        return n
    return fib(n - 1) + fib(n - 2)

t0 = time.time()
res_fib = fib(28)
t1 = time.time()
print("Result fib(28):", res_fib)
print("Time taken:", round(t1 - t0, 4), "seconds")

# Benchmark 2: Prime calculation (Loops & Arithmetic)
print("\n[2] Computing prime count up to 10,000...")
def count_primes(limit):
    count = 0
    for num in range(2, limit):
        is_p = True
        for i in range(2, num):
            if i * i > num:
                break
            if num % i == 0:
                is_p = False
                break
        if is_p:
            count += 1
    return count

t0 = time.time()
prime_count = count_primes(10000)
t1 = time.time()
print("Primes below 10,000:", prime_count)
print("Time taken:", round(t1 - t0, 4), "seconds")

# Benchmark 3: Data structure operations
print("\n[3] List manipulations & Sorting...")
t0 = time.time()
nums = []
for i in range(1000):
    nums.append((i * 37 + 13) % 1000)
sorted_nums = sorted(nums)
t1 = time.time()
print("Sorted first 5:", sorted_nums[0:5])
print("Sorted last 5:", sorted_nums[995:1000])
print("Time taken:", round(t1 - t0, 4), "seconds")

print("\nBenchmark completed successfully!")
