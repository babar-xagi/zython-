# 🐛 Zython Technical Bug Audit & Architectural Issues Log

This document provides an exhaustive, root-cause analysis of all functional bugs, architectural defects, and grammar limitations discovered during empirical testing of **Zython 0.1.0** against Python 3.14/3.15.

---

## 📑 Summary of Issues

| ID | Issue Description | Severity | Affected Component | Status |
|:---:|---|:---:|---|:---:|
| **BUG-01** | Variable freezing beyond 8 fast slots | 🔴 **Critical** | `src/interpreter.zig:622` | ✅ **RESOLVED & VERIFIED** |
| **BUG-02** | Attribute `+=` and `-=` crashes (`TypeError`) | 🔴 **Critical** | `src/interpreter.zig:909` | ✅ **RESOLVED & VERIFIED** |
| **BUG-03** | Set `in` operator always returns `False` | 🟠 **Major** | `src/interpreter.zig:997` | ✅ **RESOLVED & VERIFIED** |
| **BUG-04** | Set iteration throws `TypeError` | 🟠 **Major** | `src/interpreter.zig:381` | ✅ **RESOLVED & VERIFIED** |
| **BUG-05** | F-strings lack expression interpolation | 🟡 **Medium** | `src/lexer.zig:231` | ✅ **RESOLVED & VERIFIED** |
| **BUG-06** | Slicing completely ignores `step` parameter | 🟡 **Medium** | `src/interpreter.zig:1284`| ✅ **RESOLVED & VERIFIED** |
| **BUG-07** | Exception type matching is bypassed | 🟡 **Medium** | `src/interpreter.zig:473`| ✅ **RESOLVED & VERIFIED** |
| **BUG-08** | Bare tuple assignment requires parentheses | 🔵 **Minor** | `src/parser.zig:586` | ✅ **RESOLVED & VERIFIED** |
| **BUG-09** | 64-bit integer overflow wrapping | 🔵 **Minor** | `src/interpreter.zig:650` | ℹ️ **Documented Architectural Tradeoff** |

---

## 🔍 Detailed Root Cause Analysis & Reproduction

### 🔴 BUG-01: Variable Value Freezing Beyond 8 Fast Slots (AST Inline Cache Bug)

#### Description
When a function or global scope defines more than 8 variables, any variable beyond the 8th slot is allocated in the overflow `bindings` hash map. When this 9th variable is read in a loop, its value is permanently frozen on the first read. Subsequent mutations inside the loop are ignored by the AST node.

#### Root Cause
In `src/interpreter.zig`, lines 606–628:
```zig
.identifier => |*id| {
    if (id.slot_idx < env.fast_count) {
        const slot = &env.fast_slots[id.slot_idx];
        if (slot.name.ptr == id.name.ptr or std.mem.eql(u8, slot.name, id.name)) {
            return slot.val;
        }
    }
    if (id.cached_val) |cv| {
        return cv; // <-- Returns stale cached value!
    }
    var i: u8 = 0;
    while (i < env.fast_count) : (i += 1) { ... }
    if (env.get(id.name)) |v| {
        if (env.parent != null) {
            id.cached_val = v; // <-- Permanently caches mutable variable on AST node!
        }
        return v;
    }
```
Because `global_env.parent` is set to `builtins_env`, `env.parent != null` is **always true**. If a variable is not in `fast_slots` ($>8$ variables), the AST node caches the first value it reads and never invalidates it when the variable is re-assigned.

#### Reproduction
```python
v1=1; v2=2; v3=3; v4=4; v5=5; v6=6; v7=7; v8=8
# Variable 9 overflows fast_slots
v9 = 0
for i in range(4):
    v9 = i
    print(v9)
```
* **Expected**: `0, 1, 2, 3`
* **Actual (Zython)**: `0, 0, 0, 0`

#### Recommended Fix
Only cache values on `IdentExpr` if the variable is confirmed to be an immutable constant (or in `builtins_env`/`modules`), or implement epoch-based cache validation.

---

### 🔴 BUG-02: Augmented Assignment (`+=`, `-=`) on Object Attributes Fails with `TypeError`

#### Description
Augmented assignment on local variables (`x += 1`) works via direct fast-slot pointer mutation. However, augmented assignment on attributes (`self.hp -= dmg` or `obj.counter += 1`) crashes at runtime with `RuntimeError: TypeError`.

#### Root Cause
In `src/interpreter.zig`, lines 159–163:
```zig
const rhs = try self.evalExpr(aa.value, env);
const cur = try self.evalExpr(aa.target, env);
const updated = try self.evalBinaryOp(cur, aa.op, rhs);
try self.assignTarget(aa.target, updated, env);
```
In `evalBinaryOp` (lines 909–915):
```zig
.sub => {
    if (left == .float and right == .float) return Value.makeFloat(left.float - right.float);
    if (left == .int and right == .float) return Value.makeFloat(@as(f64, @floatFromInt(left.int)) - right.float);
    if (left == .float and right == .int) return Value.makeFloat(left.float - @as(f64, @floatFromInt(right.int)));
    return error.TypeError; // <-- Missing 'if (left == .int and right == .int)'!
}
```
`evalBinaryOp` omits the integer addition and subtraction branches (`left == .int and right == .int`), immediately returning `error.TypeError`.

#### Reproduction
```python
class Character:
    def __init__(self, hp):
        self.hp = hp
    def take_damage(self, dmg):
        self.hp -= dmg # Crashes!

c = Character(100)
c.take_damage(25)
```
* **Expected**: `c.hp == 75`
* **Actual (Zython)**: `RuntimeError: TypeError`

