const std = @import("std");
const Allocator = std.mem.Allocator;
const value_mod = @import("value.zig");
const Value = value_mod.Value;
const PyString = value_mod.PyString;
const PyList = value_mod.PyList;
const PyTuple = value_mod.PyTuple;
const PyDict = value_mod.PyDict;
const PyModule = value_mod.PyModule;
const PyBuiltin = value_mod.PyBuiltin;

pub const METH_VARARGS: c_int = 0x0001;
pub const METH_KEYWORDS: c_int = 0x0002;
pub const METH_NOARGS: c_int = 0x0004;
pub const METH_O: c_int = 0x0008;

pub const PyObjectKind = enum {
    long,
    float,
    unicode,
    tuple,
    list,
    dict,
    module,
};

pub const PyObject = extern struct {
    ob_refcnt: isize = 1,
    ob_type: ?*anyopaque = null,
};

pub const PyLongObject = extern struct {
    ob_base: PyObject = .{ .ob_refcnt = 1, .ob_type = null },
    value: i64,
};

pub const PyFloatObject = extern struct {
    ob_base: PyObject = .{ .ob_refcnt = 1, .ob_type = null },
    value: f64,
};

pub const PyUnicodeObject = extern struct {
    ob_base: PyObject = .{ .ob_refcnt = 1, .ob_type = null },
    length: isize,
    utf8: ?[*:0]const u8,
};

pub const PyTupleObject = extern struct {
    ob_base: PyObject = .{ .ob_refcnt = 1, .ob_type = null },
    size: isize,
    items: [*]?*PyObject,
};

pub const PyListObject = extern struct {
    ob_base: PyObject = .{ .ob_refcnt = 1, .ob_type = null },
    size: isize,
    allocated: isize,
    items: [*]?*PyObject,
};

pub const PyDictEntry = extern struct {
    key: ?*PyObject,
    val: ?*PyObject,
};

pub const PyDictObject = extern struct {
    ob_base: PyObject = .{ .ob_refcnt = 1, .ob_type = null },
    size: isize,
    capacity: isize,
    entries: [*]PyDictEntry,
};

pub const PyMethodDef = extern struct {
    ml_name: ?[*:0]const u8,
    ml_meth: ?*const anyopaque,
    ml_flags: c_int,
    ml_doc: ?[*:0]const u8,
};

pub const PyModuleDef_Base = extern struct {
    ob_base: PyObject = .{ .ob_refcnt = 1, .ob_type = null },
    m_init: ?*const anyopaque = null,
    m_index: isize = 0,
    m_copy: ?*anyopaque = null,
};

pub const PyModuleDef = extern struct {
    m_base: PyModuleDef_Base = .{},
    m_name: [*:0]const u8,
    m_doc: ?[*:0]const u8 = null,
    m_size: isize = -1,
    m_methods: ?[*]const PyMethodDef = null,
};

pub const PyModuleObject = extern struct {
    ob_base: PyObject = .{ .ob_refcnt = 1, .ob_type = null },
    def: ?*const PyModuleDef = null,
    name: [*:0]const u8,
};

// Global arena allocator for C API objects
var g_c_allocator: ?Allocator = null;
var g_last_created_module: ?*const PyModuleDef = null;

pub fn initCApi(allocator: Allocator) void {
    g_c_allocator = allocator;
}

pub fn getCApiAllocator() Allocator {
    return g_c_allocator orelse std.heap.page_allocator;
}

// C-API Exported Functions
pub export fn PyLong_FromLong(v: c_long) callconv(.c) ?*PyObject {
    const alloc = getCApiAllocator();
    const obj = alloc.create(PyLongObject) catch return null;
    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = @ptrFromInt(1) },
        .value = @intCast(v),
    };
    return @ptrCast(obj);
}

pub export fn PyLong_FromLongLong(v: c_longlong) callconv(.c) ?*PyObject {
    const alloc = getCApiAllocator();
    const obj = alloc.create(PyLongObject) catch return null;
    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = @ptrFromInt(1) },
        .value = @intCast(v),
    };
    return @ptrCast(obj);
}

