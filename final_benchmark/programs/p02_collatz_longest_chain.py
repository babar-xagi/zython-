# Longest Collatz chain below LIMIT (tight while loop, integer // and %, branching)
def collatz_len(n):
    steps = 1
    while n != 1:
        if n % 2 == 0:
            n = n // 2
        else:
            n = 3 * n + 1
        steps += 1
    return steps

def longest_below(limit):
    best = 0
    best_n = 0
    n = 1
    while n < limit:
        l = collatz_len(n)
        if l > best:
            best = l
            best_n = n
        n += 1
    return (best_n, best)

res = longest_below(100000)
n = res[0]
l = res[1]
print("longest collatz below 100000:", n, l)
