d = {}
for i in range(5):
    d[i] = i * i
del d[2]
d.update({9: 1})
print(d, len(d), d.pop(3), 9 in d)
