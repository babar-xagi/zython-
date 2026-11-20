# Zython ⚡

A high-performance Python 3.15-compatible interpreter and runtime written from scratch in **Zig 0.17.1**.

Zython is designed for instant compilation times, memory safety without garbage collector pauses, and seamless execution of existing Python code, algorithms, and data structures.

---

## Features

- **Blazing Fast Compilation**: Compiles the entire interpreter in seconds using `zig build -Doptimize=ReleaseFast`.
- **Zero Heavy Runtime Dependencies**: Pure Zig implementation of the lexer, parser, runtime, AST evaluator, object system, and standard builtins.
- **Python 3.15 Syntax & Semantics**:
  - **Data Types**: Integers (`int`), IEEE 754 Floats (`float`), Strings (`str`), Booleans (`bool`), `NoneType`, Lists (`list`), Tuples (`tuple`), Dictionaries (`dict`), Sets (`set`), and Ranges (`range`).
  - **Full Control Flow**: `if` / `elif` / `else`, `while` with `break` and `continue`, `for ... in` loops with `range()` and iterables.
  - **Functions & Scopes**: User-defined functions (`def`), arbitrary recursion, default arguments, keyword arguments, `*args`, `**kwargs`, closures, and lambda expressions (`lambda`).
  - **Object-Oriented Programming (OOP)**: Classes (`class`), constructors (`__init__`), single and multi-level inheritance, bound methods (`self`), instance attributes, and `isinstance()`.
  - **Exception Handling**: `try` / `except ... as ...` / `finally` blocks, `raise` statements, and detailed assertion error messages (`assert`).
  - **Built-in Functions**: `print`, `len`, `range`, `type`, `int`, `float`, `str`, `repr`, `bool`, `list`, `tuple`, `dict`, `set`, `sum`, `min`, `max`, `abs`, `round`, `pow`, `ord`, `chr`, `callable`, `isinstance`, `enumerate`, `zip`, `reversed`, `sorted`.
  - **Standard Modules**:
    - `math`: `pi`, `e`, `tau`, `inf`, `nan`, `sqrt`, `sin`, `cos`, `floor`, `ceil`.
    - `time`: `time()`, `perf_counter()`, `sleep()`.
    - `sys`: `argv`, `version`, `platform`, `exit()`.

---

## Project Structure

```
zython-/
├── build.zig           # Zig 0.17 build script
├── build.zig.zon       # Zig package metadata
├── src/
│   ├── main.zig        # CLI entry point, argument parser, and script runner
│   ├── repl.zig        # Interactive REPL shell (>>> and ...)
│   ├── value.zig       # Value tagged union, PyString, PyList, PyDict, PyClass, PyInstance
│   ├── token.zig       # Token declarations and Python keyword maps
│   ├── lexer.zig       # Indentation-aware lexer (INDENT/DEDENT, strings, numbers)
│   ├── ast.zig         # AST node hierarchy (Statements, Expressions, Operators)
│   ├── parser.zig      # Recursive descent & Pratt expression precedence parser
│   ├── environment.zig # Lexical scope resolution, closures, and variable tables
│   ├── builtins.zig    # Python built-in functions and native modules (math, time, sys)
│   └── interpreter.zig # Core evaluation engine and method dispatcher
└── tests/
    ├── test_basic.py       # Arithmetic, bitwise, comparison, strings
    ├── test_control.py     # If/elif/else, while, for, break, continue
    ├── test_functions.py   # Recursion, defaults, closures, lambdas
    ├── test_classes.py     # Classes, inheritance, __init__, methods, isinstance
    └── test_benchmark.py   # Performance benchmarks (Fibonacci, primes, sorting)
```

---

## Building & Running

### Requirements
- [Zig](https://ziglang.org/) **0.17.1** or higher.

### Build Executable
```bash
# Debug build (instant compile)
zig build

# Optimized Release build (maximum execution speed)
zig build -Doptimize=ReleaseFast
```
The executable is generated at `zig-out/bin/zython`.

---

## Usage

### 1. Interactive REPL
Launch the interactive shell by running `zython` without arguments:
```bash
./zig-out/bin/zython
```
```python
Zython 0.1.0 (Python 3.15 compatibility layer, Zig 0.17.1)
Type 'exit()' to exit.
>>> 10 + 20 * 3
70
>>> [x * 2 for x in [1, 2, 3]] # or functions
>>> def square(x): return x * x
... 
>>> square(9)
81
>>> exit()
```

### 2. Execute One-Liners (`-c`)
```bash
./zig-out/bin/zython -c "import math; print('Pi is', math.pi)"
```

### 3. Run Python Files
```bash
./zig-out/bin/zython tests/test_basic.py
./zig-out/bin/zython tests/test_benchmark.py
```

---

## Verification & Testing

Run all test suites against Zython:
```bash
./zig-out/bin/zython tests/test_basic.py
./zig-out/bin/zython tests/test_control.py
./zig-out/bin/zython tests/test_functions.py
./zig-out/bin/zython tests/test_classes.py
./zig-out/bin/zython tests/test_benchmark.py
```
Outputs match official CPython 3 character-for-character.
