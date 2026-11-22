const std = @import("std");
const Allocator = std.mem.Allocator;
const value_mod = @import("value.zig");
const Value = value_mod.Value;

pub const Opcode = enum(u8) {
    op_pop,
    op_dup,
    op_dup2,
    op_swap,
    op_rot_three,
    op_none,
    op_true,
    op_false,
    op_const,

    // Variables & Scopes
    op_load_fast,
    op_store_fast,
    op_load_global,
    op_store_global,

    // Binary Arithmetic & Bitwise
    op_add,
    op_sub,
    op_mul,
    op_div,
    op_floor_div,
    op_mod,
    op_pow,
    op_bit_and,
    op_bit_or,
    op_bit_xor,
    op_lshift,
    op_rshift,

    // Unary
    op_neg,
    op_not,
    op_invert,

    // Comparisons
    op_eq,
    op_ne,
    op_lt,
    op_le,
    op_gt,
    op_ge,
    op_in,
    op_not_in,
    op_is,
    op_is_not,

    // Control Flow & Branching
    op_jump,
    op_jump_if_false,
    op_pop_jump_if_false,
    op_jump_if_true,
    op_pop_jump_if_true,

    // Loops & Iteration
    op_get_iter,
    op_for_iter,

    // Subscripts & Attributes
    op_get_subscript,
    op_set_subscript,
    op_get_slice,
    op_get_attr,
    op_set_attr,

    // Collections
    op_build_list,
    op_build_tuple,
    op_build_dict,
    op_build_set,
    op_list_append,
    op_unpack_tuple,

    // Functions & Execution
    op_call,
    op_return,
    op_format_value,
    op_build_string,
    op_halt,
};

pub const Instruction = packed struct {
    op: Opcode,
    arg: u24 = 0,
};

pub const Chunk = struct {
    allocator: Allocator,
    code: std.ArrayList(Instruction),
    constants: std.ArrayList(Value),
    names: std.ArrayList([]const u8),
    lines: std.ArrayList(u32),
    num_locals: u32 = 0,

    pub fn init(allocator: Allocator) Chunk {
        return .{
            .allocator = allocator,
            .code = .empty,
            .constants = .empty,
            .names = .empty,
            .lines = .empty,
        };
    }

    pub fn deinit(self: *Chunk) void {
        self.code.deinit(self.allocator);
        self.constants.deinit(self.allocator);
        self.names.deinit(self.allocator);
        self.lines.deinit(self.allocator);
    }

    pub inline fn write(self: *Chunk, op: Opcode, arg: u24, line: u32) !usize {
        const idx = self.code.items.len;
        try self.code.append(self.allocator, .{ .op = op, .arg = arg });
        try self.lines.append(self.allocator, line);
        return idx;
    }

    pub inline fn addConstant(self: *Chunk, val: Value) !u24 {
        // Linear scan for small deduplication of constants (strict type & value match)
        for (self.constants.items, 0..) |existing, i| {
            if (std.meta.activeTag(existing) == std.meta.activeTag(val) and existing.equals(val)) {
                return @intCast(i);
            }
        }
        const idx = self.constants.items.len;
        try self.constants.append(self.allocator, val);
        return @intCast(idx);
    }

    pub inline fn addName(self: *Chunk, name: []const u8) !u24 {
        for (self.names.items, 0..) |n, i| {
            if (std.mem.eql(u8, n, name)) return @intCast(i);
        }
        const idx = self.names.items.len;
        try self.names.append(self.allocator, name);
        return @intCast(idx);
    }

    pub inline fn patchJump(self: *Chunk, instruction_idx: usize, target_idx: usize) void {
        self.code.items[instruction_idx].arg = @intCast(target_idx);
    }
};
