#!/bin/sh
Z=../../zig-out/bin/zython
t() { printf '%s => ' "$1"; $Z -c "$1" 2>&1 | tr '\n' '|'; echo; }
t "def f(n):
    steps = 1
    while n != 1:
        if n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps
print(f(27))"
t "def f():
    n = 1
    best_n = 0
    return best_n, n
n, l = f()
print(n, l)"
t "n, l = 1, 2
print('x:', n, l)"
t "def f():
    return 1, 2
print(f())"
t "print('a', (1, 2))"
t "cache = {1: 1}
print(cache[1])
print(2 in cache)
print(2 not in cache)"
t "n = 5
cache = {1: 1}
while n not in cache:
    n = n - 1
print(n)"
t "path = []
path.append(1)
print(len(path))
for idx in range(len(path)):
    print(idx)"
t "words = ['a', 'b']
text = ' '.join(words)
print(text.split(' '))"
t "d = {}
print(d.get('a', 0) + 1)"
t "s = 'abc'
for ch in s:
    print(ch)"
t "print('a' or 'b')
x = 1
if x == 1 or x == 2:
    print('y')"
t "stack = [(1, 2)]
cur = stack.pop()
print(cur[0], cur[1])"
t "for row in [[1],[2]]:
    for v in row:
        print(v)"
t "def f(a):
    return a
x = [f(i) for i in range(3)]
print(x)"
t "x = [1 if i % 2 == 0 else 0 for i in range(4)]
print(x)"
t "while True:
    break
print('ok')"
t "g = [[1,2],[3,4]]
print(g[(0 - 1) % 2])"
t "for gen in range(3):
    print(gen)"
t "print(hist if False else 1)"
t "hist = {}
k = 3
if k in hist:
    hist[k] += 1
else:
    hist[k] = 1
print(hist)"
t "x = 0
for k in {1: 2}:
    x += k
print(x)"
t "print(len([]) > 0)
stack = [1]
while len(stack) > 0:
    stack.pop()
print('done')"
t "ni = 1
nj = 2
if ni >= 0 and ni < 3 and nj >= 0 and nj < 3:
    print('in')"
t "print(chr(97 + 5), 'x'.upper())"
t "freq = {}
w = 'a'
freq[w] = freq.get(w, 0) + 1
print(freq['a'])"
