class C:
    def __contains__(self, x):
        return x == 1
    def __bool__(self):
        return False
print(1 in C(), bool(C()))
