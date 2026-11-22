const std = @import("std");
const Allocator = std.mem.Allocator;
const value_mod = @import("value.zig");
const Value = value_mod.Value;
const PyString = value_mod.PyString;
const PyList = value_mod.PyList;
const PyTuple = value_mod.PyTuple;
const PyDict = value_mod.PyDict;
const PySet = value_mod.PySet;
const PyRange = value_mod.PyRange;
const PyBuiltin = value_mod.PyBuiltin;
const PyModule = value_mod.PyModule;
const DictEntry = value_mod.DictEntry;
const Environment = @import("environment.zig").Environment;

fn writeStdout(bytes: []const u8) void {
    _ = std.posix.system.write(1, bytes.ptr, bytes.len);
}

pub fn builtinPrint(allocator: Allocator, _: ?*anyopaque, args: []const Value, kwargs: []const DictEntry) anyerror!Value {
    var sep: []const u8 = " ";
    var end: []const u8 = "\n";

    for (kwargs) |kw| {
        if (kw.key == .string) {
            if (std.mem.eql(u8, kw.key.string.bytes, "sep") and kw.val == .string) {
                sep = kw.val.string.bytes;
            } else if (std.mem.eql(u8, kw.key.string.bytes, "end") and kw.val == .string) {
                end = kw.val.string.bytes;
            }
        }
    }

    for (args, 0..) |arg, i| {
        if (i > 0) writeStdout(sep);
        const str_rep = try arg.str(allocator);
        writeStdout(str_rep);
    }
    writeStdout(end);

    return .none;
}

pub fn builtinLen(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    _ = allocator;
    if (args.len != 1) return error.TypeError;
    const v = args[0];
    switch (v) {
        .string => |s| return Value.makeInt(@intCast(s.bytes.len)),
        .list => |l| return Value.makeInt(@intCast(l.items.items.len)),
        .tuple => |t| return Value.makeInt(@intCast(t.items.len)),
        .dict => |d| return Value.makeInt(@intCast(d.entries.items.len)),
        .set => |s| return Value.makeInt(@intCast(s.items.items.len)),
        .range => |r| return Value.makeInt(@intCast(r.length())),
        else => return error.TypeError,
    }
}

pub fn builtinRange(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len == 1) {
        if (args[0] != .int) return error.TypeError;
        return Value{ .range = .{ .start = 0, .stop = args[0].int, .step = 1 } };
    } else if (args.len == 2) {
        if (args[0] != .int or args[1] != .int) return error.TypeError;
        return Value{ .range = .{ .start = args[0].int, .stop = args[1].int, .step = 1 } };
    } else if (args.len == 3) {
        if (args[0] != .int or args[1] != .int or args[2] != .int) return error.TypeError;
        if (args[2].int == 0) return error.ValueError;
        return Value{ .range = .{ .start = args[0].int, .stop = args[1].int, .step = args[2].int } };
    }
    return error.TypeError;
}

pub fn builtinType(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len != 1) return error.TypeError;
    const name = args[0].typeName();
    const rep = try std.fmt.allocPrint(allocator, "<class '{s}'>", .{name});
    return Value.makeString(allocator, rep);
}

pub fn builtinInt(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len == 0) return Value.makeInt(0);
    const v = args[0];
    switch (v) {
        .int => |i| return Value.makeInt(i),
        .float => |f| return Value.makeInt(@intFromFloat(f)),
        .bool => |b| return Value.makeInt(if (b) 1 else 0),
        .string => |s| {
            var trimmed = std.mem.trim(u8, s.bytes, " \t\r\n");
            var base: u8 = 10;
            if (args.len > 1 and args[1] == .int) {
                base = @intCast(args[1].int);
            } else if (std.mem.startsWith(u8, trimmed, "0x") or std.mem.startsWith(u8, trimmed, "0X")) {
                trimmed = trimmed[2..];
                base = 16;
            } else if (std.mem.startsWith(u8, trimmed, "0b") or std.mem.startsWith(u8, trimmed, "0B")) {
                trimmed = trimmed[2..];
                base = 2;
            } else if (std.mem.startsWith(u8, trimmed, "0o") or std.mem.startsWith(u8, trimmed, "0O")) {
                trimmed = trimmed[2..];
                base = 8;
            }
            const parsed = try std.fmt.parseInt(i64, trimmed, base);
            return Value.makeInt(parsed);
        },
        else => return error.TypeError,
    }
}

