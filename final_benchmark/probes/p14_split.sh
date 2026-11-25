#!/bin/sh
Z=../../zig-out/bin/zython
cat > /tmp/_a.py <<'EOF'
import time
t = time.perf_counter()
cache = {}
for i in range(N):
    cache[i * 7] = i
print("dict int insert", N, time.perf_counter() - t)
EOF
for n in 2000 4000 8000 16000 32000 64000; do
  sed "s/N/$n/g" /tmp/_a.py > /tmp/_a2.py
  timeout 60 $Z /tmp/_a2.py
  python3 /tmp/_a2.py
done
cat > /tmp/_b.py <<'EOF'
import time
t = time.perf_counter()
s = ""
for i in range(N):
    s += chr(97 + i % 26)
print("str += ", N, time.perf_counter() - t, len(s))
EOF
for n in 5000 10000 20000 40000 80000; do
  sed "s/N/$n/g" /tmp/_b.py > /tmp/_b2.py
  timeout 60 $Z /tmp/_b2.py
  python3 /tmp/_b2.py
done
cat > /tmp/_c.py <<'EOF'
import time
t = time.perf_counter()
words = []
for i in range(N):
    words.append("w" + str(i % 997))
text = " ".join(words)
parts = text.split(" ")
freq = {}
for w in parts:
    freq[w] = freq.get(w, 0) + 1
print("words", N, time.perf_counter() - t, len(freq))
EOF
for n in 2000 5000 10000 20000 40000; do
  sed "s/N/$n/g" /tmp/_c.py > /tmp/_c2.py
  timeout 60 $Z /tmp/_c2.py
  python3 /tmp/_c2.py
done
