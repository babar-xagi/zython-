# CORRECTNESS_RESULTS.md - differential test, Zython vs CPython 3.14

223 tiny snippets, each run in its **own process** on both interpreters; CPython is the oracle; stdout must match byte-for-byte.

Status legend: PASS = identical output, WRONG = ran but printed something different (silent wrong answer), ERROR = Zython raised/exited non-zero where CPython succeeded, CRASH = segfault.

| Category | Total | PASS | WRONG output | Zython error | CRASH | Pass rate |
|---|---:|---:|---:|---:|---:|---:|
| arith | 29 | 20 | 4 | 5 | 0 | 69% |
| bignum | 18 | 3 | 12 | 3 | 0 | 17% |
| float | 25 | 11 | 5 | 9 | 0 | 44% |
| string | 28 | 12 | 3 | 13 | 0 | 43% |
| container | 40 | 17 | 7 | 16 | 0 | 42% |
| control | 35 | 19 | 2 | 12 | 2 | 54% |
| oop | 20 | 3 | 5 | 12 | 0 | 15% |
| stdlib | 28 | 9 | 3 | 16 | 0 | 32% |
| **TOTAL** | **223** | **94** | **41** | **86** | **2** | **42%** |

**Silent wrong answers (`WRONG`) are the most dangerous category** - the program keeps running and prints a plausible but incorrect result.

## Silent wrong output

| Snippet | CPython printed | Zython printed / error |
|---|---|---|
| `arith/pow_mod3` | `959082` | `6627890308811632801` |
| `arith/pow_mod_big` | `688423210` | `0` |
| `arith/round_banker` | `(0, 2, 2)` | `(1, 2, 3)` |
| `arith/round_digits` | `2.67` | `2.68` |
| `bignum/add_overflow` | `9223372036854775808` | `-9223372036854775808` |
| `bignum/mul_overflow` | `9223372037000250000` | `-9223372036709301616` |
| `bignum/mul_overflow2` | `18446744073709551614` | `-2` |
| `bignum/sub_overflow` | `-9223372036854775817` | `9223372036854775799` |
| `bignum/neg_overflow` | `9223372036854775808` | `-9223372036854775808` |
| `bignum/factorial_loop_30` | `265252859812191058636308480000000` | `-8764578968847253504` |
| `bignum/fib_big_loop` | `280571172992510140037611932413038677189525` | `-1123705814761610347` |
| `bignum/accumulate_overflow` | `1180591620717411303424` | `0` |
| `bignum/accumulate_add_overflow` | `9223372036854776000` | `-9223372036854775616` |
| `bignum/big_floordiv` | `142857142857142857142857142857` | `725277752900751945` |
| `bignum/big_mod` | `85` | `65` |
| `bignum/big_cmp` | `True` | `False` |
| `float/float_big_str` | `1e+16` | `10000000000000000.0` |
| `float/float_small_str` | `1e-05` | `0.00001` |
| `float/format_2f` | `3.14` | `3.14159` |
| `float/format_pad` | `42\|42      \|00000042` | `42\|42\|42` |
| `float/format_comma` | `1,234,567` | `1234567` |
| `string/repr_quotes` | `"it's"` | `'it's'` |
| `string/unicode_len` | `5` | `6` |
| `string/unicode_upper` | `HÉLLO` | `HéLLO` |
| `container/list_slice_assign` | `[1, 9, 9, 9, 4]` | `[1, 2, 3, 4]` |
| `container/sorted_key` | `[3, 2, 1]` | `[1, 2, 3]` |
| `container/sorted_rev` | `[3, 2, 1]` | `[1, 2, 3]` |
| `container/sorted_stable` | `[(0, 'z'), (1, 'b'), (1, 'a')]` | `[(1, 'b'), (0, 'z'), (1, 'a')]` |
| `container/enumerate_start` | `[(1, 'a'), (2, 'b')]` | `[]` |
| `container/tuple_cmp` | `True` | `False` |
| `container/max_key` | `cccc` | `aa` |
| `control/try_except_finally` | `zde division by zero / fin` | `zde ZeroDivisionError / fin` |
| `control/assert_fail` | `ae msg` | `ae AssertionError` |
| `oop/dunder_repr` | `P(1) [P(2)]` | `<P object> [<P object>]` |
| `oop/dunder_eq_lt` | `True True [P(1), P(3)]` | `False False [<P object>, <P object>]` |
| `oop/str_dunder` | `cee cee` | `<C object> <C object>` |
| `oop/default_obj_repr_prefix` | `<__main__.` | `<C object>` |
| `oop/dunder_contains_bool` | `True False` | `False True` |
| `stdlib/import_random_seed` | `0.6394267984578837` | `0.6969372117194047` |
| `stdlib/file_io` | `['hi', 'there']` | `['hi / there / ']` |
| `stdlib/bytes_ops` | `3 97 [97, 98, 99]` | `3 a ['a', 'b', 'c']` |

