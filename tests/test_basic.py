# Test basic data types and operators
a = 10
b = 3

print("--- Basic Arithmetic ---")
print("a + b =", a + b)
print("a - b =", a - b)
print("a * b =", a * b)
print("a / b =", a / b)
print("a // b =", a // b)
print("a % b =", a % b)
print("a ** b =", a ** b)

print("--- Bitwise Operators ---")
print("a & b =", a & b)
print("a | b =", a | b)
print("a ^ b =", a ^ b)
print("a << 1 =", a << 1)
print("a >> 1 =", a >> 1)

print("--- Comparisons & Logic ---")
print("a > b:", a > b)
print("a == 10:", a == 10)
print("a != 10:", a != 10)
print("True and False:", True and False)
print("True or False:", True or False)
print("not False:", not False)

print("--- Strings ---")
s = "Hello Zython"
print("Length:", len(s))
print("Upper:", s.upper())
print("Lower:", s.lower())
print("Slice [0:5]:", s[0:5])
print("Basic tests passed successfully!")
