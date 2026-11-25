s = 0
for i in range(10, 20):
    s += i
print("range(10,20) sum:", s, "(expected 145)")

s = 0
for i in range(0, 100, 5):
    s += i
print("range(0,100,5) sum:", s, "(expected 950)")

s = 0
for i in range(5, 0, -1):
    s += i
print("range(5,0,-1) sum:", s, "(expected 15)")

def f():
    s = 0
    for i in range(100, 200):
        s += i
    return s
print("in function range(100,200):", f(), "(expected 14950)")

s = 0
for i in range(1000000, 1000010):
    s += i
print("range(1000000,1000010):", s, "(expected 10000045)")
