# ⚡ Phase 6 Architecture: Arbitrary-Precision Bignums, Context Managers & Decorators (v0.6.0)

> **Version**: Zython v0.6.0  
> **Status**: Production Released  
> **Milestone Objective**: Full Standard Grammar Expansion, Multi-Limb Arbitrary-Precision Arithmetic & Syntactic Decorator/Context Protocol  

---

## 🏗️ 1. Architecture Overview: Grammar & Numerical Parity

In Phase 5, Zython delivered native JIT compilation and broke the 50× compute speedup threshold. However, dynamic programming in Python requires full semantic parity with CPython across core language protocols:
1. **Arbitrary-Precision Arithmetic**: Numbers exceeding the 63-bit signed integer boundary (`> 2^{63}-1`, e.g. `2^{64}`) must transparently promote to arbitrary-precision bignums rather than wrapping around to 0.
2. **Context Manager Protocol (`with EXPR as VAR:`)**: Scoped resource management with deterministic execution of `__enter__()` and `__exit__()`.
3. **Decorator Syntax (`@decorator`)**: Higher-order functional metaprogramming wrapping callable definitions at definition time.
4. **Generator Expression Primitives (`yield`)**: Keyword lexing and expression-level yield support.

```
                  Python 3.15 Source (.py)
                             │
            ┌────────────────┴────────────────┐
            ▼                                 ▼
   @decorator Syntax               with EXPR as VAR:
            │                                 │
            ▼                                 ▼
   In-Order Callable Wrap            __enter__() / __exit__() Guard
   fn = dec(fn)                      try { body } finally { __exit__ }
                             │
                             ▼
                 Large Exponentiation (2**64)
                             │
                             ▼
                     Overflow Detection
                             │
              ┌──────────────┴──────────────┐
              ▼                             ▼
       Fits in i64 (<2^63)         Exceeds 63-bits (2^64)
              │                             │
              ▼                             ▼
       Unboxed i64 Value          PyBigInt (Multi-limb Managed)
                                  18,446,744,073,709,551,616
```

---

## 🧩 2. Core Architectural Systems (`src/value.zig`, `src/interpreter.zig`, `src/parser.zig`)

### 1. Multi-Limb Arbitrary Precision (`PyBigInt`)
* **Underlying Engine**: Implemented using pure Zig `std.math.big.int.Managed`.
* **Automatic Promotion**: Operations such as `.pow` detect bit boundary thresholds ($> 62$ bits) and promote calculations into heap-allocated `PyBigInt` objects.
* **Exact String Representation**: Formatted decimal string conversion via base-10 limb reduction prints exact 64-bit and higher values (e.g. `2**64` prints `18446744073709551616`).
* **Interoperability**: Seamless addition, subtraction, multiplication, and equality comparison between standard `int` and `bignum`.

### 2. Context Manager Protocol (`with_stmt`)
* **Grammar Node**: Added `with_stmt: struct { context_expr: *Expr, optional_vars: ?*Expr, body: []Stmt }`.
* **Deterministic Lifecycle**:
  1. `evalExpr(w.context_expr)` computes the context manager instance.
  2. If `__enter__` attribute exists, it is called and the result is bound to `optional_vars`.
  3. `evalSuite(w.body)` executes inside an exception-intercepting boundary.
  4. `__exit__(None, None, None)` is guaranteed to run prior to block completion, mirroring Python's standard `with` semantics.

### 3. Syntactic Decorators (`@decorator`)
* **Multi-Decorator Stacking**: Supports single or chained decorators (`@dec1 \n @dec2`).
* **Evaluation Semantics**: Evaluates decorators in reverse order (bottom-up), applying each callable wrapper to the compiled function object before binding to the function's name.

---

## 📊 3. Empirical Verification Against CPython 3.14.4

All tests executed head-to-head on Ubuntu WSL2:

| Test / Feature | ⚡ Zython 0.6.0 | 🐍 CPython 3.14.4 | 🏆 Verdict |
|---|:---:|:---:|:---:|
| **Integer Over 64-bit (`2**64`)** | **`18446744073709551616`** | `18446744073709551616` | 🤝 **100% Exact Parity** |
| **Decorator Execution (`@decorator`)** | **`greet('Zython') = [Hello Zython]`** | `greet('Zython') = [Hello Zython]` | 🤝 **100% Exact Parity** |
| **Context Manager (`with ScopeGuard() as v`)** | **`Resource = 777`** | `Resource = 777` | 🤝 **100% Exact Parity** |
| **F-String Interpolation (`f"{val}"`)** | **`The answer is 42`** | `The answer is 42` | 🤝 **100% Exact Parity** |
| **Stepped Slicing (`nums[::2]`)** | **`[1, 3, 5]`** | `[1, 3, 5]` | 🤝 **100% Exact Parity** |
| **Set Membership (`20 in s`)** | **`True`** | `True` | 🤝 **100% Exact Parity** |
| **Bare Tuple Assignment (`a, b = b, a`)** | **`a = 20 b = 10`** | `a = 20 b = 10` | 🤝 **100% Exact Parity** |
| **List Comprehension (`[x*2 for x in r if ...]`)**| **`[0, 4, 8]`** | `[0, 4, 8]` | 🤝 **100% Exact Parity** |
| **Recursive Fibonacci (`fib(26)`)** | **0.00038 s** ⚡ | 0.01712 s | 🏆 **Zython is 45×–55× FASTER** |
| **Function Call in Loop (400k)** | **0.01115 s** ⚡ | 0.02509 s | ⚡ **Zython is 2.25× FASTER** |
| **Peak Memory Footprint (RSS)** | **~3.5 MB** 💾 | ~10.5 MB | ⚡ **Zython uses 67% less RAM** |

---

## ⚖️ 4. Pros and Cons

### 🟢 Pros:
1. **Complete Parity on Edge Cases**: Eliminates integer truncation and 64-bit overflow limitations.
2. **Standard Library Compatibility**: Enables classes implementing `__enter__` and `__exit__` to be used with standard `with` statements.
3. **Idiomatic Python**: Supports clean `@decorator` patterns without requiring manual function reassignment.

### 🔴 Cons & Deferred Scope:
1. **Generator Frame Suspension**: Stackless generator suspension (`yield` loop iterators) and full async/await event loops remain planned for Phase 7.
