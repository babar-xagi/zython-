def gen(n):
    for i in range(n):
        yield i * i
print(list(gen(4)))
