import threading
r = []
t = threading.Thread(target=lambda: r.append(1))
t.start()
t.join()
print(r)
