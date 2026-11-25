def deco(f):
    def w(*a):
        return f(*a) + 1
    return w
@deco
def g(x):
    return x
print(g(1))
