# Dict-heavy and string-heavy workloads: memoised Collatz in a dict, word histogram, string building
def collatz_memo(limit):
    cache = {1: 1}
    best = 0
    best_n = 0
    for start in range(1, limit):
        n = start
        path = []
        while not (n in cache):
            path.append(n)
            if n % 2 == 0:
                n = n // 2
            else:
                n = 3 * n + 1
        base = cache[n]
        k = len(path)
        for idx in range(k):
            cache[path[idx]] = base + k - idx
        v = cache[start]
        if v > best:
            best = v
            best_n = start
    return (best_n, best, len(cache))

print("memo collatz:", collatz_memo(2500))

hist = {}
x = 777
for i in range(60000):
    x = (x * 1103515245 + 12345) % 2147483648
    key = x % 400
    if key in hist:
        hist[key] += 1
    else:
        hist[key] = 1
mx = 0
mk = 0
for k in hist:
    if hist[k] > mx or (hist[k] == mx and k < mk):
        mx = hist[k]
        mk = k
print("distinct keys:", len(hist), "most common:", mk, mx)

words = []
for i in range(20000):
    words.append("w" + str(i % 997))
text = " ".join(words)
parts = text.split(" ")
freq = {}
for w in parts:
    freq[w] = freq.get(w, 0) + 1
print("text length:", len(text), "unique words:", len(freq), "w5 count:", freq["w5"])

s = ""
for i in range(20000):
    s += chr(97 + i % 26)
vowels = 0
for ch in s:
    if ch == "a" or ch == "e" or ch == "i" or ch == "o" or ch == "u":
        vowels += 1
print("vowels:", vowels, "upper head:", s[:10].upper())
