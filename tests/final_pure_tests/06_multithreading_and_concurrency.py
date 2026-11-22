import time
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

print("==========================================")
print("TEST 6: MULTI-THREADING & CONCURRENCY")
print("==========================================")

# 1. Thread Creation, Arguments, Ident & Join
results = []
def worker_task(val, multiplier):
    results.append(val * multiplier)

t1 = threading.Thread(target=worker_task, args=(10, 2))
t2 = threading.Thread(target=worker_task, args=(20, 3))
print("1. Thread Initialization: name1 =", t1.name, "| is_alive before start =", t1.is_alive())

t0 = time.time()
t1.start()
t2.start()
t1.join()
t2.join()
t1_elapsed = time.time() - t0

print("   -> Thread Execution: results =", sorted(results), "| is_alive after join =", t1.is_alive())

# 2. Mutex Locking (threading.Lock)
counter = 0
lock = threading.Lock()

def safe_increment(n):
    global counter
    for i in range(n):
        with lock:
            counter += 1

threads = [threading.Thread(target=safe_increment, args=(200,)) for _ in range(5)]
for t in threads:
    t.start()
for t in threads:
    t.join()

print("2. Mutex Lock (threading.Lock): Counter (expected 1000) =", counter)

# 3. Reentrant Lock (threading.RLock)
rlock = threading.RLock()
rlock_success = False

def reentrant_work():
    global rlock_success
    with rlock:
        with rlock:
            with rlock:
                rlock_success = True

t_rlock = threading.Thread(target=reentrant_work)
t_rlock.start()
t_rlock.join()
print("3. Reentrant Lock (threading.RLock): Reentrancy succeeded =", rlock_success)

# 4. Semaphore (threading.Semaphore)
sem = threading.Semaphore(2)
sem_acquired = 0

def sem_worker():
    global sem_acquired
    with sem:
        sem_acquired += 1

t_sem1 = threading.Thread(target=sem_worker)
t_sem2 = threading.Thread(target=sem_worker)
t_sem1.start()
t_sem2.start()
t_sem1.join()
t_sem2.join()
print("4. Semaphore (threading.Semaphore): Acquired count =", sem_acquired)

# 5. Thread Signaling (threading.Event)
event = threading.Event()
event_signaled = False

def event_waiter():
    global event_signaled
    if event.wait():
        event_signaled = True

t_ev = threading.Thread(target=event_waiter)
t_ev.start()
event.set()
t_ev.join()
print("5. Thread Signaling (threading.Event): Signaled successfully =", event_signaled)

# 6. ThreadPoolExecutor Submit & Future Result
def square(n):
    return n * n

with ThreadPoolExecutor(max_workers=4) as pool:
    fut1 = pool.submit(square, 12)
    fut2 = pool.submit(square, 15)
    r1 = fut1.result()
    r2 = fut2.result()
    print("6. ThreadPoolExecutor Submit: 12^2 =", r1, "| 15^2 =", r2, "| done =", fut1.done())

# 7. ThreadPoolExecutor Map
with ThreadPoolExecutor(max_workers=4) as pool:
    map_res = pool.map(square, [1, 2, 3, 4, 5, 6])
    print("7. ThreadPoolExecutor Map: square([1..6]) =", map_res)

# 8. As Completed Iterator
with ThreadPoolExecutor(max_workers=4) as pool:
    futures = [pool.submit(square, i) for i in [7, 8, 9]]
    completed_vals = [f.result() for f in as_completed(futures)]
    print("8. As Completed (as_completed):", sorted(completed_vals))

print("Multi-Threading & Concurrency evaluation complete.")
