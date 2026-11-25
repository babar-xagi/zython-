class C:
    def __init__(self):
        self._v = 4
    @property
    def v(self):
        return self._v * 2
print(C().v)