## Crashes (segfault)

| Snippet | CPython printed | Zython printed / error |
|---|---|---|
| `control/recursion_900` | `900` | segfault (rc=-11) |
| `control/recursion_limit_error` | `recursion error` | segfault (rc=-11) |

## Zython errors where CPython works

| Snippet | CPython printed | Zython printed / error |
|---|---|---|
| `arith/divmod` | `(3, 2)` |  `RuntimeError: NameError` |
| `arith/divmod_neg` | `(-4, 3)` |  `RuntimeError: NameError` |
| `arith/bit_length` | `8` |  `RuntimeError: AttributeError` |
| `arith/hex_bin_oct` | `('0xff', '0b101', '0o10')` |  `RuntimeError: NameError` |
| `arith/sum_genexp` | `285` |  `RuntimeError: ParseError` |
| `bignum/factorial_25` | `15511210043330985984000000` |  `RuntimeError: AttributeError` |
| `bignum/big_str_to_int` | `123456789012345678901234567891` |  `RuntimeError: Overflow` |
| `bignum/sys_maxsize` | `9223372036854775807` |  `RuntimeError: AttributeError` |
| `float/math_exp` | `2.718281828459045` |  `RuntimeError: AttributeError` |
| `float/math_log` | `2.302585092994046` |  `RuntimeError: AttributeError` |
| `float/math_log2` | `3.0` |  `RuntimeError: AttributeError` |
| `float/math_atan2` | `0.4636476090008061` |  `RuntimeError: AttributeError` |
| `float/math_hypot` | `5.0` |  `RuntimeError: AttributeError` |
| `float/math_gcd` | `6` |  `RuntimeError: AttributeError` |
| `float/math_isqrt` | `9` |  `RuntimeError: AttributeError` |
| `float/math_fabs_pow` | `1.4142135623730951` |  `RuntimeError: AttributeError` |
| `float/format_pct` | `3.1\|5\|x` |  `RuntimeError: TypeError` |
| `string/methods_basic` | `helloHELLOa b` |  `RuntimeError: AttributeError` |
| `string/find_replace` | `(2, 'aXcaXc')` |  `RuntimeError: AttributeError` |
| `string/isdigit_isalpha` | `(True, True)` |  `RuntimeError: AttributeError` |
| `string/str_format` | `1-2` |  `RuntimeError: AttributeError` |
| `string/str_format_named` | `1-2` |  `RuntimeError: AttributeError` |
| `string/count_str` | `2` |  `RuntimeError: AttributeError` |
| `string/center_zfill` | `('**ab**', '00042')` |  `RuntimeError: AttributeError` |
| `string/title_cap` | `('Hello World', 'Hello')` |  `RuntimeError: AttributeError` |
| `string/ljust_rjust` | `('a..', '..a')` |  `RuntimeError: AttributeError` |
| `string/partition` | `('a', '=', 'b=c')` |  `RuntimeError: AttributeError` |
| `string/splitlines` | `['a', 'b', 'c']` |  `RuntimeError: AttributeError` |
| `string/strip_chars` | `hi` |  `RuntimeError: AttributeError` |
| `string/encode` | `b'abc'` |  `RuntimeError: AttributeError` |
| `container/list_index_count` | `(1, 2)` |  `RuntimeError: AttributeError` |
| `container/list_methods` | `[9, 7, 5, 3, 2] 8` |  `RuntimeError: AttributeError` |
| `container/list_del` | `[1, 3, 4]` |  `RuntimeError: ParseError` |
| `container/map_filter` | `[3, 4]` |  `RuntimeError: NameError` |
| `container/any_all` | `(True, False)` |  `RuntimeError: NameError` |
| `container/dict_items` | `[('a', 1), ('b', 2)]` |  `RuntimeError: AttributeError` |
| `container/dict_comp` | `{0: 0, 1: 1, 2: 4}` |  `RuntimeError: ParseError` |
| `container/dict_mutation` | `{0: 0, 1: 1, 4: 16, 9: 1} 5 9 True` |  `RuntimeError: ParseError` |
| `container/dict_setdefault` | `{'a': [1, 2]}` |  `RuntimeError: AttributeError` |
| `container/set_ops` | `[1, 2, 3, 4] [2, 3] [1, 3]` |  `RuntimeError: TypeError` |
| `container/set_dedupe` | `[1, 2, 3]` |  `RuntimeError: TypeError` |
| `container/set_comp` | `[0, 1, 2]` |  `RuntimeError: ParseError` |
| `container/list_comp_nested` | `[(0, 0), (0, 1), (1, 0), (1, 1)]` |  `RuntimeError: ParseError` |
| `container/tuple_unpack_star` | `(1, (2, 3))` |  `RuntimeError: ParseError` |
| `container/unpack_star_assign` | `1 [2, 3, 4] 5` |  `RuntimeError: ParseError` |
| `container/range_len_index` | `(10, 3, [10, 7, 4, 1])` |  `RuntimeError: TypeError` |
| `control/walrus` | `10` |  `RuntimeError: ParseError` |
| `control/raise_custom` | `caught boom` |  `RuntimeError: NameError` |
| `control/valueerror` | `ve` |  `RuntimeError: InvalidCharacter` |
| `control/kwonly` | `6` |  `RuntimeError: ParseError` |
| `control/closure_nonlocal` | `2` |  `RuntimeError: ParseError` |
| `control/closure_loop_capture` | `[0, 1, 2]` |  `RuntimeError: ParseError` |
| `control/generator_expr_lazy` | `0 [2, 4]` |  `RuntimeError: ParseError` |
| `control/yield_from` | `[1, 2, 3]` |  `RuntimeError: ParseError` |
| `control/decorator` | `2` |  `RuntimeError: ParseError` |
| `control/lambda_default` | `4` |  `RuntimeError: ParseError` |
| `control/match_stmt` | `two` |  `RuntimeError: ParseError` |
| `control/star_call` | `3 8` |  `RuntimeError: ParseError` |
| `oop/dunder_add` | `3` |  `RuntimeError: TypeError` |
| `oop/dunder_len_getitem` | `4 6` |  `RuntimeError: TypeError` |
| `oop/dunder_hash_dict` | `a` |  `RuntimeError: KeyError` |
| `oop/super_init` | `3 1 Q True` |  `RuntimeError: NameError` |
| `oop/staticmethod` | `2` |  `RuntimeError: NameError` |
| `oop/classmethod` | `3` |  `RuntimeError: NameError` |
| `oop/property` | `8` |  `RuntimeError: NameError` |
| `oop/getattr_setattr` | `3 False` |  `RuntimeError: NameError` |
| `oop/iter_protocol` | `[1, 2, 3]` |  `RuntimeError: TypeError` |
| `oop/dunder_call` | `8` |  `RuntimeError: NotCallable` |
| `oop/type_name` | `int str list` |  `RuntimeError: AttributeError` |
| `oop/isinstance_tuple` | `True True` |  `RuntimeError: TypeError` |
| `stdlib/import_collections` | `[('b', 3)]` |  `RuntimeError: ImportError` |
| `stdlib/import_itertools` | `[(1, 2, 3), (1, 3, 2)]` |  `RuntimeError: ImportError` |
| `stdlib/import_functools` | `6` |  `RuntimeError: ImportError` |
| `stdlib/import_re` | `['12', '345']` |  `RuntimeError: ImportError` |
| `stdlib/import_heapq` | `1` |  `RuntimeError: ImportError` |
| `stdlib/import_bisect` | `2` |  `RuntimeError: ImportError` |
| `stdlib/import_string` | `abc` |  `RuntimeError: ImportError` |
| `stdlib/import_dataclasses` | `1` |  `RuntimeError: ParseError` |
| `stdlib/import_typing` | `3` |  `RuntimeError: ImportError` |
| `stdlib/print_file_stderr` | `ok` |  `RuntimeError: AttributeError` |
| `stdlib/input_absent` | `builtin_function_or_method` |  `RuntimeError: NameError` |
| `stdlib/complex_num` | `(-2+1j)` |  `RuntimeError: NameError` |
| `stdlib/fractions` | `1/2` |  `RuntimeError: ImportError` |
| `stdlib/decimal` | `0.3` |  `RuntimeError: ImportError` |
| `stdlib/statistics` | `2.5` |  `RuntimeError: ImportError` |
| `stdlib/array_module` | `2` |  `RuntimeError: ImportError` |

