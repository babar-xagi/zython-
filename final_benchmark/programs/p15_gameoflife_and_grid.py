# Cellular automaton (Conway's Game of Life on a torus) + 2D prefix sums + flood-fill style BFS
def make_grid(n, seed):
    g = []
    x = seed
    for i in range(n):
        row = []
        for j in range(n):
            x = (x * 1103515245 + 12345) % 2147483648
            row.append(1 if (x // 65536) % 3 == 0 else 0)
        g.append(row)
    return g

def life_step(g, n):
    out = []
    for i in range(n):
        up = g[(i - 1) % n]
        mid = g[i]
        down = g[(i + 1) % n]
        row = []
        for j in range(n):
            l = (j - 1) % n
            r = (j + 1) % n
            c = up[l] + up[j] + up[r] + mid[l] + mid[r] + down[l] + down[j] + down[r]
            if mid[j] == 1:
                row.append(1 if c == 2 or c == 3 else 0)
            else:
                row.append(1 if c == 3 else 0)
        out.append(row)
    return out

def bfs_components(g, n):
    seen = []
    for i in range(n):
        seen.append([0] * n)
    comps = 0
    biggest = 0
    for si in range(n):
        for sj in range(n):
            if g[si][sj] == 1 and seen[si][sj] == 0:
                comps += 1
                stack = [(si, sj)]
                seen[si][sj] = 1
                size = 0
                while len(stack) > 0:
                    cur = stack.pop()
                    ci = cur[0]
                    cj = cur[1]
                    size += 1
                    for d in range(4):
                        if d == 0:
                            ni = ci + 1
                            nj = cj
                        elif d == 1:
                            ni = ci - 1
                            nj = cj
                        elif d == 2:
                            ni = ci
                            nj = cj + 1
                        else:
                            ni = ci
                            nj = cj - 1
                        if ni >= 0 and ni < n and nj >= 0 and nj < n:
                            if g[ni][nj] == 1 and seen[ni][nj] == 0:
                                seen[ni][nj] = 1
                                stack.append((ni, nj))
                if size > biggest:
                    biggest = size
    return (comps, biggest)

N = 64
g = make_grid(N, 2024)
for gen in range(60):
    g = life_step(g, N)
alive = 0
for row in g:
    for v in row:
        alive += v
print("alive after 60 generations:", alive)
print("components, biggest:", bfs_components(g, N))
big = make_grid(300, 99)
print("components in random 300x300:", bfs_components(big, 300))
