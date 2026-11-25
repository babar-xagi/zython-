class C:
    n = 5
    def m(self):
        return self.n
print(C().m(), C.n)