pub export fn PyLong_AsLong(obj: ?*PyObject) callconv(.c) c_long {
    if (obj == null) return 0;
    const l: *PyLongObject = @ptrCast(@alignCast(obj.?));
    return @intCast(l.value);
}

pub export fn PyLong_AsLongLong(obj: ?*PyObject) callconv(.c) c_longlong {
    if (obj == null) return 0;
    const l: *PyLongObject = @ptrCast(@alignCast(obj.?));
    return @intCast(l.value);
}

pub export fn PyFloat_FromDouble(v: f64) callconv(.c) ?*PyObject {
    const alloc = getCApiAllocator();
    const obj = alloc.create(PyFloatObject) catch return null;
    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = @ptrFromInt(2) },
        .value = v,
    };
    return @ptrCast(obj);
}

pub export fn PyFloat_AsDouble(obj: ?*PyObject) callconv(.c) f64 {
    if (obj == null) return 0.0;
    const fl: *PyFloatObject = @ptrCast(@alignCast(obj.?));
    return fl.value;
}

pub export fn PyUnicode_FromString(str: [*:0]const u8) callconv(.c) ?*PyObject {
    const alloc = getCApiAllocator();
    const len = std.mem.len(str);
    const buf = alloc.allocSentinel(u8, len, 0) catch return null;
    @memcpy(buf, str[0..len]);
    const obj = alloc.create(PyUnicodeObject) catch return null;
    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = @ptrFromInt(3) },
        .length = @intCast(len),
        .utf8 = buf.ptr,
    };
    return @ptrCast(obj);
}

pub export fn PyUnicode_AsUTF8(obj: ?*PyObject) callconv(.c) ?[*:0]const u8 {
    if (obj == null) return null;
    const u: *PyUnicodeObject = @ptrCast(@alignCast(obj.?));
    return u.utf8;
}

pub export fn PyTuple_New(size: isize) callconv(.c) ?*PyObject {
    const alloc = getCApiAllocator();
    const obj = alloc.create(PyTupleObject) catch return null;
    const usize_size: usize = if (size > 0) @intCast(size) else 0;
    const items_buf = alloc.alloc(?*PyObject, usize_size) catch return null;
    @memset(items_buf, null);
    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = @ptrFromInt(4) },
        .size = size,
        .items = items_buf.ptr,
    };
    return @ptrCast(obj);
}

pub export fn PyTuple_SetItem(p: ?*PyObject, pos: isize, item: ?*PyObject) callconv(.c) c_int {
    if (p == null) return -1;
    const tup: *PyTupleObject = @ptrCast(@alignCast(p.?));
    if (pos < 0 or pos >= tup.size) return -1;
    tup.items[@intCast(pos)] = item;
    return 0;
}

pub export fn PyTuple_GetItem(p: ?*PyObject, pos: isize) callconv(.c) ?*PyObject {
    if (p == null) return null;
    const tup: *PyTupleObject = @ptrCast(@alignCast(p.?));
    if (pos < 0 or pos >= tup.size) return null;
    return tup.items[@intCast(pos)];
}

pub export fn PyTuple_Size(p: ?*PyObject) callconv(.c) isize {
    if (p == null) return 0;
    const tup: *PyTupleObject = @ptrCast(@alignCast(p.?));
    return tup.size;
}

pub export fn PyList_New(size: isize) callconv(.c) ?*PyObject {
    const alloc = getCApiAllocator();
    const obj = alloc.create(PyListObject) catch return null;
    const usize_size: usize = if (size > 0) @intCast(size) else 4;
    const items_buf = alloc.alloc(?*PyObject, usize_size) catch return null;
    @memset(items_buf, null);
    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = @ptrFromInt(5) },
        .size = size,
        .allocated = @intCast(usize_size),
        .items = items_buf.ptr,
    };
    return @ptrCast(obj);
}

