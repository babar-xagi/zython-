class C:
    def __enter__(self):
        print('in')
        return self
    def __exit__(self, *a):
        print('out')
with C():
    print('body')
