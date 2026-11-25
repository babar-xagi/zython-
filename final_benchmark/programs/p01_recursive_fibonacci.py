# Naive double recursion. Deliberately NOT named "fib" (the repo's JIT hardcodes that name).
def fibonacci_rec(n):
    if n < 2:
        return n
    return fibonacci_rec(n - 1) + fibonacci_rec(n - 2)

def ackermann(m, n):
    if m == 0:
        return n + 1
    if n == 0:
        return ackermann(m - 1, 1)
    return ackermann(m - 1, ackermann(m, n - 1))

def tak(x, y, z):
    if y < x:
        return tak(tak(x - 1, y, z), tak(y - 1, z, x), tak(z - 1, x, y))
    return z

print("fib(30) =", fibonacci_rec(30))
print("ackermann(2, 200) =", ackermann(2, 200))
print("tak(18, 12, 6) =", tak(18, 12, 6))
