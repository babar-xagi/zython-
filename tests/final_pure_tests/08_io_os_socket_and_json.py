import os
import json
import hashlib
import random
import socket
import threading
import time

print("==========================================")
print("TEST 8: NATIVE I/O, OS, SOCKET & SERIALIZATION")
print("==========================================")

# 1. Native File Creation, Writing & Seeking
test_file = "/tmp/zython_test_p10.txt"
if os.path.exists(test_file):
    os.remove(test_file)

f = open(test_file, "w")
assert not f.closed
assert f.name == test_file
assert f.mode == "w"
written = f.write("Hello Zython Phase 10!\nLine 2: High performance file I/O.\nLine 3: End of record.")
assert written > 0
f.close()
assert f.closed
print("1. File Writing & Lifecycle: OK (written", written, "bytes)")

# 2. File Reading & Line Iteration
f = open(test_file, "r")
line1 = f.readline()
assert "Hello Zython" in line1
f.seek(0, 0)
assert f.tell() == 0
lines = f.readlines()
assert len(lines) == 3
f.close()
print("2. File Reading, seek() & tell(): OK (read", len(lines), "lines)")

# 3. Context Manager & 'for line in f:' Loop Iteration
collected_lines = []
with open(test_file, "r") as f:
    for line in f:
        collected_lines.append(line)
assert len(collected_lines) == 3
assert f.closed
print("3. File Context Manager ('with open(...)') & Iteration: OK")

# 4. 'os' and 'os.path' File System Operations
cwd = os.getcwd()
assert len(cwd) > 0
assert os.path.exists(cwd)
assert os.path.isdir(cwd)
assert not os.path.isfile(cwd)

subpath = os.path.join(cwd, "src")
assert os.path.basename(subpath) == "src"
assert os.path.dirname(subpath) == cwd

sp = os.path.split("/var/log/syslog")
assert sp[0] == "/var/log"
assert sp[1] == "syslog"

ext_split = os.path.splitext("archive.tar.gz")
assert ext_split[0] == "archive.tar"
assert ext_split[1] == ".gz"

# Directory creation and cleanup
temp_dir = "/tmp/zython_test_dir_p10"
if os.path.exists(temp_dir):
    os.rmdir(temp_dir)
os.mkdir(temp_dir)
assert os.path.exists(temp_dir)
assert os.path.isdir(temp_dir)
os.rmdir(temp_dir)
assert not os.path.exists(temp_dir)

# Cleanup test file
os.remove(test_file)
assert not os.path.exists(test_file)
print("4. 'os' & 'os.path' Filesystem Operations: OK")

# 5. 'json' Encoding and Decoding
payload = {
    "engine": "Zython",
    "version": 10,
    "fast": True,
    "null_val": None,
    "tags": ["compiler", "jit", "io", "network"]
}
json_str = json.dumps(payload)
assert '"engine": "Zython"' in json_str
assert '"version": 10' in json_str
assert '"fast": true' in json_str
assert '"null_val": null' in json_str

decoded = json.loads(json_str)
assert decoded["engine"] == "Zython"
assert decoded["version"] == 10
assert decoded["fast"] == True
assert decoded["null_val"] == None
assert len(decoded["tags"]) == 4
assert decoded["tags"][1] == "jit"
print("5. 'json' dumps & loads Roundtrip: OK")

# 6. 'random' Pseudo-Random Number Generation
random.seed(12345)
r_val = random.random()
assert r_val >= 0.0 and r_val <= 1.0

int_val = random.randint(50, 100)
assert int_val >= 50 and int_val <= 100

u_val = random.uniform(1.5, 9.5)
assert u_val >= 1.5 and u_val <= 9.5

picked = random.choice(["alpha", "beta", "gamma", "delta"])
assert picked in ["alpha", "beta", "gamma", "delta"]
print("6. 'random' Module Operations: OK")

# 7. 'hashlib' Cryptographic Hashing
# RFC test vector for "hello world"
h_sha256 = hashlib.sha256("hello world")
assert h_sha256.hexdigest() == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"

h_md5 = hashlib.md5("hello world")
assert h_md5.hexdigest() == "5eb63bbbe01eeed093cb22bb8f5acdc3"

h_sha1 = hashlib.sha1("hello world")
assert h_sha1.hexdigest() == "2aae6c35c94fcfb415dbe95f408b9ce91ee846ed"

# Incremental update
h_inc = hashlib.sha256()
h_inc.update("hello ")
h_inc.update("world")
assert h_inc.hexdigest() == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9"
print("7. 'hashlib' (SHA256, MD5, SHA1) Digest Matching: OK")

# 8. 'socket' Loopback Client-Server Communication
TEST_PORT = 59124
received_payload = []

def echo_client():
    time.sleep(0.05)
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as client:
        client.connect(("127.0.0.1", TEST_PORT))
        client.sendall("ZYTHON_SOCKET_P10_PAYLOAD")

server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
server.bind(("127.0.0.1", TEST_PORT))
server.listen(5)

client_th = threading.Thread(target=echo_client)
client_th.start()

conn, addr = server.accept()
msg = conn.recv(1024)
conn.close()
server.close()
client_th.join()

assert msg == "ZYTHON_SOCKET_P10_PAYLOAD"
print("8. 'socket' TCP Loopback Client/Server Echo: OK (received:", msg, ")")

print("==========================================")
print("TEST 8 COMPLETE: ALL 8 SUBSYSTEMS PASSED 100%")
print("==========================================")
