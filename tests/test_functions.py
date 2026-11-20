# Test functions: recursion, defaults, lambdas, closures

print("--- Recursion (Factorial) ---")
def factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

print("5! =", factorial(5))
print("7! =", factorial(7))

print("--- Default Arguments ---")
def greet(name, greeting="Hello"):
    print(greeting, name)

greet("World")
greet("Zig", "Welcome to")

print("--- Higher Order Functions & Lambda ---")
def apply_twice(func, val):
    return func(func(val))

double = lambda x: x * 2
print("Double twice 5:", apply_twice(double, 5))

print("--- Closures ---")
def make_multiplier(factor):
    def multiply(x):
        return x * factor
    return multiply

times3 = make_multiplier(3)
print("times3(7) =", times3(7))
print("Function tests passed successfully!")