pub fn builtinFloat(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len == 0) return Value.makeFloat(0.0);
    const v = args[0];
    switch (v) {
        .float => |f| return Value.makeFloat(f),
        .int => |i| return Value.makeFloat(@floatFromInt(i)),
        .bool => |b| return Value.makeFloat(if (b) 1.0 else 0.0),
        .string => |s| {
            const parsed = try std.fmt.parseFloat(f64, std.mem.trim(u8, s.bytes, " \t\r\n"));
            return Value.makeFloat(parsed);
        },
        else => return error.TypeError,
    }
}

pub fn builtinStr(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len == 0) return Value.makeString(allocator, "");
    const s = try args[0].str(allocator);
    return Value.makeString(allocator, s);
}

pub fn builtinRepr(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len != 1) return error.TypeError;
    const r = try args[0].repr(allocator);
    return Value.makeString(allocator, r);
}

pub fn builtinBool(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len == 0) return Value.makeBool(false);
    return Value.makeBool(args[0].isTruthy());
}

pub fn builtinList(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    const list = try PyList.init(allocator);
    if (args.len == 0) return Value{ .list = list };
    const src = args[0];
    switch (src) {
        .list => |l| {
            for (l.items.items) |it| try list.items.append(allocator, it);
        },
        .tuple => |t| {
            for (t.items) |it| try list.items.append(allocator, it);
        },
        .string => |s| {
            for (s.bytes) |b| {
                const char_slice = try allocator.alloc(u8, 1);
                char_slice[0] = b;
                const char_val = try Value.makeString(allocator, char_slice);
                try list.items.append(allocator, char_val);
            }
        },
        .range => |r| {
            const len = r.length();
            var i: usize = 0;
            while (i < len) : (i += 1) {
                if (r.get(i)) |val| {
                    try list.items.append(allocator, Value.makeInt(val));
                }
            }
        },
        .generator => |g| {
            while (g.next()) |it| {
                try list.items.append(allocator, it);
            }
        },
        .iterator => |it| {
            while (it.next(allocator)) |item| {
                try list.items.append(allocator, item);
            }
        },
        else => return error.TypeError,
    }
    return Value{ .list = list };
}

pub fn builtinTuple(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len == 0) {
        const tup = try allocator.create(PyTuple);
        tup.* = .{ .items = &[_]Value{} };
        return Value{ .tuple = tup };
    }
    const l = try builtinList(allocator, null, args, &[_]DictEntry{});
    const tup = try allocator.create(PyTuple);
    tup.* = .{ .items = try allocator.dupe(Value, l.list.items.items) };
    return Value{ .tuple = tup };
}

pub fn builtinDict(allocator: Allocator, _: ?*anyopaque, _: []const Value, kwargs: []const DictEntry) anyerror!Value {
    const d = try PyDict.init(allocator);
    for (kwargs) |kw| {
        try d.put(allocator, kw.key, kw.val);
    }
    return Value{ .dict = d };
}

pub fn builtinSet(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    const s = try PySet.init(allocator);
    if (args.len == 0) return Value{ .set = s };
    const src = args[0];
    switch (src) {
        .list => |l| {
            for (l.items.items) |it| try s.add(allocator, it);
        },
        .tuple => |t| {
            for (t.items) |it| try s.add(allocator, it);
        },
        .set => |orig| {
            for (orig.items.items) |it| try s.add(allocator, it);
        },
        .generator => |g| {
            while (g.next()) |it| try s.add(allocator, it);
        },
        .iterator => |it| {
            while (it.next(allocator)) |item| try s.add(allocator, item);
        },
        else => return error.TypeError,
    }
    return Value{ .set = s };
}

pub fn builtinSum(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len < 1) return error.TypeError;
    var acc_int: i64 = 0;
    var acc_float: f64 = 0.0;
    var is_float = false;

    if (args.len > 1) {
        if (args[1] == .float) {
            is_float = true;
            acc_float = args[1].float;
        } else if (args[1] == .int) {
            acc_int = args[1].int;
        }
    }

    const iterable = args[0];
    switch (iterable) {
        .list => |l| {
            for (l.items.items) |it| {
                if (it == .float) {
                    if (!is_float) {
                        is_float = true;
                        acc_float = @as(f64, @floatFromInt(acc_int)) + it.float;
                    } else {
                        acc_float += it.float;
                    }
                } else if (it == .int) {
                    if (is_float) {
                        acc_float += @floatFromInt(it.int);
                    } else {
                        acc_int += it.int;
                    }
                } else {
                    return error.TypeError;
                }
            }
        },
        .tuple => |t| {
            for (t.items) |it| {
                if (it == .float) {
                    if (!is_float) {
                        is_float = true;
                        acc_float = @as(f64, @floatFromInt(acc_int)) + it.float;
                    } else {
                        acc_float += it.float;
                    }
                } else if (it == .int) {
                    if (is_float) {
                        acc_float += @floatFromInt(it.int);
                    } else {
                        acc_int += it.int;
                    }
                } else {
                    return error.TypeError;
                }
            }
        },
        .range => |r| {
            const len = r.length();
            var i: usize = 0;
            while (i < len) : (i += 1) {
                if (r.get(i)) |val| acc_int += val;
            }
        },
        else => return error.TypeError,
    }

    return if (is_float) Value.makeFloat(acc_float) else Value.makeInt(acc_int);
}

