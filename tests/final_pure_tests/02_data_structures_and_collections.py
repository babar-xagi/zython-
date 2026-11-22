import time

print("==========================================")
print("TEST 2: DATA STRUCTURES & COLLECTIONS")
print("==========================================")

def run_list_bench():
    t0 = time.time()
    lst = []
    for i in range(80000):
        lst.append(i * 3)

    s_list = 0
    for val in lst:
        s_list += val

    for _ in range(10000):
        lst.pop()

    t1 = time.time()
    print("1. List (80k appends, sum & 10k pops): Len =", len(lst), "Sum =", s_list, "| Time:", round(t1 - t0, 5), "s")

def run_dict_bench():
    t0 = time.time()
    d = {}
    for i in range(40000):
        d[str(i)] = i * 2

    s_dict = 0
    for i in range(40000):
        s_dict += d.get(str(i), 0)

    k_list = d.keys()
    v_list = d.values()

    t1 = time.time()
    print("2. Dict (40k keys, get & keys/values): Sum =", s_dict, "Keys =", len(k_list), "| Time:", round(t1 - t0, 5), "s")

def run_tuple_bench():
    t0 = time.time()
    t_acc = 0
    for i in range(30000):
        tup = (i, i + 1, i + 2)
        t_acc += tup[0] + tup[1] + tup[2]

    t1 = time.time()
    print("3. Tuple (30k allocations & access): Acc =", t_acc, "| Time:", round(t1 - t0, 5), "s")

def run_string_bench():
    t0 = time.time()
    base = "apple,banana,cherry,dates,elderberry"
    str_ops_len = 0
    for i in range(10000):
        parts = base.split(",")
        upper_joined = " - ".join(parts).upper()
        str_ops_len += len(upper_joined)

    t1 = time.time()
    print("4. String Methods (10k split/join/upper): Total Len =", str_ops_len, "| Time:", round(t1 - t0, 5), "s")

run_list_bench()
run_dict_bench()
run_tuple_bench()
run_string_bench()
print("Data Structures & Collections benchmark complete.")
