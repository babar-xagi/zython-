# Monte-Carlo estimate of pi using a hand-written LCG (deterministic, identical on both runtimes)
def lcg_next(x):
    return (x * 1103515245 + 12345) % 2147483648

x = 12345
inside = 0
N = 600000
for i in range(N):
    x = lcg_next(x)
    px = x / 2147483648.0
    x = lcg_next(x)
    py = x / 2147483648.0
    if px * px + py * py <= 1.0:
        inside += 1
print("inside:", inside)
print("pi estimate:", 4.0 * inside / N)
