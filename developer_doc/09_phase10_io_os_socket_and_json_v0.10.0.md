# 🌐 Phase 10 Architecture: Native I/O, OS File System, Network Sockets & Serialization (v0.10.0)

> **Version**: Zython v0.10.0  
> **Status**: Production Released  
> **Milestone Objective**: Full Native I/O (`open()`, `PyFile`), OS & File System Module (`os`, `os.path`), Network Sockets (`socket`), Serialization (`json`), PRNG (`random`), Cryptographic Hashing (`hashlib`), and Test Suite 08 verification.

---

## 🏗️ 1. Architecture Overview: Native I/O, POSIX & Distributed Networking

In **Phase 10 (v0.10.0)**, Zython bridges high-performance execution with complete environmental interaction. Moving beyond computation and FFI, Zython now interacts directly with file systems, persistent storage, operating system primitives, network sockets, serialization pipelines, and cryptographic routines with zero CPython overhead.

```
                      Zython v0.10.0 I/O & Networking Subsystems
                                          │
    ┌─────────────────┬───────────────────┼───────────────────┬─────────────────┐
    ▼                 ▼                   ▼                   ▼                 ▼
Native File I/O     OS & Path       Network Sockets     Serialization      Crypto & PRNG
┌──────────────┐  ┌──────────────┐  ┌──────────────┐   ┌──────────────┐  ┌──────────────┐
│ • open()     │  │ • os         │  │ • socket     │   │ • json.dumps │  │ • hashlib    │
│ • PyFile     │  │ • os.path    │  │ • AF_INET    │   │ • json.loads │  │   (sha256,   │
│ • read/write │  │ • getcwd()   │  │ • SOCK_STREAM│   │ • Recursive  │  │    md5, sha1)│
│ • seek/tell  │  │ • isfile/dir │  │ • bind/listen│   │   Descent    │  │ • random     │
│ • with & for │  │ • environ    │  │ • accept/send│   │   Parser     │  │   (uniform,  │
│   iteration  │  │ • mkdir/rm   │  │ • recv/close │   │ • Serializer │  │    randint)  │
└──────────────┘  └──────────────┘  └──────────────┘   └──────────────┘  └──────────────┘
```

---

## 🧩 2. Core Architectural Subsystems

### 1. High-Performance Native File I/O (`open()`, `PyFile`)
* **Core Struct (`src/value.zig`)**:
  Wraps libc `FILE*` handles using standard C POSIX descriptors with direct buffered access:
  - `open(allocator, path, mode)`: Supports `"r"`, `"w"`, `"a"`, `"rb"`, `"wb"`.
  - `read(max_size)`: Reads all or bounded chunks into heap-allocated `Value.string`.
  - `readline()`: Reads line-by-line up to `\n` or EOF.
  - `readlines()`: Collects all lines into a `PyList`.
  - `write(data)` / `writelines(seq)`: Zero-copy buffered writes.
  - `seek(offset, whence)` / `tell()`: Precise file pointer navigation.
  - `flush()` / `close()`: Robust descriptor synchronization.
  - **Context Manager**: Supports `with open(...) as f:` via `__enter__` and `__exit__`.
  - **Loop Specialization**: Native `for line in f:` in `src/interpreter.zig`.

### 2. Operating System & Path Module (`os`, `os.path`)
* **`os` Module (`src/builtins.zig`)**:
  - `os.name`: Identifies environment (`"posix"`).
  - `os.getcwd()`: Returns current working directory.
  - `os.chdir(path)`: Changes working directory.
  - `os.listdir(path)`: Enumerate directory entries with `opendir`/`readdir`.
  - `os.mkdir(path)`: Creates directories.
  - `os.remove(path)` / `os.unlink(path)`: Unlinks files.
  - `os.rmdir(path)`: Removes empty directories.
  - `os.rename(src, dst)`: Atomic file relocation.
  - `os.system(cmd)`: Subprocess shell execution via libc `system`.
  - `os.getenv(var, default)`: Environment variable query.
  - `os.environ`: Dynamic dictionary containing all current environment variables.
