const std = @import("std");
const Allocator = std.mem.Allocator;

pub const PyRange = struct {
    start: i64,
    stop: i64,
    step: i64,

    pub fn length(self: PyRange) usize {
        if (self.step > 0 and self.start < self.stop) {
            return @intCast(@divFloor((self.stop - 1 - self.start), self.step) + 1);
        } else if (self.step < 0 and self.start > self.stop) {
            return @intCast(@divFloor((self.start - 1 - self.stop), -self.step) + 1);
        }
        return 0;
    }

    pub fn get(self: PyRange, idx: usize) ?i64 {
        if (idx >= self.length()) return null;
        return self.start + @as(i64, @intCast(idx)) * self.step;
    }
};

pub const DictEntry = struct {
    key: Value,
    val: Value,
};

pub const FieldSlot = struct {
    name: []const u8,
    val: Value,
};

pub const PyString = struct {
    bytes: []const u8,

    pub fn init(allocator: Allocator, s: []const u8) !*PyString {
        const self = try allocator.create(PyString);
        self.* = .{ .bytes = s };
        return self;
    }

    pub fn concat(allocator: Allocator, a: []const u8, b: []const u8) !*PyString {
        const out = try allocator.alloc(u8, a.len + b.len);
        @memcpy(out[0..a.len], a);
        @memcpy(out[a.len..], b);
        return init(allocator, out);
    }
};

pub const PyList = struct {
    items: std.ArrayList(Value),

    pub fn init(allocator: Allocator) !*PyList {
        const self = try allocator.create(PyList);
        self.* = .{ .items = .empty };
        return self;
    }

    pub inline fn append(self: *PyList, allocator: Allocator, val: Value) !void {
        try self.items.append(allocator, val);
    }
};

pub const PyTuple = struct {
    items: []Value,
};

pub const PyDict = struct {
    entries: std.ArrayList(DictEntry),
    string_map: std.StringHashMap(usize),

    pub fn init(allocator: Allocator) !*PyDict {
        const self = try allocator.create(PyDict);
        self.* = .{
            .entries = .empty,
            .string_map = std.StringHashMap(usize).init(allocator),
        };
        return self;
    }

    pub fn get(self: *PyDict, key: Value) ?Value {
        if (key == .string) {
            if (self.string_map.get(key.string.bytes)) |idx| {
                if (idx < self.entries.items.len) {
                    return self.entries.items[idx].val;
                }
            }
            return null;
        }
        for (self.entries.items) |entry| {
            if (entry.key.equals(key)) {
                return entry.val;
            }
        }
        return null;
    }

    pub fn put(self: *PyDict, allocator: Allocator, key: Value, val: Value) !void {
        if (key == .string) {
            if (self.string_map.get(key.string.bytes)) |idx| {
                if (idx < self.entries.items.len) {
                    self.entries.items[idx].val = val;
                    return;
                }
            }
            const idx = self.entries.items.len;
            try self.entries.append(allocator, .{ .key = key, .val = val });
            try self.string_map.put(key.string.bytes, idx);
            return;
        }

        for (self.entries.items) |*entry| {
            if (entry.key.equals(key)) {
                entry.val = val;
                return;
            }
        }
        try self.entries.append(allocator, .{ .key = key, .val = val });
    }

    pub fn remove(self: *PyDict, key: Value) ?Value {
        if (key == .string) {
            _ = self.string_map.remove(key.string.bytes);
        }
        for (self.entries.items, 0..) |entry, i| {
            if (entry.key.equals(key)) {
                const val = entry.val;
                _ = self.entries.swapRemove(i);
                return val;
            }
        }
        return null;
    }
};

pub const PySet = struct {
    items: std.ArrayList(Value),

    pub fn init(allocator: Allocator) !*PySet {
        const self = try allocator.create(PySet);
        self.* = .{ .items = .empty };
        return self;
    }

    pub fn contains(self: *PySet, val: Value) bool {
        for (self.items.items) |item| {
            if (item.equals(val)) return true;
        }
        return false;
    }

    pub fn add(self: *PySet, allocator: Allocator, val: Value) !void {
        if (!self.contains(val)) {
            try self.items.append(allocator, val);
        }
    }

    pub fn remove(self: *PySet, val: Value) bool {
        for (self.items.items, 0..) |item, i| {
            if (item.equals(val)) {
                _ = self.items.swapRemove(i);
                return true;
            }
        }
        return false;
    }

    pub fn clear(self: *PySet) void {
        self.items.clearRetainingCapacity();
    }
};

pub const BuiltinFn = *const fn (allocator: Allocator, env_opaque: ?*anyopaque, args: []const Value, kwargs: []const DictEntry) anyerror!Value;

