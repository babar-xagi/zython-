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
    extra: ?*anyopaque = null,
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
    is_generator: bool = false,
    is_async: bool = false,
};

pub const PyGenerator = struct {
    name: []const u8,
    items: std.ArrayList(Value),
    index: usize = 0,

    pub fn init(allocator: Allocator, name: []const u8) !*PyGenerator {
        const self = try allocator.create(PyGenerator);
        self.* = .{
            .name = name,
            .items = .empty,
            .index = 0,
        };
        return self;
    }

    pub fn next(self: *PyGenerator) ?Value {
        if (self.index < self.items.items.len) {
            const val = self.items.items[self.index];
            self.index += 1;
            return val;
        }
        return null;
    }
};

pub const PyCoroutine = struct {
    name: []const u8,
    result: Value,

    pub fn init(allocator: Allocator, name: []const u8, result: Value) !*PyCoroutine {
        const self = try allocator.create(PyCoroutine);
        self.* = .{
            .name = name,
            .result = result,
        };
        return self;
    }
};

pub const AtomicMutex = struct {
    state: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn lock(self: *AtomicMutex) void {
        while (self.state.cmpxchgWeak(false, true, .acquire, .monotonic) != null) {
            std.Thread.yield() catch {};
        }
    }

    pub fn unlock(self: *AtomicMutex) void {
        self.state.store(false, .release);
    }
};

pub const AtomicEvent = struct {
    state: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn set(self: *AtomicEvent) void {
        self.state.store(true, .release);
    }

    pub fn wait(self: *AtomicEvent) void {
        while (!self.state.load(.acquire)) {
            std.Thread.yield() catch {};
        }
    }

    pub fn isSet(self: *AtomicEvent) bool {
        return self.state.load(.acquire);
    }
};

pub const PyThread = struct {
    name: []const u8,
    ident: i64,
    target: Value,
    args: []const Value,
    thread_handle: ?std.Thread = null,
    is_alive: bool = false,
    has_joined: bool = false,
    daemon: bool = false,
    result: Value = .none,
    err: ?anyerror = null,
    mutex: AtomicMutex = .{},

    pub fn init(allocator: Allocator, name: []const u8, ident: i64, target: Value, args: []const Value) !*PyThread {
        const self = try allocator.create(PyThread);
        const persistent_args = try allocator.dupe(Value, args);
        self.* = .{
            .name = name,
            .ident = ident,
            .target = target,
            .args = persistent_args,
            .thread_handle = null,
            .is_alive = false,
            .has_joined = false,
            .daemon = false,
            .result = .none,
            .err = null,
            .mutex = .{},
        };
        return self;
    }
};

pub const PyLock = struct {
    mutex: AtomicMutex = .{},
    is_locked: bool = false,
    is_rlock: bool = false,
    acquire_count: u32 = 0,
    owner: ?std.Thread.Id = null,

    pub fn init(allocator: Allocator, is_rlock: bool) !*PyLock {
        const self = try allocator.create(PyLock);
        self.* = .{
            .mutex = .{},
            .is_locked = false,
            .is_rlock = is_rlock,
            .acquire_count = 0,
            .owner = null,
        };
        return self;
    }

    pub fn acquire(self: *PyLock) void {
        const tid = std.Thread.getCurrentId();
        if (self.is_rlock) {
            if (self.owner != null and self.owner.? == tid) {
                self.acquire_count += 1;
                return;
            }
        }
        self.mutex.lock();
        self.owner = tid;
        self.is_locked = true;
        self.acquire_count = 1;
    }

    pub fn release(self: *PyLock) void {
        if (self.acquire_count > 0) {
            self.acquire_count -= 1;
            if (self.acquire_count == 0) {
                self.owner = null;
                self.is_locked = false;
                self.mutex.unlock();
            }
        }
    }
};

pub const PySemaphore = struct {
    value: std.atomic.Value(i64),
    mutex: AtomicMutex = .{},

    pub fn init(allocator: Allocator, initial_val: i64) !*PySemaphore {
        const self = try allocator.create(PySemaphore);
        self.* = .{
            .value = std.atomic.Value(i64).init(initial_val),
            .mutex = .{},
        };
        return self;
    }

    pub fn acquire(self: *PySemaphore) void {
        while (true) {
            self.mutex.lock();
            const cur = self.value.load(.acquire);
            if (cur > 0) {
                self.value.store(cur - 1, .release);
                self.mutex.unlock();
                return;
            }
            self.mutex.unlock();
            std.Thread.yield() catch {};
        }
    }

    pub fn release(self: *PySemaphore) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        _ = self.value.fetchAdd(1, .release);
    }
};

