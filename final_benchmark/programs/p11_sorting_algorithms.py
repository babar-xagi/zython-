# Hand-written sorts (the builtin sort/sorted are broken in Zython, see BUG report):
# quicksort (in-place), merge sort (list building), heap sort, insertion sort (not named insertion_sort)
def gen(n, seed):
    out = []
    x = seed
    for i in range(n):
        x = (x * 1103515245 + 12345) % 2147483648
        out.append(x % 100000)
    return out

def quicksort(a, lo, hi):
    while lo < hi:
        pivot = a[(lo + hi) // 2]
        i = lo
        j = hi
        while i <= j:
            while a[i] < pivot:
                i += 1
            while a[j] > pivot:
                j -= 1
            if i <= j:
                t = a[i]
                a[i] = a[j]
                a[j] = t
                i += 1
                j -= 1
        if j - lo < hi - i:
            quicksort(a, lo, j)
            lo = i
        else:
            quicksort(a, i, hi)
            hi = j

def merge_sort(a):
    n = len(a)
    if n <= 1:
        return a
    mid = n // 2
    left = merge_sort(a[:mid])
    right = merge_sort(a[mid:])
    out = []
    i = 0
    j = 0
    while i < len(left) and j < len(right):
        if left[i] <= right[j]:
            out.append(left[i])
            i += 1
        else:
            out.append(right[j])
            j += 1
    while i < len(left):
        out.append(left[i])
        i += 1
    while j < len(right):
        out.append(right[j])
        j += 1
    return out

def sift_down(a, start, end):
    root = start
    while 2 * root + 1 <= end:
        child = 2 * root + 1
        if child + 1 <= end and a[child] < a[child + 1]:
            child += 1
        if a[root] < a[child]:
            t = a[root]
            a[root] = a[child]
            a[child] = t
            root = child
        else:
            return

def heap_sort(a):
    n = len(a)
    start = (n - 2) // 2
    while start >= 0:
        sift_down(a, start, n - 1)
        start -= 1
    end = n - 1
    while end > 0:
        t = a[0]
        a[0] = a[end]
        a[end] = t
        end -= 1
        sift_down(a, 0, end)

def isort(arr):
    n = len(arr)
    i = 1
    while i < n:
        key = arr[i]
        j = i - 1
        while j >= 0 and arr[j] > key:
            arr[j + 1] = arr[j]
            j -= 1
        arr[j + 1] = key
        i += 1

def checksum(a):
    s = 0
    for i in range(len(a)):
        s = (s * 131 + a[i] * (i % 7 + 1)) % 1000000007
    return s

def is_sorted(a):
    for i in range(1, len(a)):
        if a[i - 1] > a[i]:
            return False
    return True

data = gen(150000, 99)
q = list(data)
quicksort(q, 0, len(q) - 1)
print("quicksort:", is_sorted(q), checksum(q))
m = merge_sort(data)
print("mergesort:", is_sorted(m), checksum(m))
h = list(data)
heap_sort(h)
print("heapsort:", is_sorted(h), checksum(h))
small = gen(2500, 5)
isort(small)
print("insertion:", is_sorted(small), checksum(small))
