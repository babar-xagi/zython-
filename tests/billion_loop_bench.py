import time

print("=== STARTING MILLION & BILLION LOOP BENCHMARK ===")

# 1. 100 Million Loop
print("\n--- 100 MILLION ITERATIONS (s += 1) ---")
t0 = time.time()
s = 0
for i in range(100000000):
    s += 1
t1 = time.time()
print("100M Loop Time:", round(t1 - t0, 6), "s | sum =", s)

# 2. 1 Billion Loop
print("\n--- 1 BILLION ITERATIONS (s += 1) ---")
t0 = time.time()
s = 0
for i in range(1000000000):
    s += 1
t1 = time.time()
print("1 BILLION Loop Time:", round(t1 - t0, 6), "s | sum =", s)

# 3. 1 Billion Accumulation
print("\n--- 1 BILLION ACCUMULATION (s += i) ---")
t0 = time.time()
s = 0
for i in range(1000000000):
    s += i
t1 = time.time()
print("1 BILLION Accumulation Time:", round(t1 - t0, 6), "s | sum =", s)

# 4. 100 Million While Loop
print("\n--- 100 MILLION WHILE LOOP (s += i; i += 1) ---")
t0 = time.time()
i = 0
s = 0
while i < 100000000:
    s += i
    i += 1
t1 = time.time()
print("100M While Loop Time:", round(t1 - t0, 6), "s | sum =", s)

print("\n=== MILLION & BILLION BENCHMARK COMPLETE ===")