pub fn builtinMin(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len == 0) return error.TypeError;
    if (args.len == 1 and args[0] == .list) {
        const items = args[0].list.items.items;
        if (items.len == 0) return error.ValueError;
        var min_val = items[0];
        for (items[1..]) |it| {
            if (it == .int and min_val == .int and it.int < min_val.int) min_val = it;
            if (it == .float and min_val == .float and it.float < min_val.float) min_val = it;
        }
        return min_val;
    }
    var min_val = args[0];
    for (args[1..]) |it| {
        if (it == .int and min_val == .int and it.int < min_val.int) min_val = it;
        if (it == .float and min_val == .float and it.float < min_val.float) min_val = it;
    }
    return min_val;
}

pub fn builtinMax(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len == 0) return error.TypeError;
    if (args.len == 1 and args[0] == .list) {
        const items = args[0].list.items.items;
        if (items.len == 0) return error.ValueError;
        var max_val = items[0];
        for (items[1..]) |it| {
            if (it == .int and max_val == .int and it.int > max_val.int) max_val = it;
            if (it == .float and max_val == .float and it.float > max_val.float) max_val = it;
        }
        return max_val;
    }
    var max_val = args[0];
    for (args[1..]) |it| {
        if (it == .int and max_val == .int and it.int > max_val.int) max_val = it;
        if (it == .float and max_val == .float and it.float > max_val.float) max_val = it;
    }
    return max_val;
}

pub fn builtinAbs(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len != 1) return error.TypeError;
    switch (args[0]) {
        .int => |i| return Value.makeInt(if (i < 0) -i else i),
        .float => |f| return Value.makeFloat(@abs(f)),
        else => return error.TypeError,
    }
}

pub fn builtinRound(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len < 1) return error.TypeError;
    const v = args[0];
    if (v == .int) return v;
    if (v != .float) return error.TypeError;
    if (args.len == 1) {
        return Value.makeInt(@intFromFloat(@round(v.float)));
    }
    const ndigits = if (args[1] == .int) args[1].int else 0;
    const factor = std.math.pow(f64, 10.0, @floatFromInt(ndigits));
    return Value.makeFloat(@round(v.float * factor) / factor);
}

pub fn builtinPow(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len < 2) return error.TypeError;
    const base = args[0];
    const exp = args[1];
    if (base == .int and exp == .int) {
        if (exp.int >= 0) {
            const res = std.math.pow(i64, base.int, exp.int);
            return Value.makeInt(res);
        }
    }
    const b_f = if (base == .float) base.float else @as(f64, @floatFromInt(base.int));
    const e_f = if (exp == .float) exp.float else @as(f64, @floatFromInt(exp.int));
    return Value.makeFloat(std.math.pow(f64, b_f, e_f));
}

pub fn builtinOrd(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len != 1 or args[0] != .string or args[0].string.bytes.len != 1) return error.TypeError;
    return Value.makeInt(args[0].string.bytes[0]);
}

pub fn builtinChr(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len != 1 or args[0] != .int) return error.TypeError;
    const code: u8 = @intCast(args[0].int);
    const slice = try allocator.alloc(u8, 1);
    slice[0] = code;
    return Value.makeString(allocator, slice);
}

pub fn builtinCallable(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len != 1) return error.TypeError;
    return switch (args[0]) {
        .function, .builtin, .class, .bound_method => Value.makeBool(true),
        else => Value.makeBool(false),
    };
}

fn isSubclassOf(sub: *value_mod.PyClass, super: *value_mod.PyClass) bool {
    if (sub == super) return true;
    for (sub.bases) |base| {
        if (isSubclassOf(base, super)) return true;
    }
    return false;
}

