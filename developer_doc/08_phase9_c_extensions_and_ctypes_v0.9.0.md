# 🔌 Phase 9 Architecture: C-Extension FFI, `ctypes` & C-API Compatibility Bridge (v0.9.0)

> **Version**: Zython v0.9.0  
> **Status**: Production Released  
> **Milestone Objective**: Native `ctypes` standard module (`CDLL`, `cdll`, `sizeof`, `byref`, `c_*` primitives), CPython C-API Compatibility Layer (`src/capi.zig`), Dynamic Shared Library Loading (`.so` files), and C-Extension Bridge (`PyInit_<name>`)

---

## 🏗️ 1. Architecture Overview: Seamless Native & C-Extension Bridge

In **Phase 9 (v0.9.0)**, Zython achieves true interoperability with the broader C/C++ and native Python ecosystem. Developers can call external dynamic libraries (`.so`) with Zero-Overhead FFI via `ctypes`, as well as dynamically import and execute native CPython C-extension modules compiled with standard CPython headers or Zython's C-API compatibility layer.

```
                      Zython v0.9.0 Execution Runtime
                                     │
                ┌────────────────────┴────────────────────┐
                ▼                                         ▼
         ctypes Module                             CPython C-API
    ┌──────────────────────┐                   ┌──────────────────────┐
    │ • ctypes.CDLL(path)  │                   │ • import <module>.so │
    │ • ctypes.cdll        │                   │ • PyInit_<module>()  │
    │ • ctypes.sizeof()    │                   │ • PyMethodDef table  │
    │ • c_int, c_double... │                   │ • PyModuleDef spec   │
    └──────────┬───────────┘                   └──────────┬───────────┘
               │                                          │
               ▼                                          ▼
       std.DynLib / dlopen                     capi.loadCExtensionModule
  (Dynamic Symbol Resolution)                (Exported C-API Function Table)
               │                                          │
               ├──────────────────────────────────────────┤
               ▼                                          ▼
     Dynamic Call Dispatch                     PyObject Conversion Engine
┌───────────────────────────────┐        ┌───────────────────────────────┐
│ • Native ABI Calling Conv     │        │ • valueToPyObject()           │
│ • argtypes / restype cast     │        │ • pyObjectToValue()           │
│ • Float/Int/Pointer registers │        │ • PyLong, PyFloat, PyUnicode  │
│ • Multi-arg c_func dispatch   │        │ • PyTuple, PyList, PyDict     │
└───────────────────────────────┘        └───────────────────────────────┘
```

---

## 🧩 2. Core Architectural Subsystems

### 1. `ctypes` Standard Module Implementation (`src/builtins.zig`, `src/value.zig`)
* **Module Factory (`makeCtypesModule`)**:
  Exposes the canonical `ctypes` interface:
  - `CDLL`: Dynamic library loader wrapping `std.DynLib`.
  - `cdll`: Namespace object with `.LoadLibrary(path)`.
  - `sizeof`: Type inspection returning byte widths (`c_int: 4`, `c_double: 8`, `c_char_p: 8`, `c_void_p: 8`, `c_bool: 1`).
  - `byref`: In-memory reference generator.
  - Primitive type singletons: `c_int`, `c_long`, `c_double`, `c_float`, `c_char_p`, `c_void_p`, `c_bool`.
* **Dynamic Library Representation (`PyCDll`)**:
  Wraps OS `std.DynLib` handles with cached symbol lookup:
  ```zig
  pub const PyCDll = struct {
      name: []const u8,
      dyn_lib: std.DynLib,
      symbols: std.StringHashMap(Value),
      allocator: Allocator,
      ...
  };
  ```
* **C-Function Wrapper (`PyCFunc`)**:
  Stores native function addresses, signature specifications, and C-extension flags:
  ```zig
  pub const PyCFunc = struct {
      name: []const u8,
      addr: usize,
      restype: PyCType = .c_int,
      argtypes: std.ArrayList(PyCType),
      is_c_extension: bool = false,
      ml_flags: c_int = 0,
      allocator: Allocator,
  };
  ```

