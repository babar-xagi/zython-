class C:
    def __init__(self):
        self.n = 0
c = C()
for i in range(5):
    c.n += i
print(c.n)
