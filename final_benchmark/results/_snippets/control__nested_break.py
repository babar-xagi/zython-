c = 0
for i in range(5):
    for j in range(5):
        if j > i:
            break
        c += 1
print(c)
