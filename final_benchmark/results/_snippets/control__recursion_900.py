def deep(n):
    if n == 0:
        return 0
    return 1 + deep(n - 1)
print(deep(900))
