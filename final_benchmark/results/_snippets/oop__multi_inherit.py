class A:
    def f(self):
        return 'A'
class B:
    def g(self):
        return 'B'
class C(A, B):
    pass
print(C().f() + C().g())
