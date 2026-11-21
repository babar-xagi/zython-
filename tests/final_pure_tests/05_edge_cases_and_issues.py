print("==========================================")
print("TEST 5: GROUND REALITY EDGE CASES & LIMITATIONS")
print("==========================================")

# 1. 64-bit Integer Overflow Check
# CPython seamlessly transitions to bignum; Zython uses unboxed i64 with wrapping
max_i64 = 9223372036854775807
val_pow = 2 ** 64
print("1. Integer Over 64-bit (2**64):", val_pow)
if val_pow == 0:
    print("   -> Zython Behavior: 64-bit overflow wraps to 0 (unboxed i64)")
else:
    print("   -> CPython Behavior: Arbitrary-precision bignum preserved")

# 2. Formatted String (F-string) Interpolation
val = 42
f_str = f"The answer is {val}"
print("2. F-string Interpolation:", f_str)
if f_str == "The answer is {val}":
    print("   -> Zython Behavior: f-strings treated as raw literals without expression evaluation")
else:
    print("   -> CPython Behavior: Expressions inside {} interpolated")

# 3. Slicing Step Parameter ([start:stop:step])
nums = [1, 2, 3, 4, 5]
step_slice = nums[::2]
print("3. Slice with Step (nums[::2]):", step_slice)
if len(step_slice) == 5:
    print("   -> Zython Behavior: Step parameter in slicing is ignored")
else:
    print("   -> CPython Behavior: Stepped slicing returns [1, 3, 5]")

# 4. Exception Matching
caught_type = "None"
try:
    x = 1 / 0
except ZeroDivisionError as e:
    caught_type = "ZeroDivisionError"
except Exception as e:
    caught_type = "Exception"

print("4. Exception Handler Matching: Caught =", caught_type)

# 5. Set Operations (in operator)
s = set([10, 20, 30])
has_20 = 20 in s
print("5. Set Membership ('20 in s'):", has_20)
if not has_20:
    print("   -> Zython Issue: 'in' operator does not implement branch for .set, always returns False")
else:
    print("   -> CPython Behavior: Set O(1) membership returns True")

# 6. AST Cache Invalidation on 9th Scope Variable (> 8 fast_slots)
v1 = 1
v2 = 2
v3 = 3
v4 = 4
v5 = 5
v6 = 6
v7 = 7
v8 = 8
# Variable 9 overflows fast_slots array into bindings map
v9 = 0
observed_v9 = []
for i in range(4):
    v9 = i
    observed_v9.append(v9)

print("6. Mutating 9th Variable in Scope: Observed =", observed_v9)
if observed_v9 == [0, 0, 0, 0]:
    print("   -> Zython Issue: Variable beyond 8 fast_slots is frozen on first read by AST inline cache")
else:
    print("   -> CPython Behavior: All variable re-assignments reflect latest mutated value")

# 7. Syntax Limitations Summary
print("7. Syntax Features Not Implemented in Zython:")
print("   - List comprehensions: [x for x in r] (Causes ParseError)")
print("   - Bare tuple assignment: a, b = b, a (Requires parentheses: (a, b) = (b, a))")
print("   - Keywords in lexer not supported in parser: nonlocal, del")
print("   - Decorators (@decorator), 'with' statement, and generators/yield")
print("Ground reality edge-cases evaluation complete.")