#### Recommended Fix
Add integer handling in `evalBinaryOp` for `.add` and `.sub`:
```zig
if (left == .int and right == .int) return Value.makeInt(left.int - right.int);
```

---

### 🟠 BUG-03: Set Membership (`in` operator) Always Returns `False`

#### Description
Testing whether an element is present in a set (`x in my_set`) always evaluates to `False`.

#### Root Cause
In `src/interpreter.zig`, lines 997–1012:
```zig
.in => {
    if (right == .list) { ... }
    else if (right == .tuple) { ... }
    else if (right == .string and left == .string) { ... }
    else if (right == .dict) { ... }
    return false; // <-- No branch for 'right == .set'!
}
```
The comparison operator lacks an `else if (right == .set)` branch.

#### Reproduction
```python
s = set([10, 20, 30])
print(20 in s)
```
* **Expected**: `True`
* **Actual (Zython)**: `False`

#### Recommended Fix
Add set membership check:
```zig
else if (right == .set) {
    return right.set.contains(left);
}
```

---

### 🟠 BUG-04: Iterating Over a Set Throws `TypeError`

#### Description
Executing a `for` loop over a `set` crashes with `RuntimeError: TypeError`.

#### Root Cause
In `src/interpreter.zig`, lines 253–382:
The `for_stmt` evaluator handles `.range`, `.list`, `.tuple`, `.string`, and `.dict`. Any other value type falls through to line 381:
```zig
else => return error.TypeError,
```
`.set` is not handled as an iterable.

#### Reproduction
```python
s = set([1, 2, 3])
for x in s:
    print(x)
```
* **Expected**: Prints elements 1, 2, 3
* **Actual (Zython)**: `RuntimeError: TypeError`

#### Recommended Fix
Add iteration support for `.set` in `for_stmt`:
```zig
.set => |st| {
    for (st.items.items) |it| {
        try self.assignTarget(f.target, it, env);
        const res = try self.evalSuite(f.body, env);
        ...
    }
}
```

---

### 🟡 BUG-05: Formatted String (F-string) Interpolation Not Implemented

#### Description
Strings with the `f` or `F` prefix treat expressions inside `{...}` as raw string characters without evaluating them.

#### Root Cause
In `src/lexer.zig`, lines 231–238:
When detecting `f"` or `f'`, the lexer routes directly into `scanString`, which consumes characters up to the closing quote without parsing interpolation expressions.

#### Reproduction
```python
name = "Zython"
print(f"Hello {name}")
```
* **Expected**: `Hello Zython`
* **Actual (Zython)**: `Hello {name}`

---

### 🟡 BUG-06: Slicing Completely Ignores the `step` Parameter

#### Description
Slice syntax `arr[start:stop:step]` ignores the third argument (`step`). Reverse slicing (`arr[::-1]`) or stepping (`arr[::2]`) returns the full list unmodified.

#### Root Cause
In `src/interpreter.zig`, lines 1284–1317 (`evalSubscript`):
```zig
const lower_i: ?i64 = if (slice.lower) |le| (try self.evalExpr(le, env)).int else null;
const upper_i: ?i64 = if (slice.upper) |ue| (try self.evalExpr(ue, env)).int else null;
// slice.step is never evaluated or used!
```

#### Reproduction
```python
nums = [1, 2, 3, 4, 5]
print(nums[::2])
print(nums[::-1])
```
* **Expected**: `[1, 3, 5]` and `[5, 4, 3, 2, 1]`
* **Actual (Zython)**: `[1, 2, 3, 4, 5]` and `[1, 2, 3, 4, 5]`

---

### 🟡 BUG-07: Exception Type Matching Is Bypassed in `try/except`

#### Description
When an exception is thrown, the first `except` block is executed unconditionally, regardless of whether the caught exception matches the specified exception type.

#### Root Cause
In `src/interpreter.zig`, lines 473–481:
```zig
if (exc_raised and t.handlers.len > 0) {
    for (t.handlers) |h| {
        if (h.name) |name| {
            const exc_str = try Value.makeString(self.allocator, "Exception");
            try env.set(name, exc_str);
        }
        result = try self.evalSuite(h.body, env);
        break; // <-- Executes the very first handler unconditionally!
    }
}
```
`h.exc_type` is never evaluated or matched against the raised error.

---

### 🔵 BUG-08: Bare Tuple Assignment Requires Parentheses

#### Description
Python allows tuple packing/unpacking without parentheses (`a, b = b, a`). In Zython, this produces a syntax error.

#### Root Cause
In `src/parser.zig`, expression statements do not parse bare comma-separated expressions as tuples unless enclosed in `(...)`.

#### Reproduction
```python
a = 1; b = 2
a, b = b, a # Fails!
(a, b) = (b, a) # Works
```
* **Actual Error**: `Unexpected token in primary expression: comma (',') at 1:16`

---

### 🔵 BUG-09: 64-bit Integer Overflow Wrapping

#### Description
Zython represents integers as unboxed 64-bit signed integers (`int: i64`). Calculations exceeding $2^{63}-1$ wrap around with wrapping arithmetic (`*%=`, `+%`), whereas standard Python seamlessly promotes to arbitrary-precision bignums.

#### Reproduction
```python
print(2 ** 64)
```
* **Expected**: `18446744073709551616`
* **Actual (Zython)**: `0`
