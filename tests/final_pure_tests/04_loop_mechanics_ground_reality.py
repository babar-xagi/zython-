import time

print("==========================================")
print("TEST 4: LOOP MECHANICS & GROUND REALITY")
print("==========================================")

def run_pattern_matched():
    t0 = time.time()
    s_spec = 0
    for i in range(10000000):
        s_spec += 1
    t1 = time.time()
    print("1. Pattern-Matched Loop (for i in range(10M): s += 1): Result =", s_spec, "| Time:", round(t1 - t0, 6), "s")

def run_unspecialized():
    t0 = time.time()
    s_unspec = 0
    for i in range(2000000):
        s_unspec = s_unspec + 1
    t1 = time.time()
    print("2. Unspecialized Simple Loop (for i in range(2M): s = s + 1): Result =", s_unspec, "| Time:", round(t1 - t0, 5), "s")

def run_branching():
    t0 = time.time()
    s_branch = 0
    for i in range(2000000):
        if i % 2 == 0:
            s_branch += i
        else:
            s_branch += 1
    t1 = time.time()
    print("3. Branching Loop (2M iterations with if/else): Result =", s_branch, "| Time:", round(t1 - t0, 5), "s")

def run_multistatement():
    t0 = time.time()
    s_multi = 0
    for i in range(1000000):
        a = i * 2
        b = a + 3
        s_multi += b
    t1 = time.time()
    print("4. Multi-statement Loop (1M iterations): Result =", s_multi, "| Time:", round(t1 - t0, 5), "s")

def run_nested_2d():
    t0 = time.time()
    total_grid = 0
    for x in range(1000):
        for y in range(1000):
            total_grid += x * y
    t1 = time.time()
    print("5. Nested 2D Loop (1,000 x 1,000): Result =", total_grid, "| Time:", round(t1 - t0, 5), "s")

def compute_step(val, inc):
    return val + inc

def run_function_loop():
    t0 = time.time()
    s_func = 0
    for i in range(400000):
        s_func = compute_step(s_func, i)
    t1 = time.time()
    print("6. Function Call in Loop (400k calls): Result =", s_func, "| Time:", round(t1 - t0, 5), "s")

run_pattern_matched()
run_unspecialized()
run_branching()
run_multistatement()
run_nested_2d()
run_function_loop()
print("Loop mechanics benchmark complete.")
