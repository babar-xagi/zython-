d = {'a': 1, 'b': 2, 'c': 3}
d.pop('a')
print(d)
print(d.get('c'))
print('c' in d)
print(list(d.keys()))
d['z'] = 9
print(d.get('c'), d.get('z'), d.get('b'))
print(len(d))
