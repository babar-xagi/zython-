import ctypes
import sample_ext
from sample_ext import add, multiply

print("==========================================")
print("TEST 7: C-EXTENSIONS & CTYPES FFI")
print("==========================================")

# 1. Primitive C-Types & sizeof Inspection
int_size = ctypes.sizeof(ctypes.c_int)
long_size = ctypes.sizeof(ctypes.c_long)
double_size = ctypes.sizeof(ctypes.c_double)
float_size = ctypes.sizeof(ctypes.c_float)
char_p_size = ctypes.sizeof(ctypes.c_char_p)
void_p_size = ctypes.sizeof(ctypes.c_void_p)
bool_size = ctypes.sizeof(ctypes.c_bool)

print("1. ctypes Primitive Sizes:")
print("   c_int =", int_size, "| c_long =", long_size, "| c_double =", double_size)
print("   c_float =", float_size, "| c_char_p =", char_p_size, "| c_void_p =", void_p_size, "| c_bool =", bool_size)
assert int_size == 4
assert long_size == 8
assert double_size == 8
assert float_size == 4
assert char_p_size == 8
assert void_p_size == 8
assert bool_size == 1

# 2. Dynamic CDLL Loading & Integer Function Dispatch
lib = ctypes.CDLL("./libsample.so")
lib.add_numbers.restype = ctypes.c_int
lib.add_numbers.argtypes = [ctypes.c_int, ctypes.c_int]
res_int = lib.add_numbers(15, 27)
print("2. ctypes.CDLL Integer Call: add_numbers(15, 27) =", res_int)
assert res_int == 42

# 3. Dynamic CDLL Floating-Point Function Dispatch
lib.multiply_floats.restype = ctypes.c_double
lib.multiply_floats.argtypes = [ctypes.c_double, ctypes.c_double]
res_float = lib.multiply_floats(3.5, 2.0)
print("3. ctypes.CDLL Floating-Point Call: multiply_floats(3.5, 2.0) =", res_float)
assert res_float == 7.0

# 4. ctypes.cdll.LoadLibrary Convenience Dispatch
lib_cdll = ctypes.cdll.LoadLibrary("./libsample.so")
res_cdll = lib_cdll.add_numbers(100, 200)
print("4. ctypes.cdll.LoadLibrary Call: add_numbers(100, 200) =", res_cdll)
assert res_cdll == 300

# 5. CPython C-API Extension Module Import
print("5. CPython C-Extension Module:")
print("   Module representation =", repr(sample_ext))
ext_add_res = sample_ext.add(20, 22)
print("   sample_ext.add(20, 22) =", ext_add_res)
assert ext_add_res == 42

# 6. CPython C-API Extension Floating-Point Execution
ext_mul_res = sample_ext.multiply(2.5, 4.0)
print("6. CPython C-Extension Float Call: sample_ext.multiply(2.5, 4.0) =", ext_mul_res)
assert ext_mul_res == 10.0

# 7. Selective Symbol Import from C-Extension ('from sample_ext import ...')
sel_add = add(50, 60)
sel_mul = multiply(3.0, 7.0)
print("7. Selective Import: add(50, 60) =", sel_add, "| multiply(3.0, 7.0) =", sel_mul)
assert sel_add == 110
assert sel_mul == 21.0

# 8. Boundary & Multi-Call Verification
total_sum = 0
for i in range(10):
    total_sum += sample_ext.add(i, i)
print("8. Loop Stress Verification: total_sum =", total_sum)
assert total_sum == 90

print("C-Extensions & ctypes FFI evaluation complete.")
