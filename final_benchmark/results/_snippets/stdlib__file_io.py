f = open('/tmp/_zy_probe.txt', 'w')
f.write('hi\nthere\n')
f.close()
print(open('/tmp/_zy_probe.txt').read().split())