pub const PyEvent = struct {
    state: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    pub fn init(allocator: Allocator) !*PyEvent {
        const self = try allocator.create(PyEvent);
        self.* = .{
            .state = std.atomic.Value(bool).init(false),
        };
        return self;
    }

    pub fn set(self: *PyEvent) void {
        self.state.store(true, .release);
    }

    pub fn clear(self: *PyEvent) void {
        self.state.store(false, .release);
    }

    pub fn isSet(self: *PyEvent) bool {
        return self.state.load(.acquire);
    }

    pub fn wait(self: *PyEvent) bool {
        while (!self.state.load(.acquire)) {
            std.Thread.yield() catch {};
        }
        return true;
    }
};

pub const PyFuture = struct {
    event: AtomicEvent = .{},
    result_val: Value = .none,
    err: ?anyerror = null,

    pub fn init(allocator: Allocator) !*PyFuture {
        const self = try allocator.create(PyFuture);
        self.* = .{
            .event = .{},
            .result_val = .none,
            .err = null,
        };
        return self;
    }

    pub fn setResult(self: *PyFuture, val: Value) void {
        self.result_val = val;
        self.event.set();
    }

    pub fn setError(self: *PyFuture, err: anyerror) void {
        self.err = err;
        self.event.set();
    }

    pub fn getResult(self: *PyFuture) anyerror!Value {
        self.event.wait();
        if (self.err) |e| return e;
        return self.result_val;
    }
};

pub const PyThreadPool = struct {
    max_workers: usize,
    allocator: Allocator,
    is_shutdown: bool = false,

    pub fn init(allocator: Allocator, max_workers: usize) !*PyThreadPool {
        const self = try allocator.create(PyThreadPool);
        self.* = .{
            .max_workers = if (max_workers == 0) 1 else max_workers,
            .allocator = allocator,
            .is_shutdown = false,
        };
        return self;
    }
};

pub const PyCType = enum {
    c_void,
    c_bool,
    c_byte,
    c_char,
    c_short,
    c_int,
    c_long,
    c_longlong,
    c_size_t,
    c_float,
    c_double,
    c_char_p,
    c_void_p,

    pub fn size(self: PyCType) usize {
        return switch (self) {
            .c_void => 0,
            .c_bool, .c_byte, .c_char => 1,
            .c_short => 2,
            .c_int, .c_float => 4,
            .c_long, .c_longlong, .c_size_t, .c_double, .c_char_p, .c_void_p => 8,
        };
    }

    pub fn name(self: PyCType) []const u8 {
        return switch (self) {
            .c_void => "c_void",
            .c_bool => "c_bool",
            .c_byte => "c_byte",
            .c_char => "c_char",
            .c_short => "c_short",
            .c_int => "c_int",
            .c_long => "c_long",
            .c_longlong => "c_longlong",
            .c_size_t => "c_size_t",
            .c_float => "c_float",
            .c_double => "c_double",
            .c_char_p => "c_char_p",
            .c_void_p => "c_void_p",
        };
    }
};

pub const PyCDll = struct {
    name: []const u8,
    dyn_lib: std.DynLib,
    symbols: std.StringHashMap(Value),
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, dyn_lib: std.DynLib) !*PyCDll {
        const self = try allocator.create(PyCDll);
        self.* = .{
            .name = name,
            .dyn_lib = dyn_lib,
            .symbols = std.StringHashMap(Value).init(allocator),
            .allocator = allocator,
        };
        return self;
    }

    pub fn lookupSymbol(self: *PyCDll, symbol_name: []const u8) ?Value {
        if (self.symbols.get(symbol_name)) |sym| return sym;

        const name_z = self.allocator.allocSentinel(u8, symbol_name.len, 0) catch return null;
        defer self.allocator.free(name_z);
        @memcpy(name_z, symbol_name);

        var addr: ?usize = null;
        if (self.dyn_lib.lookup(*const fn () callconv(.c) void, name_z)) |f| {
            addr = @intFromPtr(f);
        } else if (@hasDecl(@TypeOf(self.dyn_lib.inner), "lookupAddress")) {
            addr = self.dyn_lib.inner.lookupAddress("", symbol_name);
        }

        if (addr == null) return null;

        const c_func = PyCFunc.init(self.allocator, symbol_name, addr.?) catch return null;
        const val = Value{ .c_func = c_func };
        self.symbols.put(symbol_name, val) catch {};
        return val;
    }

    pub fn close(self: *PyCDll) void {
        self.dyn_lib.close();
    }
};

