# Mandelbrot escape-time set: pure float arithmetic in nested loops
def mandel_point(cr, ci, max_iter):
    zr = 0.0
    zi = 0.0
    i = 0
    while i < max_iter:
        zr2 = zr * zr
        zi2 = zi * zi
        if zr2 + zi2 > 4.0:
            return i
        zi = 2.0 * zr * zi + ci
        zr = zr2 - zi2 + cr
        i += 1
    return max_iter

W = 160
H = 120
MAXI = 200
inside = 0
total_iters = 0
for py in range(H):
    for px in range(W):
        cr = -2.2 + 3.2 * px / W
        ci = -1.2 + 2.4 * py / H
        it = mandel_point(cr, ci, MAXI)
        total_iters += it
        if it == MAXI:
            inside += 1
print("inside points:", inside)
print("total iterations:", total_iters)
