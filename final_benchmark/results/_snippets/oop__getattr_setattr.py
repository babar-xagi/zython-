class C:
    pass
c = C()
setattr(c, 'a', 3)
print(getattr(c, 'a'), hasattr(c, 'b'))