pub const PyBuiltin = struct {
    name: []const u8,
    func: BuiltinFn,
};

pub const PyFunction = struct {
    name: []const u8,
    param_names: [][]const u8,
    defaults: []Value,
    vararg: ?[]const u8,
    kwarg: ?[]const u8,
    body_opaque: *const anyopaque,
    body_len: usize,
    closure_env: ?*anyopaque,
    chunk: ?*anyopaque = null,
    jit_entry: ?*const anyopaque = null,
    jit_kind: u8 = 0,
    call_count: u32 = 0,
};

pub const PyIterator = struct {
    kind: union(enum) {
        range: struct { current: i64, stop: i64, step: i64 },
        list: struct { list: *PyList, index: usize },
        tuple: struct { items: []Value, index: usize },
        set: struct { items: []Value, index: usize },
        string: struct { str: []const u8, index: usize },
    },

    pub fn next(self: *PyIterator, allocator: Allocator) ?Value {
        switch (self.kind) {
            .range => |*r| {
                if (r.step > 0) {
                    if (r.current < r.stop) {
                        const val = r.current;
                        r.current += r.step;
                        return Value.makeInt(val);
                    }
                } else if (r.step < 0) {
                    if (r.current > r.stop) {
                        const val = r.current;
                        r.current += r.step;
                        return Value.makeInt(val);
                    }
                }
                return null;
            },
            .list => |*l| {
                if (l.index < l.list.items.items.len) {
                    const it = l.list.items.items[l.index];
                    l.index += 1;
                    return it;
                }
                return null;
            },
            .tuple => |*t| {
                if (t.index < t.items.len) {
                    const it = t.items[t.index];
                    t.index += 1;
                    return it;
                }
                return null;
            },
            .set => |*s| {
                if (s.index < s.items.len) {
                    const it = s.items[s.index];
                    s.index += 1;
                    return it;
                }
                return null;
            },
            .string => |*st| {
                if (st.index < st.str.len) {
                    const char_str = st.str[st.index .. st.index + 1];
                    st.index += 1;
                    const py_s = PyString.init(allocator, char_str) catch return null;
                    return Value{ .string = py_s };
                }
                return null;
            },
        }
    }
};

pub const PyClass = struct {
    name: []const u8,
    bases: []*PyClass,
    attributes: std.StringHashMap(Value),

    pub fn init(allocator: Allocator, name: []const u8, bases: []*PyClass) !*PyClass {
        const self = try allocator.create(PyClass);
        self.* = .{
            .name = name,
            .bases = bases,
            .attributes = std.StringHashMap(Value).init(allocator),
        };
        return self;
    }

    pub fn lookup(self: *PyClass, name: []const u8) ?Value {
        if (self.attributes.get(name)) |v| return v;
        for (self.bases) |base| {
            if (base.lookup(name)) |v| return v;
        }
        return null;
    }
};

pub const PyInstance = struct {
    class: *PyClass,
    inline_slots: [16]FieldSlot = undefined,
    inline_count: u8 = 0,
    attributes: ?std.StringHashMap(Value) = null,

    pub fn init(allocator: Allocator, class: *PyClass) !*PyInstance {
        const self = try allocator.create(PyInstance);
        self.* = .{
            .class = class,
            .inline_count = 0,
            .attributes = null,
        };
        return self;
    }

    pub fn setAttr(self: *PyInstance, allocator: Allocator, name: []const u8, val: Value) !void {
        var i: u8 = 0;
        while (i < self.inline_count) : (i += 1) {
            if (self.inline_slots[i].name.ptr == name.ptr or std.mem.eql(u8, self.inline_slots[i].name, name)) {
                self.inline_slots[i].val = val;
                return;
            }
        }
        if (self.inline_count < 16) {
            self.inline_slots[self.inline_count] = .{ .name = name, .val = val };
            self.inline_count += 1;
            return;
        }
        if (self.attributes == null) {
            self.attributes = std.StringHashMap(Value).init(allocator);
        }
        try self.attributes.?.put(name, val);
    }

    pub fn getAttr(self: *PyInstance, allocator: Allocator, name: []const u8) ?Value {
        var i: u8 = 0;
        while (i < self.inline_count) : (i += 1) {
            if (self.inline_slots[i].name.ptr == name.ptr or std.mem.eql(u8, self.inline_slots[i].name, name)) {
                return self.inline_slots[i].val;
            }
        }
        if (self.attributes) |*attrs| {
            if (attrs.get(name)) |v| return v;
        }
        if (self.class.lookup(name)) |v| {
            if (v == .function or v == .builtin) {
                const bm = allocator.create(PyBoundMethod) catch return v;
                bm.* = .{
                    .instance = .{ .instance = self },
                    .function = v,
                };
                return .{ .bound_method = bm };
            }
            return v;
        }
        return null;
    }
};

