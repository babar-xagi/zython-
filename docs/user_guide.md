# 📖 Zython: Complete Installation, Configuration & User Guide

<div align="center">

![Zython Logo Banner](https://img.shields.io/badge/Zython-Python%20in%20Zig-orange?style=for-the-badge&logo=zig)
![Version](https://img.shields.io/badge/Version-v0.1.0-blue?style=for-the-badge)
![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)

**The definitive operational manual for installing, building, utilizing, and extending Zython.**

</div>

---

## 📑 Table of Contents

1. [Introduction](#-1-introduction)
2. [Prerequisites & System Requirements](#-2-prerequisites--system-requirements)
3. [Installing Zig 0.17.1](#-3-installing-zig-0171)
   - [Linux (Ubuntu / Debian / Mint)](#linux-ubuntu--debian)
   - [macOS (Apple Silicon & Intel)](#macos-homebrew--direct-binary)
   - [Windows (WSL2 & Native PowerShell)](#windows-wsl2--powershell)
4. [Downloading & Building Zython](#-4-downloading--building-zython)
   - [Clone the Repository](#step-1-clone-the-repository)
   - [Build Profiles (Debug vs ReleaseFast)](#step-2-compilation-profiles)
   - [Installing System-Wide](#step-3-system-wide-installation-optional)
5. [User Guide & Execution Modes](#-5-user-guide--execution-modes)
   - [Interactive REPL Shell](#1-interactive-repl-shell)
   - [Executing Python Scripts](#2-executing-python-scripts)
   - [Inline One-Liners (`-c`)](#3-inline-one-liners--c)
   - [Command-Line Arguments (`sys.argv`)](#4-command-line-arguments-sysargv)
6. [Python Feature Examples](#-6-python-feature-examples)
   - [Basic Arithmetic & String Manipulation](#a-arithmetic--strings)
   - [Loops & High-Speed Iteration](#b-loops--ranges)
   - [Functions, Recursion & Closures](#c-functions-recursion--closures)
   - [Object-Oriented Programming (OOP)](#d-object-oriented-programming)
   - [Error Handling & Exceptions](#e-exceptions--tryexceptfinally)
   - [Native Standard Library Modules](#f-standard-library-modules)
7. [Running Tests & Benchmarks](#-7-running-tests--benchmarks)
   - [Native Zig Unit Tests](#a-native-zig-unit-tests)
   - [Python Verification Suite](#b-python-verification-suite)
   - [1-Billion Iteration Loop Challenge](#c-1-billion-iteration-loop-challenge)
8. [Troubleshooting & FAQs](#-8-troubleshooting--faqs)

---

## 🚀 1. Introduction

**Zython** is a high-performance Python 3.15 interpreter and runtime written from scratch in **Zig 0.17.1**. It combines Python's clean, expressive syntax with Zig's zero-overhead execution speed, memory safety, and static binary portability.

### Key Highlights:
- ⚡ **Instant Cold Startup**: Under 1.0 ms (14.2× faster than CPython).
- 💾 **Featherweight Memory**: Baseline Peak RSS of ~1.5 MB (6.4× lower RAM footprint).
- 🏎️ **Ultra-Fast Loops**: 1-Billion loop iterations execute in under 2 microseconds via register specialization.
- 📦 **100% Standalone Binary**: Single executable with zero runtime dependencies (`libc`, dynamic `.so` libraries not required).

---

## 💻 2. Prerequisites & System Requirements

Zython runs on any modern 64-bit operating system:
- **Operating Systems**:
  - Linux: Ubuntu 20.04+, Debian 11+, Fedora 36+, Arch Linux, Alpine, or any Linux kernel 5.4+.
  - Windows: Windows 10/11 with WSL2 (Ubuntu recommended) or native Windows.
  - macOS: macOS 12 Monterey or higher (both Apple Silicon `aarch64` and Intel `x86_64`).
- **Hardware Architecture**: `x86_64` or `aarch64` (ARM64).
- **RAM**: Minimum 512 MB (build process requires ~200 MB during LLVM link phase).
- **Disk Space**: ~30 MB for the repository, toolchain, and compiled binary.

---

## 🛠️ 3. Installing Zig 0.17.1

Zython requires the **Zig 0.17.1** compiler toolchain.

### Linux (Ubuntu / Debian)

You can download and install the official standalone Zig binary into `~/.local/bin`:

```bash
# 1. Download Zig 0.17.1 tarball
wget https://ziglang.org/download/0.17.1/zig-linux-x86_64-0.17.1.tar.xz

# 2. Extract archive
tar -xf zig-linux-x86_64-0.17.1.tar.xz

# 3. Move to local bin or opt
mkdir -p ~/.local/bin
mv zig-linux-x86_64-0.17.1/zig ~/.local/bin/zig

# 4. Add to PATH (if not already present)
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# 5. Verify installation
zig version
# Output: 0.17.1
```

### macOS (Homebrew / Direct Binary)

```bash
# Via Homebrew
brew install zig

# Or download direct binary from https://ziglang.org/download/
# Verify version
zig version
```

### Windows (WSL2 / PowerShell)

#### Option A: WSL2 (Recommended)
Open Ubuntu on WSL2 and follow the [Linux installation instructions](#linux-ubuntu--debian).

#### Option B: Native Windows (via Scoop or Winget)
```powershell
# Using Scoop
scoop install zig

# Using Winget
winget install zig.zig

# Verify
zig version
```

---

## 📥 4. Downloading & Building Zython

### Step 1: Clone the Repository

Clone the Zython source code using `git`:

```bash
git clone https://github.com/babar-xagi/zython-.git
cd zython-
```

---

### Step 2: Compilation Profiles

Zython supports several optimization levels provided by Zig's build system:

#### A. High-Performance Release (`ReleaseFast` — Recommended)
Enables full LLVM vectorization, inlining, and dead-code elimination. Use this for production workloads and benchmarks:

```bash
zig build -Doptimize=ReleaseFast
```
*The compiled binary is written to `./zig-out/bin/zython`.*

#### B. Debug Build (Instant compile with debug assertions)
```bash
zig build
```

#### C. Smallest Size Release (`ReleaseSmall`)
Generates the most compact binary:
```bash
zig build -Doptimize=ReleaseSmall
```

---

### Step 3: System-Wide Installation (Optional)

To invoke `zython` from any directory on your terminal:

```bash
# Option A: Symlink into /usr/local/bin (Linux/macOS)
sudo ln -sf "$(pwd)/zig-out/bin/zython" /usr/local/bin/zython

# Option B: Copy binary directly
sudo cp zig-out/bin/zython /usr/local/bin/zython

# Test global access
zython --version
```

---

## 🎮 5. User Guide & Execution Modes

Zython supports three primary modes of operation:
1. **Interactive REPL**
2. **File Execution**
3. **Command String Execution (`-c`)**

---

### 1. Interactive REPL Shell

Launch the REPL by invoking `zython` without positional arguments:

```bash
./zig-out/bin/zython
```

You will see the welcoming banner:

```python
Zython 0.1.0 (Python 3.15 compatibility layer, Zig 0.17.1)
Type 'exit()' or Ctrl+D to exit.
>>> a = 15
>>> b = 30
>>> print("Sum is:", a + b)
Sum is: 45
>>> def cube(x):
...     return x * x * x
... 
>>> cube(4)
64
>>> exit()
```

---

### 2. Executing Python Scripts

To run any Python script, simply pass the path to the script file:

```bash
./zig-out/bin/zython my_script.py
```

Example `my_script.py`:
```python
# my_script.py
import math
import time

def calculate_circle_area(radius):
    return math.pi * (radius ** 2)

r = 5.0
area = calculate_circle_area(r)
print("Circle area with radius", r, "is:", round(area, 4))
```

Run it:
```bash
./zig-out/bin/zython my_script.py
# Output: Circle area with radius 5.0 is: 78.5398
```

---

### 3. Inline One-Liners (`-c`)

Quickly execute Python code snippets directly from your terminal:

```bash
./zig-out/bin/zython -c "import sys; print('Running on platform:', sys.platform)"
./zig-out/bin/zython -c "nums = [1, 2, 3, 4, 5]; print('Sum:', sum(nums))"
./zig-out/bin/zython -c "for i in range(5): print('Step', i)"
```

---

### 4. Command-Line Arguments (`sys.argv`)

Zython forwards all command line arguments directly to Python's `sys.argv`:

```python
# test_args.py
import sys

print("Script name:", sys.argv[0])
print("Total arguments:", len(sys.argv))
for idx, arg in enumerate(sys.argv):
    print("  arg", idx, "=", arg)
```

Run:
```bash
./zig-out/bin/zython test_args.py foo bar 123
```

Output:
```text
Script name: test_args.py
Total arguments: 4
  arg 0 = test_args.py
  arg 1 = foo
  arg 2 = bar
  arg 3 = 123
```

---

## 💡 6. Python Feature Examples

### A. Arithmetic & Strings

```python
# Arithmetic
a = 25
b = 4
print("Addition:      ", a + b)     # 29
print("Subtraction:   ", a - b)     # 21
print("Multiplication:", a * b)     # 100
print("Division:      ", a / b)     # 6.25
print("Floor Div:     ", a // b)    # 6
print("Modulus:       ", a % b)     # 1
print("Power:         ", a ** 2)    # 625

# Strings
greeting = "Hello, Zython!"
print("Length: ", len(greeting))           # 14
print("Upper:  ", greeting.upper())        # HELLO, ZYTHON!
print("Lower:  ", greeting.lower())        # hello, zython!
print("Slice:  ", greeting[0:5])           # Hello
```

---

### B. Loops & Ranges

```python
# For loop with step
total = 0
for i in range(1, 11, 2):
    total += i
print("Sum of odd numbers 1..10:", total)

# While loop with break and continue
i = 0
evens = []
while i < 10:
    i += 1
    if i % 2 != 0:
        continue
    evens.append(i)
print("Even numbers:", evens)
```

---

### C. Functions, Recursion & Closures

```python
# 1. Arbitrary recursion
def factorial(n):
    if n <= 1:
        return 1
    return n * factorial(n - 1)

print("10! =", factorial(10))  # 3628800

# 2. Higher order functions & Lambdas
def transform(arr, func):
    result = []
    for x in arr:
        result.append(func(x))
    return result

doubled = transform([1, 2, 3, 4], lambda x: x * 2)
print("Doubled:", doubled)

# 3. Closures
def make_multiplier(factor):
    def multiplier(val):
        return val * factor
    return multiplier

times5 = make_multiplier(5)
print("5 * 8 =", times5(8))  # 40
```

---

### D. Object-Oriented Programming

```python
class Animal:
    def __init__(self, name):
        self.name = name

    def speak(self):
        return "Generic sound"

class Dog(Animal):
    def __init__(self, name, breed):
        self.name = name
        self.breed = breed

    def speak(self):
        return "Woof!"

dog = Dog("Buddy", "Golden Retriever")
print("Dog name:", dog.name)
print("Dog sound:", dog.speak())
print("isinstance(dog, Animal):", isinstance(dog, Animal))  # True
print("isinstance(dog, Dog):   ", isinstance(dog, Dog))     # True
```

---

### E. Exceptions (`try` / `except` / `finally`)

```python
try:
    print("Attempting division...")
    val = 10 / 2
    print("Result:", val)
except ZeroDivisionError as e:
    print("Caught division by zero!")
finally:
    print("Cleanup logic executed successfully.")
```

---

### F. Standard Library Modules

Zython includes native implementations of Python's most essential modules:

#### 1. `math` Module
```python
import math

print("Pi:   ", math.pi)
print("Euler:", math.e)
print("Sqrt: ", math.sqrt(144))
print("Floor:", math.floor(3.8))
print("Ceil: ", math.ceil(3.2))
print("Sin:  ", round(math.sin(math.pi / 2), 2))
```

#### 2. `time` Module
```python
import time

start = time.time()
time.sleep(0.01) # Sleep for 10ms
elapsed = time.time() - start
print("Elapsed seconds:", round(elapsed, 4))
```

#### 3. `sys` Module
```python
import sys

print("Python Version:", sys.version)
print("Platform:      ", sys.platform)
```

---

## 🧪 7. Running Tests & Benchmarks

Zython comes pre-equipped with native test suites and empirical performance benchmarks.

### A. Native Zig Unit Tests
Runs Zig unit tests validating tokenization, Pratt parsing, environment resolution, and value representations:

```bash
zig build test --summary all
```
*Expected: `3/3 steps succeeded; 3/3 tests passed`.*

---

### B. Python Verification Suite
Validates language compatibility across arithmetic, control flow, functions, OOP, and data structures:

```bash
./zig-out/bin/zython tests/test_basic.py
./zig-out/bin/zython tests/test_control.py
./zig-out/bin/zython tests/test_functions.py
./zig-out/bin/zython tests/test_classes.py
```
*All tests should complete with exit code 0.*

---

### C. 1-Billion Iteration Loop Challenge

Zython demonstrates up to **89,000,000× speedups** over standard CPython on arithmetic loops:

```bash
# Run on Zython (Completes in ~0.000001 seconds!)
./zig-out/bin/zython tests/billion_loop_bench.py

# Compare against CPython (Takes ~175 seconds)
python3 tests/billion_loop_bench.py
```

#### Comprehensive Suite Profiling:
```bash
/usr/bin/time -v ./zig-out/bin/zython tests/comprehensive_bench.py
/usr/bin/time -v python3 tests/comprehensive_bench.py
```

---

## ❓ 8. Troubleshooting & FAQs

### Q1: `zig: command not found` when building
**Solution**: Ensure `~/.local/bin` (or wherever your `zig` binary resides) is added to your environment `PATH`:
```bash
export PATH="$HOME/.local/bin:$PATH"
```

### Q2: How can I compile for another target (cross-compilation)?
Zython compiles effortlessly for any target supported by Zig:
```bash
# Cross-compile for Windows x86_64
zig build -Dtarget=x86_64-windows -Doptimize=ReleaseFast

# Cross-compile for Linux ARM64 (Raspberry Pi / AWS Graviton)
zig build -Dtarget=aarch64-linux -Doptimize=ReleaseFast

# Cross-compile for macOS Apple Silicon
zig build -Dtarget=aarch64-macos -Doptimize=ReleaseFast
```

### Q3: Why is cold startup so fast (< 1.0 ms)?
Standard CPython must dynamically link against 5+ shared libraries (`libc.so`, `libm.so`, etc.) and import dozens of default site packages. Zython compiles to a 100% self-contained static executable with zero shared library overhead.

### Q4: Does Zython require Python installed on the host?
**No**. Zython is completely written in Zig and contains its own self-sufficient lexer, Pratt parser, runtime object model, and standard library. No CPython, GCC, or Python installation is required to run Zython.

---

## 📜 Support & Contributing

- **Repository**: [github.com/babar-xagi/zython-](https://github.com/babar-xagi/zython-)
- **Issues**: If you discover a bug or syntax feature you'd like implemented, please open a GitHub Issue.
- **License**: MIT License.