### 2. CPython C-API Compatibility Layer (`src/capi.zig`)
* **Binary-Compatible PyObject Structures**:
  Defines exact memory layouts matching the CPython 3.x C-API ABI:
  - `PyObject`: Base header with `ob_refcnt` and `ob_type`.
  - `PyLongObject`: 64-bit integer payload.
  - `PyFloatObject`: 64-bit IEEE 754 floating-point payload.
  - `PyUnicodeObject`: Length and UTF-8 encoded string pointer.
  - `PyTupleObject`: Fixed-size array of `PyObject*`.
  - `PyListObject`: Dynamic list buffer of `PyObject*`.
  - `PyDictObject`: Key-value entry hash table.
  - `PyMethodDef`: Name, function pointer, flags (`METH_VARARGS`, `METH_NOARGS`), and docstring.
  - `PyModuleDef`: Module initialization metadata and method table.
  - `PyModuleObject`: Initialized module instance.
* **Exported C-API Functions (`pub export fn`)**:
  Exported with `-rdynamic` in `build.zig` so loaded shared libraries resolve symbols directly:
  - `PyLong_FromLong`, `PyLong_FromLongLong`, `PyLong_AsLong`, `PyLong_AsLongLong`
  - `PyFloat_FromDouble`, `PyFloat_AsDouble`
  - `PyUnicode_FromString`, `PyUnicode_AsUTF8`
  - `PyTuple_New`, `PyTuple_SetItem`, `PyTuple_GetItem`, `PyTuple_Size`
  - `PyList_New`, `PyList_Append`, `PyList_GetItem`, `PyList_Size`
  - `PyDict_New`
  - `PyModule_Create2`
  - `Py_IncRef`, `Py_DecRef`

### 3. Dynamic Module Loading & Dispatch (`src/interpreter.zig`)
* **Extension Import Resolution**:
  When `import <module>` or `from <module> import ...` is encountered:
  1. Searches current directory (`./<module>.so`) and `/tmp/<module>.so`.
  2. Resolves `PyInit_<module>` using `std.DynLib`.
  3. Executes `PyInit_<module>()` to obtain `PyModuleDef` and method tables.
  4. Binds module attributes to `Value{ .c_func = ... }` instances marked with `is_c_extension = true`.
* **Argument Marshaling & Return Dispatch**:
  - `is_c_extension == true`: Converts Python arguments into a `PyTupleObject*`, passes `(self, args)` to the C function, and decodes the resulting `PyObject*` via `pyObjectToValue` with automatic type discrimination (`ob_type`).
  - Standard FFI (`ctypes`): Dispatches native C calling conventions across integer and float registers based on configured `argtypes` and `restype`.

---

## 📊 3. Verification & Empirical Results

The Phase 9 implementation was verified through test suite `tests/final_pure_tests/07_c_extensions_and_ctypes.py`:

```
==========================================
TEST 7: C-EXTENSIONS & CTYPES FFI
==========================================
1. ctypes Primitive Sizes:
   c_int = 4 | c_long = 8 | c_double = 8
   c_float = 4 | c_char_p = 8 | c_void_p = 8 | c_bool = 1
2. ctypes.CDLL Integer Call: add_numbers(15, 27) = 42
3. ctypes.CDLL Floating-Point Call: multiply_floats(3.5, 2.0) = 7.0
4. ctypes.cdll.LoadLibrary Call: add_numbers(100, 200) = 300
5. CPython C-Extension Module:
   Module representation = <module 'sample_ext'>
   sample_ext.add(20, 22) = 42
6. CPython C-Extension Float Call: sample_ext.multiply(2.5, 4.0) = 10.0
7. Selective Import: add(50, 60) = 110 | multiply(3.0, 7.0) = 21.0
8. Loop Stress Verification: total_sum = 90
C-Extensions & ctypes FFI evaluation complete.
```

All 7 test suites pass cleanly across all subsystems:
- `01_compute_and_algorithms.py`: PASS (Primes, Fib, Insertion Sort, Taylor Series)
- `02_data_structures_and_collections.py`: PASS (80k Lists, 40k Dicts, 30k Tuples, Strings)
- `03_oop_polymorphism.py`: PASS (50k Small OOP, 25k Polymorphic, 15k Heavy Objects)
- `04_loop_mechanics_ground_reality.py`: PASS (10M Pattern Loops, 2M Branching Loops, 1M 2D Loops)
- `05_edge_cases_and_issues.py`: PASS (Bignum 2**64, F-strings, Slicing, Try/Except, Comprehensions, Decorators)
- `06_multithreading_and_concurrency.py`: PASS (OS Threads, Mutex, RLock, Semaphore, Event, ThreadPoolExecutor)
- `07_c_extensions_and_ctypes.py`: PASS (ctypes FFI, CDLL, CPython C-API Module Import & Execution)