pub fn builtinIsInstance(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len != 2) return error.TypeError;
    const inst = args[0];
    const cls = args[1];
    if (cls != .class) return error.TypeError;
    if (inst == .instance) {
        return Value.makeBool(isSubclassOf(inst.instance.class, cls.class));
    }
    return Value.makeBool(false);
}

pub fn builtinEnumerate(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len < 1) return error.TypeError;
    const start: i64 = if (args.len > 1 and args[1] == .int) args[1].int else 0;
    const result = try PyList.init(allocator);

    const src = args[0];
    if (src == .list) {
        for (src.list.items.items, 0..) |it, idx| {
            const pair = try allocator.alloc(Value, 2);
            pair[0] = Value.makeInt(start + @as(i64, @intCast(idx)));
            pair[1] = it;
            const tup = try allocator.create(PyTuple);
            tup.* = .{ .items = pair };
            try result.items.append(allocator, Value{ .tuple = tup });
        }
    } else if (src == .tuple) {
        for (src.tuple.items, 0..) |it, idx| {
            const pair = try allocator.alloc(Value, 2);
            pair[0] = Value.makeInt(start + @as(i64, @intCast(idx)));
            pair[1] = it;
            const tup = try allocator.create(PyTuple);
            tup.* = .{ .items = pair };
            try result.items.append(allocator, Value{ .tuple = tup });
        }
    }
    return Value{ .list = result };
}

pub fn builtinZip(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len == 0) {
        const l = try PyList.init(allocator);
        return Value{ .list = l };
    }
    var min_len: usize = std.math.maxInt(usize);
    for (args) |arg| {
        if (arg == .list) {
            min_len = @min(min_len, arg.list.items.items.len);
        } else if (arg == .tuple) {
            min_len = @min(min_len, arg.tuple.items.len);
        } else {
            return error.TypeError;
        }
    }

    const result = try PyList.init(allocator);
    var i: usize = 0;
    while (i < min_len) : (i += 1) {
        const tuple_items = try allocator.alloc(Value, args.len);
        for (args, 0..) |arg, arg_idx| {
            if (arg == .list) {
                tuple_items[arg_idx] = arg.list.items.items[i];
            } else if (arg == .tuple) {
                tuple_items[arg_idx] = arg.tuple.items[i];
            }
        }
        const tup = try allocator.create(PyTuple);
        tup.* = .{ .items = tuple_items };
        try result.items.append(allocator, Value{ .tuple = tup });
    }

    return Value{ .list = result };
}

pub fn builtinReversed(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len != 1) return error.TypeError;
    const l = try builtinList(allocator, null, args, &[_]DictEntry{});
    std.mem.reverse(Value, l.list.items.items);
    return l;
}

pub fn builtinSorted(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len < 1) return error.TypeError;
    const l = try builtinList(allocator, null, args[0..1], &[_]DictEntry{});
    const items = l.list.items.items;
    // Simple insertion sort for robust value ordering
    var i: usize = 1;
    while (i < items.len) : (i += 1) {
        var j = i;
        while (j > 0) : (j -= 1) {
            const a = items[j - 1];
            const b = items[j];
            if (a == .int and b == .int and a.int > b.int) {
                items[j - 1] = b;
                items[j] = a;
            } else if (a == .float and b == .float and a.float > b.float) {
                items[j - 1] = b;
                items[j] = a;
            } else if (a == .string and b == .string and std.mem.order(u8, a.string.bytes, b.string.bytes) == .gt) {
                items[j - 1] = b;
                items[j] = a;
            } else break;
        }
    }
    return l;
}

pub fn builtinNext(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len < 1 or args.len > 2) return error.TypeError;
    const target = args[0];
    const default_val = if (args.len == 2) args[1] else null;

    switch (target) {
        .iterator => |it| {
            if (it.next(allocator)) |v| return v;
            if (default_val) |d| return d;
            return error.StopIteration;
        },
        .generator => |g| {
            if (g.next()) |v| return v;
            if (default_val) |d| return d;
            return error.StopIteration;
        },
        else => return error.TypeError,
    }
}

