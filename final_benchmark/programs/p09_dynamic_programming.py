# Dynamic programming: LCS (2D table), 0/1 knapsack (1D), edit distance, coin change
def gen_seq(n, seed, alpha):
    out = []
    x = seed
    for i in range(n):
        x = (x * 1103515245 + 12345) % 2147483648
        out.append(x % alpha)
    return out

def lcs(a, b):
    n = len(a)
    m = len(b)
    table = []
    for i in range(n + 1):
        table.append([0] * (m + 1))
    for i in range(1, n + 1):
        ai = a[i - 1]
        prev = table[i - 1]
        cur = table[i]
        for j in range(1, m + 1):
            if ai == b[j - 1]:
                cur[j] = prev[j - 1] + 1
            else:
                up = prev[j]
                left = cur[j - 1]
                cur[j] = up if up > left else left
    return table[n][m]

def edit_distance(a, b):
    n = len(a)
    m = len(b)
    prev = list(range(m + 1))
    for i in range(1, n + 1):
        cur = [i] + [0] * m
        for j in range(1, m + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            best = prev[j - 1] + cost
            if prev[j] + 1 < best:
                best = prev[j] + 1
            if cur[j - 1] + 1 < best:
                best = cur[j - 1] + 1
            cur[j] = best
        prev = cur
    return prev[m]

def knapsack(weights, values, cap):
    dp = [0] * (cap + 1)
    for idx in range(len(weights)):
        w = weights[idx]
        v = values[idx]
        c = cap
        while c >= w:
            cand = dp[c - w] + v
            if cand > dp[c]:
                dp[c] = cand
            c -= 1
    return dp[cap]

def coin_ways(coins, target):
    ways = [0] * (target + 1)
    ways[0] = 1
    for c in coins:
        for t in range(c, target + 1):
            ways[t] = (ways[t] + ways[t - c]) % 1000000007
    return ways[target]

A = gen_seq(900, 7, 4)
B = gen_seq(900, 11, 4)
print("LCS length:", lcs(A, B))
print("edit distance:", edit_distance(A[:700], B[:700]))
W = gen_seq(120, 3, 40)
V = gen_seq(120, 5, 100)
print("knapsack:", knapsack([w + 1 for w in W], V, 3000))
print("coin ways:", coin_ways([1, 2, 5, 10, 20, 50, 100, 200], 20000))