pub export fn PyList_Append(p: ?*PyObject, item: ?*PyObject) callconv(.c) c_int {
    if (p == null) return -1;
    const l: *PyListObject = @ptrCast(@alignCast(p.?));
    const alloc = getCApiAllocator();
    if (l.size >= l.allocated) {
        const new_cap = @as(usize, @intCast(l.allocated)) * 2;
        const new_buf = alloc.alloc(?*PyObject, new_cap) catch return -1;
        const old_slice = l.items[0..@as(usize, @intCast(l.size))];
        @memcpy(new_buf[0..old_slice.len], old_slice);
        l.items = new_buf.ptr;
        l.allocated = @intCast(new_cap);
    }
    l.items[@intCast(l.size)] = item;
    l.size += 1;
    return 0;
}

pub export fn PyList_GetItem(p: ?*PyObject, pos: isize) callconv(.c) ?*PyObject {
    if (p == null) return null;
    const l: *PyListObject = @ptrCast(@alignCast(p.?));
    if (pos < 0 or pos >= l.size) return null;
    return l.items[@intCast(pos)];
}

pub export fn PyList_Size(p: ?*PyObject) callconv(.c) isize {
    if (p == null) return 0;
    const l: *PyListObject = @ptrCast(@alignCast(p.?));
    return l.size;
}

pub export fn PyDict_New() callconv(.c) ?*PyObject {
    const alloc = getCApiAllocator();
    const obj = alloc.create(PyDictObject) catch return null;
    const entries = alloc.alloc(PyDictEntry, 8) catch return null;
    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = @ptrFromInt(6) },
        .size = 0,
        .capacity = 8,
        .entries = entries.ptr,
    };
    return @ptrCast(obj);
}

pub export fn PyModule_Create2(def: *const PyModuleDef, apiver: c_int) callconv(.c) ?*PyObject {
    _ = apiver;
    g_last_created_module = def;
    const alloc = getCApiAllocator();
    const obj = alloc.create(PyModuleObject) catch return null;
    obj.* = .{
        .ob_base = .{ .ob_refcnt = 1, .ob_type = @ptrFromInt(7) },
        .def = def,
        .name = def.m_name,
    };
    return @ptrCast(obj);
}

pub export fn Py_IncRef(obj: ?*PyObject) callconv(.c) void {
    if (obj) |o| {
        o.ob_refcnt += 1;
    }
}

pub export fn Py_DecRef(obj: ?*PyObject) callconv(.c) void {
    if (obj) |o| {
        o.ob_refcnt -= 1;
    }
}

// Convert Zython Value to PyObject*
pub fn valueToPyObject(allocator: Allocator, val: Value) ?*PyObject {
    switch (val) {
        .int => |n| return PyLong_FromLong(@intCast(n)),
        .float => |f| return PyFloat_FromDouble(f),
        .string => |s| {
            const z = allocator.allocSentinel(u8, s.bytes.len, 0) catch return null;
            @memcpy(z, s.bytes);
            return PyUnicode_FromString(z.ptr);
        },
        .tuple => |t| {
            const tup_obj = PyTuple_New(@intCast(t.items.len)) orelse return null;
            for (t.items, 0..) |item, i| {
                const item_obj = valueToPyObject(allocator, item);
                _ = PyTuple_SetItem(tup_obj, @intCast(i), item_obj);
            }
            return tup_obj;
        },
        .list => |l| {
            const list_obj = PyList_New(0) orelse return null;
            for (l.items.items) |item| {
                const item_obj = valueToPyObject(allocator, item);
                _ = PyList_Append(list_obj, item_obj);
            }
            return list_obj;
        },
        else => return PyLong_FromLong(0),
    }
}

