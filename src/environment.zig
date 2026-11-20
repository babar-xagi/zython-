const std = @import("std");
const Allocator = std.mem.Allocator;
const value_mod = @import("value.zig");
const Value = value_mod.Value;

pub const Environment = struct {
    allocator: Allocator,
    parent: ?*Environment,
    globals: ?*Environment,
    bindings: std.StringHashMap(Value),
    global_vars: std.StringHashMap(void),

    pub fn init(allocator: Allocator, parent: ?*Environment) !*Environment {
        const self = try allocator.create(Environment);
        self.* = .{
            .allocator = allocator,
            .parent = parent,
            .globals = if (parent) |p| (p.globals orelse p) else null,
            .bindings = std.StringHashMap(Value).init(allocator),
            .global_vars = std.StringHashMap(void).init(allocator),
        };
        return self;
    }

    pub fn markGlobal(self: *Environment, name: []const u8) !void {
        try self.global_vars.put(name, {});
    }

    pub fn get(self: *Environment, name: []const u8) ?Value {
        if (self.global_vars.contains(name)) {
            if (self.globals) |g| {
                return g.get(name);
            }
        }
        if (self.bindings.get(name)) |v| {
            return v;
        }
        if (self.parent) |p| {
            return p.get(name);
        }
        if (self.globals) |g| {
            return g.get(name);
        }
        return null;
    }

    pub fn set(self: *Environment, name: []const u8, val: Value) !void {
        if (self.global_vars.contains(name)) {
            if (self.globals) |g| {
                try g.set(name, val);
                return;
            }
        }
        try self.bindings.put(name, val);
    }

    pub fn assign(self: *Environment, name: []const u8, val: Value) !bool {
        if (self.global_vars.contains(name)) {
            if (self.globals) |g| {
                return g.assign(name, val);
            }
        }
        if (self.bindings.contains(name)) {
            try self.bindings.put(name, val);
            return true;
        }
        if (self.parent) |p| {
            return p.assign(name, val);
        }
        return false;
    }
};
