import threading
import time

def work(n):
    s = 0
    i = 0
    while i < n:
        s += i % 7
        i += 1
    return s

N = 2000000

# serial
t = time.perf_counter()
work(N)
work(N)
work(N)
work(N)
serial = time.perf_counter() - t

# 4 threads
results = []
def runner():
    results.append(work(N))

t = time.perf_counter()
ths = []
for k in range(4):
    th = threading.Thread(target=runner)
    ths.append(th)
    th.start()
for th in ths:
    th.join()
par = time.perf_counter() - t
print("serial 4x:", round(serial, 3), "threads 4x:", round(par, 3), "results:", results)

# race test: unsynchronised shared counter, 4 threads x 200000 increments
counter = [0]
def inc():
    for _ in range(200000):
        counter[0] += 1
ths = []
for k in range(4):
    th = threading.Thread(target=inc)
    ths.append(th)
    th.start()
for th in ths:
    th.join()
print("unsynchronised counter (expected 800000):", counter[0])

# locked counter
lock = threading.Lock()
c2 = [0]
def inc2():
    for _ in range(100000):
        lock.acquire()
        c2[0] += 1
        lock.release()
ths = []
for k in range(4):
    th = threading.Thread(target=inc2)
    ths.append(th)
    th.start()
for th in ths:
    th.join()
print("locked counter (expected 400000):", c2[0])

# shared list append from threads
shared = []
def app():
    for i in range(50000):
        shared.append(i)
ths = []
for k in range(4):
    th = threading.Thread(target=app)
    ths.append(th)
    th.start()
for th in ths:
    th.join()
print("shared list len (expected 200000):", len(shared))
