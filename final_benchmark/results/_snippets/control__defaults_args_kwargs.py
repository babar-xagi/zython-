def f(a, b=2, *args, **kw):
    return a + b + len(args) + len(kw)
print(f(1, 2, 3, 4, z=1))
