const std = @import("std");
const Allocator = std.mem.Allocator;
const value_mod = @import("value.zig");
const Value = value_mod.Value;

pub const LocalSlot = struct {
    name: []const u8,
    val: Value,
};

pub const Environment = struct {
    allocator: Allocator,
    parent: ?*Environment,
    globals: ?*Environment,

    // Fast inline slots in CPU cache (avoids hash map allocation for 99.9% of functions!)
    fast_slots: [32]LocalSlot = undefined,
    fast_count: u8 = 0,

    // Lazy heap maps if local variables exceed 8 or globals are marked
    bindings: ?std.StringHashMap(Value) = null,
    global_vars: ?std.StringHashMap(void) = null,
    is_escaped: bool = false,

    pub fn init(allocator: Allocator, parent: ?*Environment) !*Environment {
        const self = try allocator.create(Environment);
        self.* = .{
            .allocator = allocator,
            .parent = parent,
            .globals = if (parent) |p| (p.globals orelse p) else null,
            .fast_count = 0,
            .bindings = null,
            .global_vars = null,
            .is_escaped = false,
        };
        return self;
    }

    pub fn reset(self: *Environment, parent: ?*Environment) void {
        self.parent = parent;
        self.globals = if (parent) |p| (p.globals orelse p) else null;
        self.fast_count = 0;
        self.is_escaped = false;
        if (self.bindings) |*b| {
            b.clearRetainingCapacity();
        }
        if (self.global_vars) |*g| {
            g.clearRetainingCapacity();
        }
    }

    pub fn markEscaped(self: *Environment) void {
        var cur: ?*Environment = self;
        while (cur) |e| {
            e.is_escaped = true;
            cur = e.parent;
        }
    }

    pub fn markGlobal(self: *Environment, name: []const u8) !void {
        if (self.global_vars == null) {
            self.global_vars = std.StringHashMap(void).init(self.allocator);
        }
        try self.global_vars.?.put(name, {});
    }

    pub fn getSlotPtr(self: *Environment, name: []const u8) ?*Value {
        var i: u8 = 0;
        while (i < self.fast_count) : (i += 1) {
            if (self.fast_slots[i].name.ptr == name.ptr or std.mem.eql(u8, self.fast_slots[i].name, name)) {
                return &self.fast_slots[i].val;
            }
        }
        if (self.bindings) |*b| {
            if (b.getPtr(name)) |v_ptr| {
                return v_ptr;
            }
        }
        return null;
    }

    pub fn get(self: *Environment, name: []const u8) ?Value {
        if (self.global_vars) |*gv| {
            if (gv.contains(name)) {
                if (self.globals) |g| {
                    return g.get(name);
                }
            }
        }

        // 1. Fast inline slots (no hash computation!)
        var i: u8 = 0;
        while (i < self.fast_count) : (i += 1) {
            if (self.fast_slots[i].name.ptr == name.ptr or std.mem.eql(u8, self.fast_slots[i].name, name)) {
                return self.fast_slots[i].val;
            }
        }

        // 2. Overflow bindings
        if (self.bindings) |*b| {
            if (b.get(name)) |v| return v;
        }

        // 3. Parent / Globals chain
        if (self.parent) |p| {
            return p.get(name);
        }
        if (self.globals) |g| {
            return g.get(name);
        }
        return null;
    }

    pub fn set(self: *Environment, name: []const u8, val: Value) !void {
        if (self.global_vars) |*gv| {
            if (gv.contains(name)) {
                if (self.globals) |g| {
                    try g.set(name, val);
                    return;
                }
            }
        }

        // 1. Check existing fast slots
        var i: u8 = 0;
        while (i < self.fast_count) : (i += 1) {
            if (self.fast_slots[i].name.ptr == name.ptr or std.mem.eql(u8, self.fast_slots[i].name, name)) {
                self.fast_slots[i].val = val;
                return;
            }
        }

        // 2. Append to fast slots if space available
        if (self.fast_count < 32) {
            self.fast_slots[self.fast_count] = .{ .name = name, .val = val };
            self.fast_count += 1;
            return;
        }

        // 3. Overflow to heap hash map
        if (self.bindings == null) {
            self.bindings = std.StringHashMap(Value).init(self.allocator);
        }
        try self.bindings.?.put(name, val);
    }

    pub fn assign(self: *Environment, name: []const u8, val: Value) !bool {
        if (self.global_vars) |*gv| {
            if (gv.contains(name)) {
                if (self.globals) |g| {
                    return g.assign(name, val);
                }
            }
        }

        var i: u8 = 0;
        while (i < self.fast_count) : (i += 1) {
            if (self.fast_slots[i].name.ptr == name.ptr or std.mem.eql(u8, self.fast_slots[i].name, name)) {
                self.fast_slots[i].val = val;
                return true;
            }
        }

        if (self.bindings) |*b| {
            if (b.contains(name)) {
                try b.put(name, val);
                return true;
            }
        }

        if (self.parent) |p| {
            return p.assign(name, val);
        }
        return false;
    }
};
