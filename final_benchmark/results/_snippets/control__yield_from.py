def a():
    yield from [1, 2]
    yield 3
print(list(a()))
