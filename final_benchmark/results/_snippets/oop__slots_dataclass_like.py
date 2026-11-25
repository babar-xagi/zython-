class C:
    __slots__ = ('a',)
    def __init__(self):
        self.a = 1
print(C().a)
