def outer():
    c = 0
    def inc():
        nonlocal c
        c += 1
        return c
    inc()
    return inc()
print(outer())
