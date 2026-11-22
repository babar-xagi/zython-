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

# 7. Bare Tuple Assignment & List Comprehension
a, b = 10, 20
a, b = b, a
print("7. Bare Tuple Assignment ('a, b = b, a'): a =", a, "b =", b)

lc = [x * 2 for x in range(5) if x % 2 == 0]
print("8. List Comprehension with Filter: lc =", lc)

# 9. Set Mutation Methods (add, remove)
s_mut = set([1, 2])
s_mut.add(3)
s_mut.remove(1)
has_1 = 1 in s_mut
has_3 = 3 in s_mut
print("9. Set add/remove: contains 1 =", has_1, "contains 3 =", has_3)

# 10. Decorator Execution (@decorator)
def make_bold(fn):
    def wrapper(text):
        return "[" + fn(text) + "]"
    return wrapper

@make_bold
def greet(name):
    return "Hello " + name

print("10. Decorator Execution: greet('Zython') =", greet("Zython"))

# 11. Context Manager ('with expr as var:')
class ScopeGuard:
    def __enter__(self):
        return 777
    def __exit__(self, exc_type, exc_val, exc_tb):
        pass

with ScopeGuard() as guard_val:
    print("11. Context Manager with 'with': Resource =", guard_val)

# 12. Remaining Roadmap Scope (Future Releases)
print("12. Future Scope Roadmap:")
print("   - Generators / yield frame suspension")
print("   - Async/await coroutine scheduler")
print("Ground reality edge-cases evaluation complete.")
