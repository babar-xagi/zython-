class C:
    k = 3
    @classmethod
    def f(cls):
        return cls.k
print(C.f())