pub const PyBoundMethod = struct {
    instance: Value,
    function: Value,
};

pub const PyModule = struct {
    name: []const u8,
    attributes: std.StringHashMap(Value),

    pub fn init(allocator: Allocator, name: []const u8) !*PyModule {
        const self = try allocator.create(PyModule);
        self.* = .{
            .name = name,
            .attributes = std.StringHashMap(Value).init(allocator),
        };
        return self;
    }
};

pub const Value = union(enum) {
    none,
    bool: bool,
    int: i64,
    float: f64,
    string: *PyString,
    list: *PyList,
    tuple: *PyTuple,
    dict: *PyDict,
    set: *PySet,
    range: PyRange,
    function: *PyFunction,
    builtin: *PyBuiltin,
    class: *PyClass,
    instance: *PyInstance,
    bound_method: *PyBoundMethod,
    module: *PyModule,
    iterator: *PyIterator,
    return_flow,
    break_flow,
    continue_flow,

    pub fn makeInt(n: i64) Value {
        return .{ .int = n };
    }

    pub fn makeFloat(f: f64) Value {
        return .{ .float = f };
    }

    pub fn makeBool(b: bool) Value {
        return .{ .bool = b };
    }

    pub fn makeNone() Value {
        return .none;
    }

    pub fn makeString(allocator: Allocator, s: []const u8) !Value {
        const py_str = try allocator.create(PyString);
        py_str.* = .{ .bytes = s };
        return .{ .string = py_str };
    }

    pub fn isTruthy(self: Value) bool {
        return switch (self) {
            .none => false,
            .bool => |b| b,
            .int => |i| i != 0,
            .float => |f| f != 0.0,
            .string => |s| s.bytes.len > 0,
            .list => |l| l.items.items.len > 0,
            .tuple => |t| t.items.len > 0,
            .dict => |d| d.entries.items.len > 0,
            .set => |s| s.items.items.len > 0,
            .range => |r| r.length() > 0,
            .function, .builtin, .class, .instance, .bound_method, .module, .iterator => true,
            .return_flow, .break_flow, .continue_flow => false,
        };
    }

    pub fn typeName(self: Value) []const u8 {
        return switch (self) {
            .none => "NoneType",
            .bool => "bool",
            .int => "int",
            .float => "float",
            .string => "str",
            .list => "list",
            .tuple => "tuple",
            .dict => "dict",
            .set => "set",
            .range => "range",
            .function => "function",
            .builtin => "builtin_function_or_method",
            .class => "type",
            .instance => |ins| ins.class.name,
            .bound_method => "method",
            .module => "module",
            .iterator => "iterator",
            .return_flow => "return",
            .break_flow => "break",
            .continue_flow => "continue",
        };
    }

    pub fn equals(self: Value, other: Value) bool {
        switch (self) {
            .none => return other == .none,
            .bool => |b| {
                if (other == .bool) return b == other.bool;
                if (other == .int) return (if (b) @as(i64, 1) else @as(i64, 0)) == other.int;
                return false;
            },
            .int => |i| {
                if (other == .int) return i == other.int;
                if (other == .float) return @as(f64, @floatFromInt(i)) == other.float;
                if (other == .bool) return i == (if (other.bool) @as(i64, 1) else @as(i64, 0));
                return false;
            },
            .float => |f| {
                if (other == .float) return f == other.float;
                if (other == .int) return f == @as(f64, @floatFromInt(other.int));
                return false;
            },
            .string => |s| {
                if (other != .string) return false;
                return std.mem.eql(u8, s.bytes, other.string.bytes);
            },
            .list => |l| {
                if (other != .list) return false;
                if (l.items.items.len != other.list.items.items.len) return false;
                for (l.items.items, 0..) |it, idx| {
                    if (!it.equals(other.list.items.items[idx])) return false;
                }
                return true;
            },
            .tuple => |t| {
                if (other != .tuple) return false;
                if (t.items.len != other.tuple.items.len) return false;
                for (t.items, 0..) |it, idx| {
                    if (!it.equals(other.tuple.items[idx])) return false;
                }
                return true;
            },
            .dict => |d| {
                if (other != .dict) return false;
                if (d.entries.items.len != other.dict.entries.items.len) return false;
                for (d.entries.items) |e| {
                    const other_val = other.dict.get(e.key) orelse return false;
                    if (!e.val.equals(other_val)) return false;
                }
                return true;
            },
            .range => |r| {
                if (other != .range) return false;
                return r.start == other.range.start and r.stop == other.range.stop and r.step == other.range.step;
            },
            .instance => |ins| {
                if (other != .instance) return false;
                return ins == other.instance;
            },
            .function => |f| {
                if (other != .function) return false;
                return f == other.function;
            },
            .class => |c| {
                if (other != .class) return false;
                return c == other.class;
            },
            .builtin => |b| {
                if (other != .builtin) return false;
                return b == other.builtin;
            },
            .iterator => |it| {
                if (other != .iterator) return false;
                return it == other.iterator;
            },
            else => return false,
        }
    }

    pub fn str(self: Value, allocator: Allocator) Allocator.Error![]const u8 {
        switch (self) {
            .none => return "None",
            .bool => |b| return if (b) "True" else "False",
            .int => |i| return std.fmt.allocPrint(allocator, "{d}", .{i}),
            .float => |f| {
                if (f == @floor(f) and !std.math.isNan(f) and !std.math.isInf(f)) {
                    return std.fmt.allocPrint(allocator, "{d:.1}", .{f});
                }
                return std.fmt.allocPrint(allocator, "{d}", .{f});
            },
            .string => |s| return s.bytes,
            .list => |l| {
                var buf: std.ArrayList(u8) = .empty;
                try buf.append(allocator, '[');
                for (l.items.items, 0..) |item, i| {
                    if (i > 0) try buf.appendSlice(allocator, ", ");
                    const rep = try item.repr(allocator);
                    try buf.appendSlice(allocator, rep);
                }
                try buf.append(allocator, ']');
                return buf.items;
            },
            .tuple => |t| {
                var buf: std.ArrayList(u8) = .empty;
                try buf.append(allocator, '(');
                for (t.items, 0..) |item, i| {
                    if (i > 0) try buf.appendSlice(allocator, ", ");
                    const rep = try item.repr(allocator);
                    try buf.appendSlice(allocator, rep);
                }
                if (t.items.len == 1) try buf.append(allocator, ',');
                try buf.append(allocator, ')');
                return buf.items;
            },
            .dict => |d| {
                var buf: std.ArrayList(u8) = .empty;
                try buf.append(allocator, '{');
                for (d.entries.items, 0..) |entry, i| {
                    if (i > 0) try buf.appendSlice(allocator, ", ");
                    const k_rep = try entry.key.repr(allocator);
                    const v_rep = try entry.val.repr(allocator);
                    try buf.appendSlice(allocator, k_rep);
                    try buf.appendSlice(allocator, ": ");
                    try buf.appendSlice(allocator, v_rep);
                }
                try buf.append(allocator, '}');
                return buf.items;
            },
            .set => |s| {
                if (s.items.items.len == 0) return "set()";
                var buf: std.ArrayList(u8) = .empty;
                try buf.append(allocator, '{');
                for (s.items.items, 0..) |item, i| {
                    if (i > 0) try buf.appendSlice(allocator, ", ");
                    const rep = try item.repr(allocator);
                    try buf.appendSlice(allocator, rep);
                }
                try buf.append(allocator, '}');
                return buf.items;
            },
            .range => |r| {
                if (r.step == 1) {
                    if (r.start == 0) return std.fmt.allocPrint(allocator, "range({d})", .{r.stop});
                    return std.fmt.allocPrint(allocator, "range({d}, {d})", .{ r.start, r.stop });
                }
                return std.fmt.allocPrint(allocator, "range({d}, {d}, {d})", .{ r.start, r.stop, r.step });
            },
            .function => |f| return std.fmt.allocPrint(allocator, "<function {s}>", .{f.name}),
            .builtin => |b| return std.fmt.allocPrint(allocator, "<built-in function {s}>", .{b.name}),
            .class => |c| return std.fmt.allocPrint(allocator, "<class '{s}'>", .{c.name}),
            .instance => |ins| return std.fmt.allocPrint(allocator, "<{s} object>", .{ins.class.name}),
            .bound_method => return "<bound method>",
            .module => |m| return std.fmt.allocPrint(allocator, "<module '{s}'>", .{m.name}),
            .iterator => return "<iterator object>",
            .return_flow => return "return",
            .break_flow => return "break",
            .continue_flow => return "continue",
        }
    }

    pub fn repr(self: Value, allocator: Allocator) Allocator.Error![]const u8 {
        if (self == .string) {
            return std.fmt.allocPrint(allocator, "'{s}'", .{self.string.bytes});
        }
        return self.str(allocator);
    }
};
