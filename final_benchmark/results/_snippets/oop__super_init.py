
class P:
    def __init__(self, x):
        self.x = x
    def __add__(self, o):
        return P(self.x + o.x)
    def __repr__(self):
        return 'P(' + str(self.x) + ')'
    def __eq__(self, o):
        return self.x == o.x
    def __lt__(self, o):
        return self.x < o.x
    def __len__(self):
        return self.x
    def __getitem__(self, i):
        return self.x + i
    def __hash__(self):
        return hash(self.x)
class Q(P):
    def __init__(self, x):
        super().__init__(x)
        self.y = 1
    def who(self):
        return 'Q'
q = Q(3)
print(q.x, q.y, q.who(), isinstance(q, P))
