# Numerical analysis: Simpson integration, Newton-Raphson, Taylor series, Leibniz pi, trapezoid
import math

def f_poly(x):
    return x * x * x - 2.0 * x * x + 3.0 * x - 5.0

def simpson(f, a, b, n):
    h = (b - a) / n
    s = f(a) + f(b)
    i = 1
    while i < n:
        if i % 2 == 1:
            s += 4.0 * f(a + i * h)
        else:
            s += 2.0 * f(a + i * h)
        i += 1
    return s * h / 3.0

def f_sin(x):
    return math.sin(x) * math.cos(x)

def newton_sqrt(v):
    g = v / 2.0
    for _ in range(40):
        g = 0.5 * (g + v / g)
    return g

def taylor_exp_series(x, terms):
    total = 1.0
    term = 1.0
    for i in range(1, terms):
        term = term * x / i
        total += term
    return total

def leibniz(n):
    s = 0.0
    sign = 1.0
    for k in range(n):
        s += sign / (2 * k + 1)
        sign = -sign
    return 4.0 * s

print("simpson poly:", round(simpson(f_poly, 0.0, 10.0, 200000), 6))
print("simpson sin*cos:", round(simpson(f_sin, 0.0, 3.0, 200000), 9))
acc = 0.0
for v in range(1, 20001):
    acc += newton_sqrt(float(v))
print("sum newton sqrt:", round(acc, 6))
acc2 = 0.0
for k in range(5000):
    acc2 += taylor_exp_series(3.5, 40)
print("taylor e^3.5 sum:", round(acc2, 4))
print("leibniz pi:", round(leibniz(1000000), 9))