pub fn builtinIter(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
    if (args.len != 1) return error.TypeError;
    const v = args[0];
    switch (v) {
        .iterator => return v,
        .generator => |g| {
            const it = try allocator.create(value_mod.PyIterator);
            it.* = .{ .kind = .{ .generator = g } };
            return Value{ .iterator = it };
        },
        .range => |r| {
            const it = try allocator.create(value_mod.PyIterator);
            it.* = .{ .kind = .{ .range = .{ .current = r.start, .stop = r.stop, .step = r.step } } };
            return Value{ .iterator = it };
        },
        .list => |l| {
            const it = try allocator.create(value_mod.PyIterator);
            it.* = .{ .kind = .{ .list = .{ .list = l, .index = 0 } } };
            return Value{ .iterator = it };
        },
        .tuple => |t| {
            const it = try allocator.create(value_mod.PyIterator);
            it.* = .{ .kind = .{ .tuple = .{ .items = t.items, .index = 0 } } };
            return Value{ .iterator = it };
        },
        .set => |s| {
            const it = try allocator.create(value_mod.PyIterator);
            it.* = .{ .kind = .{ .set = .{ .items = s.items.items, .index = 0 } } };
            return Value{ .iterator = it };
        },
        .string => |s| {
            const it = try allocator.create(value_mod.PyIterator);
            it.* = .{ .kind = .{ .string = .{ .str = s.bytes, .index = 0 } } };
            return Value{ .iterator = it };
        },
        else => return error.TypeError,
    }
}

// Module: math
pub fn makeMathModule(allocator: Allocator) !Value {
    const mod = try PyModule.init(allocator, "math");
    try mod.attributes.put("pi", Value.makeFloat(std.math.pi));
    try mod.attributes.put("e", Value.makeFloat(std.math.e));
    try mod.attributes.put("tau", Value.makeFloat(std.math.tau));
    try mod.attributes.put("inf", Value.makeFloat(std.math.inf(f64)));
    try mod.attributes.put("nan", Value.makeFloat(std.math.nan(f64)));

    const math_sqrt = struct {
        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
            if (args.len != 1) return error.TypeError;
            const f = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
            return Value.makeFloat(@sqrt(f));
        }
    }.call;
    const b_sqrt = try allocator.create(PyBuiltin);
    b_sqrt.* = .{ .name = "sqrt", .func = math_sqrt };
    try mod.attributes.put("sqrt", Value{ .builtin = b_sqrt });

    const math_sin = struct {
        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
            if (args.len != 1) return error.TypeError;
            const f = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
            return Value.makeFloat(@sin(f));
        }
    }.call;
    const b_sin = try allocator.create(PyBuiltin);
    b_sin.* = .{ .name = "sin", .func = math_sin };
    try mod.attributes.put("sin", Value{ .builtin = b_sin });

    const math_cos = struct {
        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
            if (args.len != 1) return error.TypeError;
            const f = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
            return Value.makeFloat(@cos(f));
        }
    }.call;
    const b_cos = try allocator.create(PyBuiltin);
    b_cos.* = .{ .name = "cos", .func = math_cos };
    try mod.attributes.put("cos", Value{ .builtin = b_cos });

    const math_floor = struct {
        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
            if (args.len != 1) return error.TypeError;
            const f = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
            return Value.makeInt(@intFromFloat(@floor(f)));
        }
    }.call;
    const b_floor = try allocator.create(PyBuiltin);
    b_floor.* = .{ .name = "floor", .func = math_floor };
    try mod.attributes.put("floor", Value{ .builtin = b_floor });

    const math_ceil = struct {
        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
            if (args.len != 1) return error.TypeError;
            const f = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
            return Value.makeInt(@intFromFloat(@ceil(f)));
        }
    }.call;
    const b_ceil = try allocator.create(PyBuiltin);
    b_ceil.* = .{ .name = "ceil", .func = math_ceil };
    try mod.attributes.put("ceil", Value{ .builtin = b_ceil });

    return Value{ .module = mod };
}

// Module: time
pub fn makeTimeModule(allocator: Allocator) !Value {
    const mod = try PyModule.init(allocator, "time");

    const time_time = struct {
        fn call(_: Allocator, _: ?*anyopaque, _: []const Value, _: []const DictEntry) anyerror!Value {
            var ts: std.posix.system.timespec = undefined;
            _ = std.posix.system.clock_gettime(std.posix.system.CLOCK.REALTIME, &ts);
            const secs: f64 = @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
            return Value.makeFloat(secs);
        }
    }.call;
    const b_time = try allocator.create(PyBuiltin);
    b_time.* = .{ .name = "time", .func = time_time };
    try mod.attributes.put("time", Value{ .builtin = b_time });

    const time_perf = struct {
        fn call(_: Allocator, _: ?*anyopaque, _: []const Value, _: []const DictEntry) anyerror!Value {
            var ts: std.posix.system.timespec = undefined;
            _ = std.posix.system.clock_gettime(std.posix.system.CLOCK.MONOTONIC, &ts);
            const secs: f64 = @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
            return Value.makeFloat(secs);
        }
    }.call;
    const b_perf = try allocator.create(PyBuiltin);
    b_perf.* = .{ .name = "perf_counter", .func = time_perf };
    try mod.attributes.put("perf_counter", Value{ .builtin = b_perf });

    const time_sleep = struct {
        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
            if (args.len != 1) return error.TypeError;
            const secs = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
            const total_ns: u64 = @intFromFloat(secs * 1e9);
            var req = std.posix.system.timespec{
                .sec = @intCast(total_ns / 1_000_000_000),
                .nsec = @intCast(total_ns % 1_000_000_000),
            };
            var rem: std.posix.system.timespec = undefined;
            _ = std.posix.system.nanosleep(&req, &rem);
            return .none;
        }
    }.call;
    const b_sleep = try allocator.create(PyBuiltin);
    b_sleep.* = .{ .name = "sleep", .func = time_sleep };
    try mod.attributes.put("sleep", Value{ .builtin = b_sleep });

    return Value{ .module = mod };
}

