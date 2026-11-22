const std = @import("std");
const Allocator = std.mem.Allocator;
const ast_mod = @import("ast.zig");
const Expr = ast_mod.Expr;
const Stmt = ast_mod.Stmt;
const BinaryOp = ast_mod.BinaryOp;
const CompareOp = ast_mod.CompareOp;
const value_mod = @import("value.zig");
const Value = value_mod.Value;
const bytecode_mod = @import("bytecode.zig");
const Opcode = bytecode_mod.Opcode;
const Instruction = bytecode_mod.Instruction;
const Chunk = bytecode_mod.Chunk;

pub const Local = struct {
    name: []const u8,
    depth: u32,
    is_captured: bool = false,
};

pub const LoopContext = struct {
    start_ip: usize,
    break_jumps: std.ArrayList(usize),
    is_for_loop: bool = false,
};

pub const Compiler = struct {
    allocator: Allocator,
    chunk: *Chunk,
    locals: [256]Local = undefined,
    local_count: u32 = 0,
    scope_depth: u32 = 0,
    current_loop: ?*LoopContext = null,

    pub fn init(allocator: Allocator, chunk: *Chunk) Compiler {
        return .{
            .allocator = allocator,
            .chunk = chunk,
            .local_count = 0,
            .scope_depth = 0,
            .current_loop = null,
        };
    }

    pub fn initFunction(allocator: Allocator, chunk: *Chunk) Compiler {
        var c = init(allocator, chunk);
        c.scope_depth = 1;
        return c;
    }

    pub inline fn emit(self: *Compiler, op: Opcode, arg: u24) !usize {
        return self.chunk.write(op, arg, 0);
    }

    pub fn enterScope(self: *Compiler) void {
        self.scope_depth += 1;
    }

    pub fn exitScope(self: *Compiler) !void {
        self.scope_depth -= 1;
        while (self.local_count > 0 and self.locals[self.local_count - 1].depth > self.scope_depth) {
            _ = try self.emit(.op_pop, 0);
            self.local_count -= 1;
        }
    }

    pub fn addLocal(self: *Compiler, name: []const u8) !u8 {
        if (self.local_count >= 256) return error.TooManyLocals;
        const idx: u8 = @intCast(self.local_count);
        self.locals[self.local_count] = .{
            .name = name,
            .depth = self.scope_depth,
            .is_captured = false,
        };
        self.local_count += 1;
        return idx;
    }

    pub fn resolveLocal(self: *Compiler, name: []const u8) ?u8 {
        var i: i32 = @as(i32, @intCast(self.local_count)) - 1;
        while (i >= 0) : (i -= 1) {
            const idx: usize = @intCast(i);
            if (std.mem.eql(u8, self.locals[idx].name, name)) {
                return @intCast(idx);
            }
        }
        return null;
    }

    pub fn compileSuite(self: *Compiler, stmts: []const Stmt) anyerror!void {
        for (stmts) |stmt| {
            try self.compileStmt(stmt);
        }
        self.chunk.num_locals = self.local_count;
    }

    pub fn compileStmt(self: *Compiler, stmt: Stmt) anyerror!void {
        switch (stmt) {
            .expr_stmt => |e| {
                try self.compileExpr(e);
                _ = try self.emit(.op_pop, 0);
            },
            .assign => |a| {
                try self.compileExpr(a.value);
                for (a.targets, 0..) |target, idx| {
                    if (idx < a.targets.len - 1) {
                        _ = try self.emit(.op_dup, 0);
                    }
                    try self.compileAssignmentTarget(target);
                }
            },
            .aug_assign => |aa| {
                switch (aa.target.*) {
                    .identifier => |id| {
                        if (self.resolveLocal(id.name)) |slot| {
                            _ = try self.emit(.op_load_fast, slot);
                            try self.compileExpr(aa.value);
                            try self.emitBinaryOp(aa.op);
                            _ = try self.emit(.op_store_fast, slot);
                        } else {
                            const name_idx = try self.chunk.addName(id.name);
                            _ = try self.emit(.op_load_global, name_idx);
                            try self.compileExpr(aa.value);
                            try self.emitBinaryOp(aa.op);
                            _ = try self.emit(.op_store_global, name_idx);
                        }
                    },
                    .attribute => |att| {
                        try self.compileExpr(att.value);
                        _ = try self.emit(.op_dup, 0);
                        const name_idx = try self.chunk.addName(att.attr);
                        _ = try self.emit(.op_get_attr, name_idx);
                        try self.compileExpr(aa.value);
                        try self.emitBinaryOp(aa.op);
                        _ = try self.emit(.op_set_attr, name_idx);
                    },
                    .subscript => |sub| {
                        try self.compileExpr(sub.value);
                        if (sub.slice.is_index and sub.slice.lower != null) {
                            try self.compileExpr(sub.slice.lower.?);
                            _ = try self.emit(.op_dup2, 0);
                            _ = try self.emit(.op_get_subscript, 0);
                            try self.compileExpr(aa.value);
                            try self.emitBinaryOp(aa.op);
                            _ = try self.emit(.op_rot_three, 0);
                            _ = try self.emit(.op_set_subscript, 0);
                        }
                    },
                    else => return error.InvalidAssignmentTarget,
                }
            },
            .if_stmt => |i| {
                try self.compileExpr(i.condition);
                const then_jump = try self.emit(.op_pop_jump_if_false, 0);
                try self.compileSuite(i.then_branch);

                var end_jumps: std.ArrayList(usize) = .empty;
                defer end_jumps.deinit(self.allocator);

                try end_jumps.append(self.allocator, try self.emit(.op_jump, 0));
                self.chunk.patchJump(then_jump, self.chunk.code.items.len);

                for (i.elif_branches) |branch| {
                    try self.compileExpr(branch.condition);
                    const elif_jump = try self.emit(.op_pop_jump_if_false, 0);
                    try self.compileSuite(branch.body);
                    try end_jumps.append(self.allocator, try self.emit(.op_jump, 0));
                    self.chunk.patchJump(elif_jump, self.chunk.code.items.len);
                }

                if (i.else_branch) |eb| {
                    try self.compileSuite(eb);
                }

                const post_if_ip = self.chunk.code.items.len;
                for (end_jumps.items) |jump_idx| {
                    self.chunk.patchJump(jump_idx, post_if_ip);
                }
            },
            .while_stmt => |w| {
                const loop_start = self.chunk.code.items.len;
                try self.compileExpr(w.condition);
                const exit_jump = try self.emit(.op_pop_jump_if_false, 0);

                var loop_ctx = LoopContext{
                    .start_ip = loop_start,
                    .break_jumps = .empty,
                    .is_for_loop = false,
                };
                defer loop_ctx.break_jumps.deinit(self.allocator);

                const prev_loop = self.current_loop;
                self.current_loop = &loop_ctx;
                defer self.current_loop = prev_loop;

                try self.compileSuite(w.body);
                _ = try self.emit(.op_jump, @intCast(loop_start));

                const loop_end = self.chunk.code.items.len;
                self.chunk.patchJump(exit_jump, loop_end);
                for (loop_ctx.break_jumps.items) |bj| {
                    self.chunk.patchJump(bj, loop_end);
                }

                if (w.else_branch) |eb| {
                    try self.compileSuite(eb);
                }
            },
            .for_stmt => |f| {
                try self.compileExpr(f.iter);
                _ = try self.emit(.op_get_iter, 0);

                const loop_start = self.chunk.code.items.len;
                const iter_jump = try self.emit(.op_for_iter, 0);

                var loop_ctx = LoopContext{
                    .start_ip = loop_start,
                    .break_jumps = .empty,
                    .is_for_loop = true,
                };
                defer loop_ctx.break_jumps.deinit(self.allocator);

                const prev_loop = self.current_loop;
                self.current_loop = &loop_ctx;
                defer self.current_loop = prev_loop;

                try self.compileAssignmentTarget(f.target);
                try self.compileSuite(f.body);
                _ = try self.emit(.op_jump, @intCast(loop_start));

                const loop_end = self.chunk.code.items.len;
                self.chunk.patchJump(iter_jump, loop_end);
                for (loop_ctx.break_jumps.items) |bj| {
                    self.chunk.patchJump(bj, loop_end);
                }

                if (f.else_branch) |eb| {
                    try self.compileSuite(eb);
                }
            },
            .return_stmt => |r| {
                if (r) |ret_expr| {
                    try self.compileExpr(ret_expr);
                } else {
                    _ = try self.emit(.op_none, 0);
                }
                _ = try self.emit(.op_return, 0);
            },
            .break_stmt => {
                if (self.current_loop) |loop| {
                    if (loop.is_for_loop) {
                        _ = try self.emit(.op_pop, 0);
                    }
                    const j = try self.emit(.op_jump, 0);
                    try loop.break_jumps.append(self.allocator, j);
                } else return error.SyntaxError;
            },
            .continue_stmt => {
                if (self.current_loop) |loop| {
                    _ = try self.emit(.op_jump, @intCast(loop.start_ip));
                } else return error.SyntaxError;
            },
            .pass_stmt => {},
            else => {},
        }
    }

    pub fn compileAssignmentTarget(self: *Compiler, target: *Expr) anyerror!void {
        switch (target.*) {
            .identifier => |id| {
                if (self.resolveLocal(id.name)) |slot| {
                    _ = try self.emit(.op_store_fast, slot);
                } else if (self.scope_depth > 0) {
                    const slot = try self.addLocal(id.name);
                    _ = try self.emit(.op_store_fast, slot);
                } else {
                    const name_idx = try self.chunk.addName(id.name);
                    _ = try self.emit(.op_store_global, name_idx);
                }
            },
            .attribute => |att| {
                try self.compileExpr(att.value);
                _ = try self.emit(.op_swap, 0);
                const name_idx = try self.chunk.addName(att.attr);
                _ = try self.emit(.op_set_attr, name_idx);
            },
            .subscript => |sub| {
                try self.compileExpr(sub.value);
                if (sub.slice.is_index and sub.slice.lower != null) {
                    try self.compileExpr(sub.slice.lower.?);
                    _ = try self.emit(.op_set_subscript, 0);
                }
            },
            .tuple_expr => |items| {
                _ = try self.emit(.op_unpack_tuple, @intCast(items.len));
                for (items) |it| {
                    try self.compileAssignmentTarget(it);
                }
            },
            else => return error.InvalidAssignmentTarget,
        }
    }

    pub fn compileExpr(self: *Compiler, expr: *Expr) anyerror!void {
        switch (expr.*) {
            .literal => |lit| {
                switch (lit) {
                    .none => _ = try self.emit(.op_none, 0),
                    .bool => |b| _ = try self.emit(if (b) .op_true else .op_false, 0),
                    else => {
                        const idx = try self.chunk.addConstant(lit);
                        _ = try self.emit(.op_const, idx);
                    },
                }
            },
            .identifier => |id| {
                if (self.resolveLocal(id.name)) |slot| {
                    _ = try self.emit(.op_load_fast, slot);
                } else {
                    const name_idx = try self.chunk.addName(id.name);
                    _ = try self.emit(.op_load_global, name_idx);
                }
            },
            .binary => |b| {
                try self.compileExpr(b.left);
                try self.compileExpr(b.right);
                try self.emitBinaryOp(b.op);
            },
            .unary => |u| {
                try self.compileExpr(u.expr);
                switch (u.op) {
                    .minus => _ = try self.emit(.op_neg, 0),
                    .not => _ = try self.emit(.op_not, 0),
                    .invert => _ = try self.emit(.op_invert, 0),
                    .plus => {},
                }
            },
            .compare => |cmp| {
                if (cmp.ops.len == 1) {
                    try self.compileExpr(cmp.left);
                    try self.compileExpr(cmp.rights[0]);
                    switch (cmp.ops[0]) {
                        .eq => _ = try self.emit(.op_eq, 0),
                        .ne => _ = try self.emit(.op_ne, 0),
                        .lt => _ = try self.emit(.op_lt, 0),
                        .le => _ = try self.emit(.op_le, 0),
                        .gt => _ = try self.emit(.op_gt, 0),
                        .ge => _ = try self.emit(.op_ge, 0),
                        .in => _ = try self.emit(.op_in, 0),
                        .not_in => _ = try self.emit(.op_not_in, 0),
                        .is => _ = try self.emit(.op_is, 0),
                        .is_not => _ = try self.emit(.op_is_not, 0),
                    }
                }
            },
            .bool_op => |bo| {
                if (bo.op == .op_and) {
                    var end_jumps: std.ArrayList(usize) = .empty;
                    defer end_jumps.deinit(self.allocator);

                    for (bo.values, 0..) |v, idx| {
                        try self.compileExpr(v);
                        if (idx < bo.values.len - 1) {
                            try end_jumps.append(self.allocator, try self.emit(.op_jump_if_false, 0));
                            _ = try self.emit(.op_pop, 0);
                        }
                    }
                    const end_ip = self.chunk.code.items.len;
                    for (end_jumps.items) |j| {
                        self.chunk.patchJump(j, end_ip);
                    }
                } else {
                    var end_jumps: std.ArrayList(usize) = .empty;
                    defer end_jumps.deinit(self.allocator);

                    for (bo.values, 0..) |v, idx| {
                        try self.compileExpr(v);
                        if (idx < bo.values.len - 1) {
                            try end_jumps.append(self.allocator, try self.emit(.op_jump_if_true, 0));
                            _ = try self.emit(.op_pop, 0);
                        }
                    }
                    const end_ip = self.chunk.code.items.len;
                    for (end_jumps.items) |j| {
                        self.chunk.patchJump(j, end_ip);
                    }
                }
            },
            .call => |c| {
                try self.compileExpr(c.callee);
                for (c.args) |a| {
                    try self.compileExpr(a);
                }
                _ = try self.emit(.op_call, @intCast(c.args.len));
            },
            .attribute => |att| {
                try self.compileExpr(att.value);
                const name_idx = try self.chunk.addName(att.attr);
                _ = try self.emit(.op_get_attr, name_idx);
            },
            .subscript => |sub| {
                try self.compileExpr(sub.value);
                if (sub.slice.is_index and sub.slice.lower != null) {
                    try self.compileExpr(sub.slice.lower.?);
                    _ = try self.emit(.op_get_subscript, 0);
                } else {
                    if (sub.slice.lower) |l| try self.compileExpr(l) else _ = try self.emit(.op_none, 0);
                    if (sub.slice.upper) |u| try self.compileExpr(u) else _ = try self.emit(.op_none, 0);
                    if (sub.slice.step) |s| try self.compileExpr(s) else _ = try self.emit(.op_none, 0);
                    _ = try self.emit(.op_get_slice, 0);
                }
            },
            .list_expr => |items| {
                for (items) |it| try self.compileExpr(it);
                _ = try self.emit(.op_build_list, @intCast(items.len));
            },
            .tuple_expr => |items| {
                for (items) |it| try self.compileExpr(it);
                _ = try self.emit(.op_build_tuple, @intCast(items.len));
            },
            .dict_expr => |d| {
                for (d.keys, 0..) |k, i| {
                    try self.compileExpr(k);
                    try self.compileExpr(d.values[i]);
                }
                _ = try self.emit(.op_build_dict, @intCast(d.keys.len));
            },
            .set_expr => |items| {
                for (items) |it| try self.compileExpr(it);
                _ = try self.emit(.op_build_set, @intCast(items.len));
            },
            .ternary => |ter| {
                try self.compileExpr(ter.condition);
                const false_jump = try self.emit(.op_pop_jump_if_false, 0);
                try self.compileExpr(ter.if_val);
                const end_jump = try self.emit(.op_jump, 0);
                self.chunk.patchJump(false_jump, self.chunk.code.items.len);
                try self.compileExpr(ter.else_val);
                self.chunk.patchJump(end_jump, self.chunk.code.items.len);
            },
            .f_string => |fs| {
                for (fs.parts) |p| {
                    try self.compileExpr(p);
                    _ = try self.emit(.op_format_value, 0);
                }
                _ = try self.emit(.op_build_string, @intCast(fs.parts.len));
            },
            .list_comp => |lc| {
                _ = try self.emit(.op_build_list, 0);
                try self.compileExpr(lc.iter);
                _ = try self.emit(.op_get_iter, 0);

                const loop_start = self.chunk.code.items.len;
                const iter_jump = try self.emit(.op_for_iter, 0);

                try self.compileAssignmentTarget(lc.target);

                if (lc.condition) |cond| {
                    try self.compileExpr(cond);
                    const skip_jump = try self.emit(.op_pop_jump_if_false, 0);
                    try self.compileExpr(lc.elt);
                    _ = try self.emit(.op_list_append, 0);
                    self.chunk.patchJump(skip_jump, self.chunk.code.items.len);
                } else {
                    try self.compileExpr(lc.elt);
                    _ = try self.emit(.op_list_append, 0);
                }

                _ = try self.emit(.op_jump, @intCast(loop_start));
                self.chunk.patchJump(iter_jump, self.chunk.code.items.len);
            },
            else => {},
        }
    }

    pub inline fn emitBinaryOp(self: *Compiler, op: BinaryOp) !void {
        switch (op) {
            .add => _ = try self.emit(.op_add, 0),
            .sub => _ = try self.emit(.op_sub, 0),
            .mul => _ = try self.emit(.op_mul, 0),
            .div => _ = try self.emit(.op_div, 0),
            .floor_div => _ = try self.emit(.op_floor_div, 0),
            .mod => _ = try self.emit(.op_mod, 0),
            .pow => _ = try self.emit(.op_pow, 0),
            .bit_and => _ = try self.emit(.op_bit_and, 0),
            .bit_or => _ = try self.emit(.op_bit_or, 0),
            .bit_xor => _ = try self.emit(.op_bit_xor, 0),
            .lshift => _ = try self.emit(.op_lshift, 0),
            .rshift => _ = try self.emit(.op_rshift, 0),
        }
    }
};
