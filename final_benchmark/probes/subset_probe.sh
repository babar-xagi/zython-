#!/bin/sh
# quick-and-dirty: run small snippets on zython and print outputs
Z=../../zig-out/bin/zython
t() { printf '%s => ' "$1"; $Z -c "$1" 2>&1 | tr '\n' '|'; echo; }
t "a=[1]*5
print(a)"
t "a=[0]*10
a[3]=7
print(a[3], len(a))"
t "import math
print(math.sqrt(16.0), math.pi, math.sin(1.0), math.floor(2.5))"
t "x = 5
x //= 2
x **= 2
x %= 3
print(x)"
t "d = {}
d[1]=2
print(d[1], 1 in d, len(d))"
t "s = 0
for k in [1,2,3]:
    s += k
print(s)"
t "d = {'a':1,'b':2}
for k in d:
    print(k)"
t "print(abs(-3), min(1,2), max(1,2), int(3.7), float(2), str(5))"
t "def f(a, b=2):
    return a+b
print(f(1), f(1,5))"
t "print(2**62, 2**63, 2**64, 3**40)"
t "print(10**18, 10**19)"
t "x = 2**62
print(x*2)"
t "print(7//2, -7//2, 7%3, -7%3, 7.5//2)"
t "print(1e308*10, 0.1+0.2, 1/3)"
t "print(1/0)"
t "def r(n):
    return 0 if n==0 else 1+r(n-1)
print(r(100))
print(r(1000))
print(r(5000))"
t "def r(n):
    return 0 if n==0 else 1+r(n-1)
print(r(20000))"
t "class A:
    def __init__(self):
        self.v=0
    def inc(self):
        self.v += 1
a=A()
for i in range(10):
    a.inc()
print(a.v)"
t "l=[3,1,2]
l.sort()
print(l)
print(sorted([3,1,2]))"
t "print(len('abc'), 'abc'.upper(), 'a,b'.split(','))"
t "x = [i*i for i in range(5)]
print(x)"
t "print(round(2.5), round(3.14159,2))"
t "t=(1,2)
a,b=t
print(a,b)"
t "print(True+True, None is None, not 0)"
t "print('%d' % 5)"
t "print(f'{1.5:.3f}')"
t "i=0
while True:
    i+=1
    if i>5: break
print(i)"
t "print(int('42'), float('1.5'))"
t "import time
print(type(time.perf_counter()))"
