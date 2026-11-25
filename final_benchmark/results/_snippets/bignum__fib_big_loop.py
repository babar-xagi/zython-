a, b = 0, 1
for _ in range(200):
    a, b = b, a + b
print(a)
