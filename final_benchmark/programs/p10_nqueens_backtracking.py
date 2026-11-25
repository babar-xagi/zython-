# N-Queens backtracking with list state + recursion + subset-sum search
def solve(n, row, cols, d1, d2):
    if row == n:
        return 1
    count = 0
    for c in range(n):
        if cols[c] == 0 and d1[row + c] == 0 and d2[row - c + n - 1] == 0:
            cols[c] = 1
            d1[row + c] = 1
            d2[row - c + n - 1] = 1
            count += solve(n, row + 1, cols, d1, d2)
            cols[c] = 0
            d1[row + c] = 0
            d2[row - c + n - 1] = 0
    return count

def queens(n):
    return solve(n, 0, [0] * n, [0] * (2 * n), [0] * (2 * n))

def subset_count(nums, idx, remaining):
    if remaining == 0:
        return 1
    if idx == len(nums) or remaining < 0:
        return 0
    return subset_count(nums, idx + 1, remaining - nums[idx]) + subset_count(nums, idx + 1, remaining)

print("queens(8) =", queens(8))
print("queens(9) =", queens(9))
print("queens(10) =", queens(10))
print("subset_count =", subset_count([3, 34, 4, 12, 5, 2, 7, 8, 9, 10, 11, 13, 14, 15, 1, 6, 16, 17], 0, 60))