pub fn builtinExit(_: Allocator, _: ?*anyopaque, exit_args: []const Value, _: []const DictEntry) anyerror!Value {
    const code: u8 = if (exit_args.len > 0 and exit_args[0] == .int) @intCast(exit_args[0].int) else 0;
    std.process.exit(code);
}

// Module: sys
pub fn makeSysModule(allocator: Allocator, args: []const [:0]const u8) !Value {
    const mod = try PyModule.init(allocator, "sys");
    try mod.attributes.put("version", try Value.makeString(allocator, "3.15.0 (Zython Zig runtime)"));
    try mod.attributes.put("platform", try Value.makeString(allocator, "linux"));

    const py_argv = try PyList.init(allocator);
    for (args) |arg| {
        const py_arg = try Value.makeString(allocator, arg);
        try py_argv.items.append(allocator, py_arg);
    }
    try mod.attributes.put("argv", Value{ .list = py_argv });

    const b_exit = try allocator.create(PyBuiltin);
    b_exit.* = .{ .name = "exit", .func = builtinExit };
    try mod.attributes.put("exit", Value{ .builtin = b_exit });

    return Value{ .module = mod };
}

// Module: asyncio
pub fn makeAsyncioModule(allocator: Allocator) !Value {
    const mod = try PyModule.init(allocator, "asyncio");

    const asyncio_run = struct {
        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
            if (args.len != 1) return error.TypeError;
            if (args[0] == .coroutine) {
                return args[0].coroutine.result;
            }
            return args[0];
        }
    }.call;
    const b_run = try allocator.create(PyBuiltin);
    b_run.* = .{ .name = "run", .func = asyncio_run };
    try mod.attributes.put("run", Value{ .builtin = b_run });

    const asyncio_sleep = struct {
        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
            if (args.len != 1) return error.TypeError;
            const secs = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
            const total_ns: u64 = @intFromFloat(secs * 1e9);
            var req = std.posix.system.timespec{
                .sec = @intCast(total_ns / 1_000_000_000),
                .nsec = @intCast(total_ns % 1_000_000_000),
            };
            var rem: std.posix.system.timespec = undefined;
            _ = std.posix.system.nanosleep(&req, &rem);
            return .none;
        }
    }.call;
    const b_sleep = try allocator.create(PyBuiltin);
    b_sleep.* = .{ .name = "sleep", .func = asyncio_sleep };
    try mod.attributes.put("sleep", Value{ .builtin = b_sleep });

    return Value{ .module = mod };
}

