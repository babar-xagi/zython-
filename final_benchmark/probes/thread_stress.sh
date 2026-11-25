#!/bin/sh
cd "$(dirname "$0")"
cat > /tmp/_ts.py <<'EOF'
import threading
shared = []
d = {}
def app(k):
    for i in range(30000):
        shared.append(i)
        d[k * 100000 + i] = i
ths = []
for k in range(4):
    th = threading.Thread(target=app, args=(k,))
    ths.append(th)
    th.start()
for th in ths:
    th.join()
print(len(shared), len(d))
EOF
for i in 1 2 3 4 5 6; do
  timeout 60 ../../zig-out/bin/zython /tmp/_ts.py
  echo "exit=$?"
done
echo "CPYTHON:"; python3 /tmp/_ts.py