* **`os.path` Module**:
  - `exists(p)`: Verifies path existence via `access`.
  - `isfile(p)`: True if target exists and is a regular file (not directory).
  - `isdir(p)`: True if target is a navigable directory.
  - `join(*parts)`: Portable path segment concatenation.
  - `basename(p)` / `dirname(p)`: Path decomposition.
  - `split(p)`: Splits into `(head, tail)` tuple.
  - `splitext(p)`: Splits into `(root, ext)` tuple.

### 3. POSIX Network Sockets (`socket`)
* **Core Struct (`src/value.zig`)**:
  - `AF_INET = 2`, `SOCK_STREAM = 1`, `SOCK_DGRAM = 2`, `SOL_SOCKET = 1`, `SO_REUSEADDR = 2`.
  - `socket(family, type, proto)`: Constructs kernel socket descriptors.
  - `bind((host, port))`: Binds to local address and sets `SO_REUSEADDR`.
  - `listen(backlog)`: Configures passive connection backlog.
  - `accept()`: Returns `(client_socket, (address, port))`.
  - `connect((host, port))`: Establishes outbound connection.
  - `send(data)` / `sendall(data)`: Transmits byte streams over socket.
  - `recv(buf_size)`: Reads network bytes.
  - `close()`: Shuts down descriptor.
  - `with socket.socket(...) as s:` context manager support.

### 4. Native Serialization (`json`)
* **Recursive Serializer (`json.dumps`)**:
  - Serializes nested dictionaries, lists, tuples, strings, integers, floats, booleans, and `None` into compliant JSON strings.
* **Recursive Descent Parser (`json.loads`)**:
  - Parses JSON strings with string escape handling (`\"`, `\\`, `\/`, `\b`, `\f`, `\n`, `\r`, `\t`), negative and floating-point numbers, true, false, null, arrays, and objects into native Zython `Value` types.

### 5. Cryptographic Hashing (`hashlib`)
* **Standard Algorithms**:
  - `hashlib.sha256(data)`: SHA-256 standard cryptographic hash.
  - `hashlib.md5(data)`: MD5 hash.
  - `hashlib.sha1(data)`: SHA-1 hash.
  - `.update(chunk)`: Incremental hashing.
  - `.hexdigest()`: Returns standard lowercase hexadecimal digest.

### 6. Pseudo-Random Number Generation (`random`)
* **PRNG Functions**:
  - `random.random()`: Uniform float in `[0.0, 1.0)`.
  - `random.randint(a, b)`: Uniform integer in `[a, b]`.
  - `random.uniform(a, b)`: Uniform float in `[a, b]`.
  - `random.choice(seq)`: Random element from list or tuple.
  - `random.seed(n)`: Deterministic PRNG seed initialization.

---

## 🧪 3. Verification & Test Suite 08

All 8 subsystems were verified in **Test Suite 08** (`tests/final_pure_tests/08_io_os_socket_and_json.py`):
1. **File Writing & Lifecycle**: Created file, wrote 80 bytes, verified closed status.
2. **File Reading & Seeking**: Read lines, tested `seek(0, 0)`, `tell()`, and `readlines()`.
3. **Context Manager & Iteration**: Verified `with open(...) as f:` and `for line in f:` iteration.
4. **`os` & `os.path`**: Verified `getcwd`, `exists`, `isdir`, `isfile`, `join`, `split`, `splitext`, `mkdir`, and `rmdir`.
5. **`json` Roundtrip**: Encoded nested structures with null, bool, int, float, array, dict and parsed back with 100% equivalence.
6. **`random` Operations**: Verified bounds and choices.
7. **`hashlib` Verification**: Tested against official RFC test vectors for SHA-256, MD5, and SHA-1 with exact digest matches.
8. **`socket` Loopback Client/Server**: Concurrently transmitted and echoed data over `127.0.0.1` TCP socket via `threading.Thread`.

**Result**: 100% Pass Rate across all 8 test suites.