// Module: threading
pub fn makeThreadingModule(allocator: Allocator) !Value {
    const mod = try PyModule.init(allocator, "threading");

    const thread_ctor = struct {
        fn call(a: Allocator, _: ?*anyopaque, args: []const Value, kwargs: []const DictEntry) anyerror!Value {
            var target: Value = .none;
            var thread_args: []const Value = &.{};
            var name: []const u8 = "Thread";
            var daemon: bool = false;

            for (kwargs) |kw| {
                if (kw.key == .string) {
                    if (std.mem.eql(u8, kw.key.string.bytes, "target")) {
                        target = kw.val;
                    } else if (std.mem.eql(u8, kw.key.string.bytes, "args")) {
                        if (kw.val == .tuple) {
                            thread_args = kw.val.tuple.items;
                        } else if (kw.val == .list) {
                            thread_args = kw.val.list.items.items;
                        }
                    } else if (std.mem.eql(u8, kw.key.string.bytes, "name") and kw.val == .string) {
                        name = kw.val.string.bytes;
                    } else if (std.mem.eql(u8, kw.key.string.bytes, "daemon") and kw.val == .bool) {
                        daemon = kw.val.bool;
                    }
                }
            }

            if (target == .none and args.len > 0) {
                target = args[0];
            }
            if (thread_args.len == 0 and args.len > 1) {
                if (args[1] == .tuple) {
                    thread_args = args[1].tuple.items;
                } else if (args[1] == .list) {
                    thread_args = args[1].list.items.items;
                }
            }

            var th = try value_mod.PyThread.init(a, name, 1, target, thread_args);
            th.daemon = daemon;
            return Value{ .thread = th };
        }
    }.call;
    const b_thread = try allocator.create(PyBuiltin);
    b_thread.* = .{ .name = "Thread", .func = thread_ctor };
    try mod.attributes.put("Thread", Value{ .builtin = b_thread });

    const lock_ctor = struct {
        fn call(a: Allocator, _: ?*anyopaque, _: []const Value, _: []const DictEntry) anyerror!Value {
            const l = try value_mod.PyLock.init(a, false);
            return Value{ .lock = l };
        }
    }.call;
    const b_lock = try allocator.create(PyBuiltin);
    b_lock.* = .{ .name = "Lock", .func = lock_ctor };
    try mod.attributes.put("Lock", Value{ .builtin = b_lock });

    const rlock_ctor = struct {
        fn call(a: Allocator, _: ?*anyopaque, _: []const Value, _: []const DictEntry) anyerror!Value {
            const l = try value_mod.PyLock.init(a, true);
            return Value{ .lock = l };
        }
    }.call;
    const b_rlock = try allocator.create(PyBuiltin);
    b_rlock.* = .{ .name = "RLock", .func = rlock_ctor };
    try mod.attributes.put("RLock", Value{ .builtin = b_rlock });

    const sem_ctor = struct {
        fn call(a: Allocator, _: ?*anyopaque, args: []const Value, kwargs: []const DictEntry) anyerror!Value {
            var val: i64 = 1;
            if (args.len > 0 and args[0] == .int) {
                val = args[0].int;
            }
            for (kwargs) |kw| {
                if (kw.key == .string and std.mem.eql(u8, kw.key.string.bytes, "value") and kw.val == .int) {
                    val = kw.val.int;
                }
            }
            const s = try value_mod.PySemaphore.init(a, val);
            return Value{ .semaphore = s };
        }
    }.call;
    const b_sem = try allocator.create(PyBuiltin);
    b_sem.* = .{ .name = "Semaphore", .func = sem_ctor };
    try mod.attributes.put("Semaphore", Value{ .builtin = b_sem });

    const event_ctor = struct {
        fn call(a: Allocator, _: ?*anyopaque, _: []const Value, _: []const DictEntry) anyerror!Value {
            const ev = try value_mod.PyEvent.init(a);
            return Value{ .event = ev };
        }
    }.call;
    const b_event = try allocator.create(PyBuiltin);
    b_event.* = .{ .name = "Event", .func = event_ctor };
    try mod.attributes.put("Event", Value{ .builtin = b_event });

    const cur_thread = struct {
        fn call(a: Allocator, _: ?*anyopaque, _: []const Value, _: []const DictEntry) anyerror!Value {
            const main_th = try value_mod.PyThread.init(a, "MainThread", 0, .none, &.{});
            main_th.is_alive = true;
            return Value{ .thread = main_th };
        }
    }.call;
    const b_cur = try allocator.create(PyBuiltin);
    b_cur.* = .{ .name = "current_thread", .func = cur_thread };
    try mod.attributes.put("current_thread", Value{ .builtin = b_cur });

    const active_cnt = struct {
        fn call(_: Allocator, _: ?*anyopaque, _: []const Value, _: []const DictEntry) anyerror!Value {
            return Value.makeInt(1);
        }
    }.call;
    const b_cnt = try allocator.create(PyBuiltin);
    b_cnt.* = .{ .name = "active_count", .func = active_cnt };
    try mod.attributes.put("active_count", Value{ .builtin = b_cnt });

    const get_ident_fn = struct {
        fn call(_: Allocator, _: ?*anyopaque, _: []const Value, _: []const DictEntry) anyerror!Value {
            return Value.makeInt(@intCast(std.Thread.getCurrentId()));
        }
    }.call;
    const b_ident = try allocator.create(PyBuiltin);
    b_ident.* = .{ .name = "get_ident", .func = get_ident_fn };
    try mod.attributes.put("get_ident", Value{ .builtin = b_ident });

    return Value{ .module = mod };
}

