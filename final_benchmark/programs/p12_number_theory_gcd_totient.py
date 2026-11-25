# Number theory: Euclid gcd, Euler totient sieve, digit sums, perfect numbers, divisor sums
def gcd(a, b):
    while b != 0:
        t = a % b
        a = b
        b = t
    return a

def totient_sum(n):
    phi = list(range(n + 1))
    for i in range(2, n + 1):
        if phi[i] == i:
            j = i
            while j <= n:
                phi[j] = phi[j] - phi[j] // i
                j += i
    s = 0
    for i in range(1, n + 1):
        s += phi[i]
    return s

def digit_sum(n):
    s = 0
    while n > 0:
        s += n % 10
        n = n // 10
    return s

def divisor_sum_table(n):
    sig = [0] * (n + 1)
    for d in range(1, n + 1):
        m = d
        while m <= n:
            sig[m] += d
            m += d
    return sig

g = 0
for a in range(1, 700):
    for b in range(1, 700):
        g += gcd(a, b)
print("sum gcd(a,b) a,b<700:", g)
print("totient sum n=300000:", totient_sum(300000))
ds = 0
for n in range(1, 300000):
    ds += digit_sum(n * n)
print("digit sum of squares:", ds)
sig = divisor_sum_table(200000)
perfect = []
amicable = 0
for n in range(2, 200001):
    if sig[n] - n == n:
        perfect.append(n)
    m = sig[n] - n
    if m != n and m <= 200000 and sig[m] - m == n and n < m:
        amicable += 1
print("perfect numbers:", perfect)
print("amicable pairs:", amicable)
