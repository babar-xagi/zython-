def deep(n):
    return 1 + deep(n + 1)
try:
    deep(0)
except RecursionError:
    print('recursion error')