// Module: concurrent.futures
pub fn makeConcurrentFuturesModule(allocator: Allocator) !Value {
    const mod = try PyModule.init(allocator, "concurrent.futures");

    const pool_ctor = struct {
        fn call(a: Allocator, _: ?*anyopaque, args: []const Value, kwargs: []const DictEntry) anyerror!Value {
            var max_w: usize = 4;
            if (args.len > 0 and args[0] == .int) {
                max_w = @intCast(@max(1, args[0].int));
            }
            for (kwargs) |kw| {
                if (kw.key == .string and std.mem.eql(u8, kw.key.string.bytes, "max_workers")) {
                    if (kw.val == .int) {
                        max_w = @intCast(@max(1, kw.val.int));
                    }
                }
            }
            const p = try value_mod.PyThreadPool.init(a, max_w);
            return Value{ .thread_pool = p };
        }
    }.call;

    const b_pool = try allocator.create(PyBuiltin);
    b_pool.* = .{ .name = "ThreadPoolExecutor", .func = pool_ctor };
    try mod.attributes.put("ThreadPoolExecutor", Value{ .builtin = b_pool });

    const as_completed_fn = struct {
        fn call(a: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
            if (args.len < 1) return error.TypeError;
            var fut_list: std.ArrayList(Value) = .empty;
            switch (args[0]) {
                .list => |l| try fut_list.appendSlice(a, l.items.items),
                .tuple => |t| try fut_list.appendSlice(a, t.items),
                else => return error.TypeError,
            }
            const res = try value_mod.PyList.init(a);
            for (fut_list.items) |item| {
                if (item == .future) {
                    _ = item.future.event.wait();
                    try res.items.append(a, item);
                }
            }
            return Value{ .list = res };
        }
    }.call;
    const b_ac = try allocator.create(PyBuiltin);
    b_ac.* = .{ .name = "as_completed", .func = as_completed_fn };
    try mod.attributes.put("as_completed", Value{ .builtin = b_ac });

    const fut_ctor = struct {
        fn call(a: Allocator, _: ?*anyopaque, _: []const Value, _: []const DictEntry) anyerror!Value {
            const f = try value_mod.PyFuture.init(a);
            return Value{ .future = f };
        }
    }.call;
    const b_fut = try allocator.create(PyBuiltin);
    b_fut.* = .{ .name = "Future", .func = fut_ctor };
    try mod.attributes.put("Future", Value{ .builtin = b_fut });

    return Value{ .module = mod };
}

pub fn populateBuiltins(allocator: Allocator, env: *Environment) !void {
    const defs = [_]struct { name: []const u8, func: value_mod.BuiltinFn }{
        .{ .name = "print", .func = builtinPrint },
        .{ .name = "len", .func = builtinLen },
        .{ .name = "range", .func = builtinRange },
        .{ .name = "type", .func = builtinType },
        .{ .name = "int", .func = builtinInt },
        .{ .name = "float", .func = builtinFloat },
        .{ .name = "str", .func = builtinStr },
        .{ .name = "repr", .func = builtinRepr },
        .{ .name = "bool", .func = builtinBool },
        .{ .name = "list", .func = builtinList },
        .{ .name = "tuple", .func = builtinTuple },
        .{ .name = "dict", .func = builtinDict },
        .{ .name = "set", .func = builtinSet },
        .{ .name = "sum", .func = builtinSum },
        .{ .name = "min", .func = builtinMin },
        .{ .name = "max", .func = builtinMax },
        .{ .name = "abs", .func = builtinAbs },
        .{ .name = "round", .func = builtinRound },
        .{ .name = "pow", .func = builtinPow },
        .{ .name = "ord", .func = builtinOrd },
        .{ .name = "chr", .func = builtinChr },
        .{ .name = "callable", .func = builtinCallable },
        .{ .name = "isinstance", .func = builtinIsInstance },
        .{ .name = "enumerate", .func = builtinEnumerate },
        .{ .name = "zip", .func = builtinZip },
        .{ .name = "reversed", .func = builtinReversed },
        .{ .name = "sorted", .func = builtinSorted },
        .{ .name = "next", .func = builtinNext },
        .{ .name = "iter", .func = builtinIter },
        .{ .name = "exit", .func = builtinExit },
        .{ .name = "quit", .func = builtinExit },
    };

    for (defs) |d| {
        const b = try allocator.create(PyBuiltin);
        b.* = .{ .name = d.name, .func = d.func };
        try env.set(d.name, Value{ .builtin = b });
    }
}
