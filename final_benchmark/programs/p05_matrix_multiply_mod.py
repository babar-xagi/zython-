# Dense integer matrix multiplication (list of lists), modular arithmetic kept < 2^63
MOD = 1000003

def make_matrix(n, seed):
    m = []
    x = seed
    for i in range(n):
        row = []
        for j in range(n):
            x = (x * 1103515245 + 12345) % 2147483648
            row.append(x % 1000)
        m.append(row)
    return m

def matmul(a, b, n):
    c = []
    for i in range(n):
        row_a = a[i]
        row = []
        for j in range(n):
            s = 0
            for k in range(n):
                s += row_a[k] * b[k][j]
            row.append(s % MOD)
        c.append(row)
    return c

N = 90
a = make_matrix(N, 1)
b = make_matrix(N, 2)
c = matmul(a, b, N)
d = matmul(c, a, N)
trace = 0
checksum = 0
for i in range(N):
    trace += d[i][i]
    for j in range(N):
        checksum = (checksum * 31 + d[i][j]) % 1000000007
print("trace:", trace)
print("checksum:", checksum)
