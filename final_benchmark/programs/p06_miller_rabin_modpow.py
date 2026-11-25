# Deterministic Miller-Rabin primality + modular exponentiation (n < 3e9 so products fit in int64)
def mod_pow(base, exp, mod):
    result = 1
    base = base % mod
    while exp > 0:
        if exp % 2 == 1:
            result = (result * base) % mod
        base = (base * base) % mod
        exp = exp // 2
    return result

def is_prime_mr(n):
    if n < 2:
        return False
    if n % 2 == 0:
        return n == 2
    if n % 3 == 0:
        return n == 3
    d = n - 1
    r = 0
    while d % 2 == 0:
        d = d // 2
        r += 1
    for a in [2, 3, 5, 7]:
        if a % n == 0:
            continue
        x = mod_pow(a, d, n)
        if x == 1 or x == n - 1:
            continue
        composite = True
        for _ in range(r - 1):
            x = (x * x) % n
            if x == n - 1:
                composite = False
                break
        if composite:
            return False
    return True

count = 0
last = 0
n = 1000000000
while n < 1000060000:
    if is_prime_mr(n):
        count += 1
        last = n
    n += 1
print("MR primes in [1e9, 1e9+60000):", count, "last:", last)
print("2^1000003 mod 1000000007 =", mod_pow(2, 1000003, 1000000007))
