# Allocation churn: everything allocated here is garbage immediately.
# CPython (refcounting) should stay flat; an arena allocator that never frees will grow linearly.
n = NNN
total = 0
i = 0
while i < n:
    tmp = [i, i + 1, i + 2, i + 3]
    s = "abc" + str(i)
    total += len(tmp) + len(s)
    i += 1
print(total)