// Convert PyObject* to Zython Value
pub fn pyObjectToValue(allocator: Allocator, obj: ?*PyObject, expected_type: ?value_mod.PyCType) Value {
    if (obj == null) return .none;
    if (obj.?.ob_type) |t_ptr| {
        const type_id = @intFromPtr(t_ptr);
        if (type_id == 2) {
            const fl: *PyFloatObject = @ptrCast(@alignCast(obj.?));
            return Value.makeFloat(fl.value);
        } else if (type_id == 3) {
            const u: *PyUnicodeObject = @ptrCast(@alignCast(obj.?));
            if (u.utf8) |str_ptr| {
                const span = std.mem.span(str_ptr);
                const py_s = PyString.init(allocator, span) catch return .none;
                return Value{ .string = py_s };
            }
            return .none;
        } else if (type_id == 1) {
            const l: *PyLongObject = @ptrCast(@alignCast(obj.?));
            return Value.makeInt(l.value);
        }
    }
    if (expected_type) |et| {
        switch (et) {
            .c_double, .c_float => {
                const fl: *PyFloatObject = @ptrCast(@alignCast(obj.?));
                return Value.makeFloat(fl.value);
            },
            .c_char_p => {
                const u: *PyUnicodeObject = @ptrCast(@alignCast(obj.?));
                if (u.utf8) |str_ptr| {
                    const span = std.mem.span(str_ptr);
                    const py_s = PyString.init(allocator, span) catch return .none;
                    return Value{ .string = py_s };
                }
                return .none;
            },
            else => {
                const l: *PyLongObject = @ptrCast(@alignCast(obj.?));
                return Value.makeInt(l.value);
            },
        }
    }
    // Heuristic inspection: default as long
    const l: *PyLongObject = @ptrCast(@alignCast(obj.?));
    return Value.makeInt(l.value);
}

// Load a C-Extension (.so) into a Zython PyModule
pub fn loadCExtensionModule(allocator: Allocator, module_name: []const u8, so_path: []const u8) !*PyModule {
    var dyn_lib = try std.DynLib.open(so_path);

    // Resolve PyInit_<module_name>
    var init_name_buf: [128]u8 = undefined;
    const init_name_slice = try std.fmt.bufPrint(&init_name_buf, "PyInit_{s}", .{module_name});
    const init_fn_name = try allocator.allocSentinel(u8, init_name_slice.len, 0);
    defer allocator.free(init_fn_name);
    @memcpy(init_fn_name, init_name_slice);

    const init_fn = dyn_lib.lookup(*const fn () callconv(.c) ?*PyObject, init_fn_name);
    if (init_fn == null) {
        return error.SymbolNotFound;
    }

    g_last_created_module = null;
    const mod_obj = init_fn.?();
    if (mod_obj == null and g_last_created_module == null) {
        return error.ModuleInitFailed;
    }

    const def: *const PyModuleDef = if (g_last_created_module) |g|
        g
    else if (mod_obj) |mo| init: {
        const m_obj: *PyModuleObject = @ptrCast(@alignCast(mo));
        if (m_obj.def) |d| {
            break :init d;
        } else {
            const def_candidate: *const PyModuleDef = @ptrCast(@alignCast(mo));
            if (def_candidate.m_methods != null) {
                break :init def_candidate;
            }
            return error.ModuleDefNotFound;
        }
    } else return error.ModuleDefNotFound;

    const py_mod = try PyModule.init(allocator, module_name);

    if (def.m_methods) |methods| {
        var idx: usize = 0;
        while (true) : (idx += 1) {
            const m = methods[idx];
            if (m.ml_name == null) break;
            const m_name = std.mem.span(m.ml_name.?);
            if (m.ml_meth) |meth_ptr| {
                const c_func_addr = @intFromPtr(meth_ptr);
                const c_func = try value_mod.PyCFunc.init(allocator, m_name, c_func_addr);
                c_func.is_c_extension = true;
                c_func.ml_flags = m.ml_flags;
                try py_mod.attributes.put(m_name, Value{ .c_func = c_func });
            }
        }
    }

    return py_mod;
}
