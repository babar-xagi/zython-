d = {}
for i in range(1000):
    d['k' + str(i)] = i
print(sum(d.values()), len(d))