pub const PyCFunc = struct {
    name: []const u8,
    addr: usize,
    restype: PyCType = .c_int,
    argtypes: std.ArrayList(PyCType),
    is_c_extension: bool = false,
    ml_flags: c_int = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator, name: []const u8, addr: usize) !*PyCFunc {
        const self = try allocator.create(PyCFunc);
        self.* = .{
            .name = name,
            .addr = addr,
            .restype = .c_int,
            .argtypes = .empty,
            .is_c_extension = false,
            .ml_flags = 0,
            .allocator = allocator,
        };
        return self;
    }
};

pub const PyIterator = struct {
    kind: union(enum) {
        range: struct { current: i64, stop: i64, step: i64 },
        list: struct { list: *PyList, index: usize },
        tuple: struct { items: []Value, index: usize },
        set: struct { items: []Value, index: usize },
        string: struct { str: []const u8, index: usize },
        generator: *PyGenerator,
    },

    pub fn next(self: *PyIterator, allocator: Allocator) ?Value {
        switch (self.kind) {
            .generator => |g| return g.next(),
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

pub const PyBigInt = struct {
    managed: std.math.big.int.Managed,

    pub fn init(allocator: Allocator, val: i64) !*PyBigInt {
        const self = try allocator.create(PyBigInt);
        self.managed = try std.math.big.int.Managed.init(allocator);
        try self.managed.set(val);
        return self;
    }

    pub fn initFromManaged(allocator: Allocator, m: std.math.big.int.Managed) !*PyBigInt {
        const self = try allocator.create(PyBigInt);
        self.managed = m;
        return self;
    }

    pub fn toString(self: *PyBigInt, allocator: Allocator) Allocator.Error![]const u8 {
        return self.managed.toString(allocator, 10, .lower) catch |err| switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InvalidBase => unreachable,
        };
    }
};

extern "c" fn fgetc(stream: *std.c.FILE) c_int;
extern "c" fn fseek(stream: *std.c.FILE, offset: c_long, whence: c_int) c_int;
extern "c" fn ftell(stream: *std.c.FILE) c_long;
extern "c" fn fflush(stream: *std.c.FILE) c_int;

pub const PyFile = struct {
    path: []const u8,
    mode: []const u8,
    handle: ?*std.c.FILE,
    is_closed: bool = false,
    allocator: Allocator,

    pub fn open(allocator: Allocator, path: []const u8, mode: []const u8) !*PyFile {
        const path_z = try allocator.allocSentinel(u8, path.len, 0);
        defer allocator.free(path_z);
        @memcpy(path_z, path);

        const mode_z = try allocator.allocSentinel(u8, mode.len, 0);
        defer allocator.free(mode_z);
        @memcpy(mode_z, mode);

        const f = std.c.fopen(path_z.ptr, mode_z.ptr);
        if (f == null) return error.FileNotFound;

        const path_copy = try allocator.dupe(u8, path);
        const mode_copy = try allocator.dupe(u8, mode);

        const self = try allocator.create(PyFile);
        self.* = .{
            .path = path_copy,
            .mode = mode_copy,
            .handle = f,
            .is_closed = false,
            .allocator = allocator,
        };
        return self;
    }

    pub fn read(self: *PyFile, max_size: ?usize) ![]const u8 {
        if (self.is_closed or self.handle == null) return error.ValueError;
        const h = self.handle.?;

        if (max_size) |sz| {
            const buf = try self.allocator.alloc(u8, sz);
            const n = std.c.fread(buf.ptr, 1, sz, h);
            if (n < sz) {
                return self.allocator.realloc(buf, n);
            }
            return buf;
        }

        var list: std.ArrayList(u8) = .empty;
        var chunk: [4096]u8 = undefined;
        while (true) {
            const n = std.c.fread(&chunk, 1, 4096, h);
            if (n == 0) break;
            try list.appendSlice(self.allocator, chunk[0..n]);
            if (n < 4096) break;
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn readline(self: *PyFile) ![]const u8 {
        if (self.is_closed or self.handle == null) return error.ValueError;
        const h = self.handle.?;
        var list: std.ArrayList(u8) = .empty;
        while (true) {
            const c = fgetc(h);
            if (c == -1) break;
            const b: u8 = @intCast(c);
            try list.append(self.allocator, b);
            if (b == '\n') break;
        }
        return list.toOwnedSlice(self.allocator);
    }

    pub fn readlines(self: *PyFile) !*PyList {
        const py_list = try PyList.init(self.allocator);
        while (true) {
            const line = try self.readline();
            if (line.len == 0) break;
            const str_val = try Value.makeString(self.allocator, line);
            try py_list.append(self.allocator, str_val);
        }
        return py_list;
    }

    pub fn write(self: *PyFile, data: []const u8) !usize {
        if (self.is_closed or self.handle == null) return error.ValueError;
        const h = self.handle.?;
        return std.c.fwrite(data.ptr, 1, data.len, h);
    }

    pub fn writelines(self: *PyFile, lines: []const Value) !void {
        for (lines) |item| {
            const s = try item.str(self.allocator);
            _ = try self.write(s);
        }
    }

    pub fn seek(self: *PyFile, offset: i64, whence: i32) !void {
        if (self.is_closed or self.handle == null) return error.ValueError;
        const res = fseek(self.handle.?, @intCast(offset), whence);
        if (res != 0) return error.OSError;
    }

    pub fn tell(self: *PyFile) !i64 {
        if (self.is_closed or self.handle == null) return error.ValueError;
        const res = ftell(self.handle.?);
        if (res < 0) return error.OSError;
        return @intCast(res);
    }

    pub fn flush(self: *PyFile) void {
        if (!self.is_closed and self.handle != null) {
            _ = fflush(self.handle.?);
        }
    }

    pub fn close(self: *PyFile) void {
        if (!self.is_closed and self.handle != null) {
            _ = std.c.fclose(self.handle.?);
            self.handle = null;
            self.is_closed = true;
        }
    }
};

pub const SockAddrIn = extern struct {
    sin_family: u16 = 2,
    sin_port: u16 = 0,
    sin_addr: u32 = 0,
    sin_zero: [8]u8 = [_]u8{ 0, 0, 0, 0, 0, 0, 0, 0 },
};

pub const PySocket = struct {
    handle: ?c_int,
    family: i32,
    type: i32,
    proto: i32,
    is_closed: bool = false,
    allocator: Allocator,

    pub fn create(allocator: Allocator, family: i32, sock_type: i32, proto: i32) !*PySocket {
        const fd = std.c.socket(@intCast(family), @intCast(sock_type), @intCast(proto));
        if (fd < 0) return error.OSError;

        const self = try allocator.create(PySocket);
        self.* = .{
            .handle = fd,
            .family = family,
            .type = sock_type,
            .proto = proto,
            .is_closed = false,
            .allocator = allocator,
        };
        return self;
    }

    pub fn connect(self: *PySocket, host: []const u8, port: u16) !void {
        if (self.is_closed or self.handle == null) return error.ValueError;
        var addr = SockAddrIn{
            .sin_family = 2,
            .sin_port = std.mem.nativeToBig(u16, port),
            .sin_addr = 0x0100007f, // loopback 127.0.0.1
        };

        if (!std.mem.eql(u8, host, "127.0.0.1") and !std.mem.eql(u8, host, "localhost")) {
            addr.sin_addr = 0x0100007f;
        }

        const ptr: *const std.c.sockaddr = @ptrCast(&addr);
        const res = std.c.connect(self.handle.?, ptr, @sizeOf(SockAddrIn));
        if (res < 0) return error.ConnectionRefused;
    }

    pub fn bind(self: *PySocket, host: []const u8, port: u16) !void {
        if (self.is_closed or self.handle == null) return error.ValueError;
        var addr = SockAddrIn{
            .sin_family = 2,
            .sin_port = std.mem.nativeToBig(u16, port),
            .sin_addr = 0x0100007f,
        };
        if (!std.mem.eql(u8, host, "127.0.0.1") and !std.mem.eql(u8, host, "localhost") and host.len > 0) {
            addr.sin_addr = 0; // INADDR_ANY
        }

        var opt: c_int = 1;
        _ = std.c.setsockopt(self.handle.?, std.c.SOL.SOCKET, std.c.SO.REUSEADDR, &opt, @sizeOf(c_int));

        const ptr: *const std.c.sockaddr = @ptrCast(&addr);
        const res = std.c.bind(self.handle.?, ptr, @sizeOf(SockAddrIn));
        if (res < 0) return error.OSError;
    }

    pub fn listen(self: *PySocket, backlog: i32) !void {
        if (self.is_closed or self.handle == null) return error.ValueError;
        const res = std.c.listen(self.handle.?, @intCast(backlog));
        if (res < 0) return error.OSError;
    }

    pub fn accept(self: *PySocket) !*PySocket {
        if (self.is_closed or self.handle == null) return error.ValueError;
        var client_addr: SockAddrIn = undefined;
        var addr_len: std.c.socklen_t = @sizeOf(SockAddrIn);
        const ptr: *std.c.sockaddr = @ptrCast(&client_addr);
        const client_fd = std.c.accept(self.handle.?, ptr, &addr_len);
        if (client_fd < 0) return error.OSError;

        const client = try self.allocator.create(PySocket);
        client.* = .{
            .handle = client_fd,
            .family = self.family,
            .type = self.type,
            .proto = self.proto,
            .is_closed = false,
            .allocator = self.allocator,
        };
        return client;
    }

    pub fn send(self: *PySocket, data: []const u8) !usize {
        if (self.is_closed or self.handle == null) return error.ValueError;
        const res = std.c.send(self.handle.?, data.ptr, data.len, 0);
        if (res < 0) return error.OSError;
        return @intCast(res);
    }

    pub fn recv(self: *PySocket, buf_size: usize) ![]const u8 {
        if (self.is_closed or self.handle == null) return error.ValueError;
        const buf = try self.allocator.alloc(u8, buf_size);
        const res = std.c.recv(self.handle.?, buf.ptr, buf_size, 0);
        if (res < 0) return error.OSError;
        const n: usize = @intCast(res);
        if (n < buf_size) {
            return self.allocator.realloc(buf, n);
        }
        return buf;
    }

    pub fn close(self: *PySocket) void {
        if (!self.is_closed and self.handle != null) {
            _ = std.c.close(self.handle.?);
            self.handle = null;
            self.is_closed = true;
        }
    }
};

pub const Value = union(enum) {
    none,
    bool: bool,
    int: i64,
    bignum: *PyBigInt,
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
    generator: *PyGenerator,
    coroutine: *PyCoroutine,
    thread: *PyThread,
    lock: *PyLock,
    semaphore: *PySemaphore,
    event: *PyEvent,
    future: *PyFuture,
    thread_pool: *PyThreadPool,
    c_dll: *PyCDll,
    c_func: *PyCFunc,
    c_type: PyCType,
    file: *PyFile,
    socket: *PySocket,
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
            .bignum => |b| !b.managed.eqlZero(),
            .float => |f| f != 0.0,
            .string => |s| s.bytes.len > 0,
            .list => |l| l.items.items.len > 0,
            .tuple => |t| t.items.len > 0,
            .dict => |d| d.entries.items.len > 0,
            .set => |s| s.items.items.len > 0,
            .range => |r| r.length() > 0,
            .function, .builtin, .class, .instance, .bound_method, .module, .iterator, .generator, .coroutine, .thread, .lock, .semaphore, .event, .future, .thread_pool, .c_dll, .c_func, .c_type, .file, .socket => true,
            .return_flow, .break_flow, .continue_flow => false,
        };
    }

    pub fn typeName(self: Value) []const u8 {
        return switch (self) {
            .none => "NoneType",
            .bool => "bool",
            .int, .bignum => "int",
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
            .generator => "generator",
            .coroutine => "coroutine",
            .thread => "Thread",
            .lock => "Lock",
            .semaphore => "Semaphore",
            .event => "Event",
            .future => "Future",
            .thread_pool => "ThreadPoolExecutor",
            .c_dll => "CDLL",
            .c_func => "CFunction",
            .c_type => "PyCSimpleType",
            .file => "_io.TextIOWrapper",
            .socket => "socket.socket",
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
                if (other == .bignum) {
                    if (other.bignum.managed.toInt(i64)) |val| {
                        return i == val;
                    } else |_| return false;
                }
                if (other == .float) return @as(f64, @floatFromInt(i)) == other.float;
                if (other == .bool) return i == (if (other.bool) @as(i64, 1) else @as(i64, 0));
                return false;
            },
            .bignum => |b| {
                if (other == .bignum) return b.managed.eql(other.bignum.managed);
                if (other == .int) {
                    if (b.managed.toInt(i64)) |val| {
                        return val == other.int;
                    } else |_| return false;
                }
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
            .generator => |g| {
                if (other != .generator) return false;
                return g == other.generator;
            },
            .coroutine => |co| {
                if (other != .coroutine) return false;
                return co == other.coroutine;
            },
            .thread => |t| {
                if (other != .thread) return false;
                return t == other.thread;
            },
            .lock => |l| {
                if (other != .lock) return false;
                return l == other.lock;
            },
            .semaphore => |s| {
                if (other != .semaphore) return false;
                return s == other.semaphore;
            },
            .event => |e| {
                if (other != .event) return false;
                return e == other.event;
            },
            .future => |f| {
                if (other != .future) return false;
                return f == other.future;
            },
            .thread_pool => |p| {
                if (other != .thread_pool) return false;
                return p == other.thread_pool;
            },
            .c_dll => |d| {
                if (other != .c_dll) return false;
                return d == other.c_dll;
            },
            .c_func => |cf| {
                if (other != .c_func) return false;
                return cf == other.c_func;
            },
            .c_type => |ct| {
                if (other != .c_type) return false;
                return ct == other.c_type;
            },
            else => return false,
        }
    }

    pub fn str(self: Value, allocator: Allocator) Allocator.Error![]const u8 {
        switch (self) {
            .none => return "None",
            .bool => |b| return if (b) "True" else "False",
            .int => |i| return std.fmt.allocPrint(allocator, "{d}", .{i}),
            .bignum => |b| return b.toString(allocator),
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
            .generator => |g| return std.fmt.allocPrint(allocator, "<generator object {s}>", .{g.name}),
            .coroutine => |co| return std.fmt.allocPrint(allocator, "<coroutine object {s}>", .{co.name}),
            .thread => |t| return std.fmt.allocPrint(allocator, "<Thread({s}, ident={d}, {s})>", .{ t.name, t.ident, if (t.is_alive) "alive" else "stopped" }),
            .lock => |l| return std.fmt.allocPrint(allocator, "<{s} _thread.lock object at 0x{x}>", .{ if (l.is_locked) "locked" else "unlocked", @intFromPtr(l) }),
            .semaphore => |s| return std.fmt.allocPrint(allocator, "<_thread.Semaphore object at 0x{x}>", .{@intFromPtr(s)}),
            .event => |e| return std.fmt.allocPrint(allocator, "<threading.Event object at 0x{x} is_set={s}>", .{ @intFromPtr(e), if (e.isSet()) "True" else "False" }),
            .future => |f| return std.fmt.allocPrint(allocator, "<Future at 0x{x} state={s}>", .{ @intFromPtr(f), if (f.event.isSet()) "finished" else "pending" }),
            .thread_pool => |p| return std.fmt.allocPrint(allocator, "<ThreadPoolExecutor max_workers={d}>", .{p.max_workers}),
            .c_dll => |d| return std.fmt.allocPrint(allocator, "<CDLL '{s}', handle 0x{x}>", .{ d.name, @intFromPtr(d) }),
            .c_func => |cf| return std.fmt.allocPrint(allocator, "<_FuncPtr '{s}'>", .{cf.name}),
            .c_type => |ct| return std.fmt.allocPrint(allocator, "<class 'ctypes.{s}'>", .{ct.name()}),
            .file => |fl| return std.fmt.allocPrint(allocator, "<_io.TextIOWrapper name='{s}' mode='{s}' encoding='utf-8'>", .{ fl.path, fl.mode }),
            .socket => |s| return std.fmt.allocPrint(allocator, "<socket.socket fd={?d}, family={d}, type={d}>", .{ s.handle, s.family, s.type }),
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
