# Sieve of Eratosthenes (list indexing + stores) and prime statistics
def sieve(limit):
    flags = [1] * (limit + 1)
    flags[0] = 0
    flags[1] = 0
    i = 2
    while i * i <= limit:
        if flags[i] == 1:
            j = i * i
            while j <= limit:
                flags[j] = 0
                j += i
        i += 1
    return flags

LIMIT = 2000000
flags = sieve(LIMIT)
count = 0
total = 0
twins = 0
prev = 0
for k in range(2, LIMIT + 1):
    if flags[k] == 1:
        count += 1
        total += k
        if k - prev == 2:
            twins += 1
        prev = k
print("primes <= 2,000,000:", count)
print("sum of primes:", total)
print("twin prime pairs:", twins)
