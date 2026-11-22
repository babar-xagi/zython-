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
const PyFunction = value_mod.PyFunction;
const PyBuiltin = value_mod.PyBuiltin;
const PyClass = value_mod.PyClass;
const PyInstance = value_mod.PyInstance;
const PyBoundMethod = value_mod.PyBoundMethod;
const PyModule = value_mod.PyModule;
const PyBigInt = value_mod.PyBigInt;
const PyGenerator = value_mod.PyGenerator;
const PyCoroutine = value_mod.PyCoroutine;
const DictEntry = value_mod.DictEntry;
const ast_mod = @import("ast.zig");
const Expr = ast_mod.Expr;
const Stmt = ast_mod.Stmt;
const BinaryOp = ast_mod.BinaryOp;
const UnaryOp = ast_mod.UnaryOp;
const CompareOp = ast_mod.CompareOp;
const BoolOp = ast_mod.BoolOp;
const Param = ast_mod.Param;
const environment_mod = @import("environment.zig");
const Environment = environment_mod.Environment;
const builtins_mod = @import("builtins.zig");
const parser_mod = @import("parser.zig");
const Parser = parser_mod.Parser;
const bytecode_mod = @import("bytecode.zig");
const Chunk = bytecode_mod.Chunk;
const compiler_mod = @import("compiler.zig");
const Compiler = compiler_mod.Compiler;
const vm_mod = @import("vm.zig");
const VM = vm_mod.VM;
const jit_mod = @import("jit.zig");
const JitEngine = jit_mod.JitEngine;

pub const Interpreter = struct {
    allocator: Allocator,
    builtins_env: *Environment,
    global_env: *Environment,
    modules: std.StringHashMap(Value),
    cli_args: []const [:0]const u8,

    // High-performance environment pooling for 0-allocation function execution
    env_pool: [2048]*Environment = undefined,
    env_pool_top: usize = 0,
    return_value: Value = .none,
    current_yield_gen: ?*PyGenerator = null,
    vm: VM = undefined,
    jit: JitEngine = undefined,

    pub fn init(allocator: Allocator, cli_args: []const [:0]const u8) !*Interpreter {
        const self = try allocator.create(Interpreter);

        // Separate builtins environment so global_env has completely clean fast_slots
        const b_env = try Environment.init(allocator, null);
        try builtins_mod.populateBuiltins(allocator, b_env);

        const g_env = try Environment.init(allocator, b_env);

        self.* = .{
            .allocator = allocator,
            .builtins_env = b_env,
            .global_env = g_env,
            .modules = std.StringHashMap(Value).init(allocator),
            .cli_args = cli_args,
            .env_pool_top = 0,
            .return_value = .none,
            .vm = undefined,
            .jit = undefined,
        };
        self.vm = VM.init(allocator, self);
        self.jit = JitEngine.init(allocator);

        // Preallocate pool of environments
        var pi: usize = 0;
        while (pi < 1024) : (pi += 1) {
            self.env_pool[pi] = try Environment.init(allocator, null);
        }
        self.env_pool_top = 1024;

        // Preload standard modules
        const mod_math = try builtins_mod.makeMathModule(allocator);
        try self.modules.put("math", mod_math);

        const mod_time = try builtins_mod.makeTimeModule(allocator);
        try self.modules.put("time", mod_time);

        const mod_sys = try builtins_mod.makeSysModule(allocator, cli_args);
        try self.modules.put("sys", mod_sys);

        const mod_asyncio = try builtins_mod.makeAsyncioModule(allocator);
        try self.modules.put("asyncio", mod_asyncio);

        return self;
    }

    pub inline fn acquireEnv(self: *Interpreter, parent: ?*Environment) *Environment {
        if (self.env_pool_top > 0) {
            self.env_pool_top -= 1;
            const env = self.env_pool[self.env_pool_top];
            env.reset(parent);
            return env;
        }
        return Environment.init(self.allocator, parent) catch unreachable;
    }

    pub inline fn releaseEnv(self: *Interpreter, env: *Environment) void {
        if (!env.is_escaped and self.env_pool_top < self.env_pool.len) {
            self.env_pool[self.env_pool_top] = env;
            self.env_pool_top += 1;
        }
    }

    pub fn evalSource(self: *Interpreter, source: []const u8) anyerror!Value {
        var parser = try Parser.init(self.allocator, source);
        defer parser.deinit();

        const stmts = try parser.parseModule();
        return self.evalSuite(stmts, self.global_env);
    }

    pub fn evalSuite(self: *Interpreter, stmts: []const Stmt, env: *Environment) anyerror!Value {
        var last_val: Value = .none;
        for (stmts) |stmt| {
            const res = try self.evalStmt(stmt, env);
            switch (res) {
                .return_flow, .break_flow, .continue_flow => return res,
                else => {
                    last_val = res;
                },
            }
        }
        return last_val;
    }

    pub fn hasYield(stmts: []const Stmt) bool {
        for (stmts) |stmt| {
            if (stmtHasYield(stmt)) return true;
        }
        return false;
    }

    fn stmtHasYield(stmt: Stmt) bool {
        switch (stmt) {
            .expr_stmt => |e| return exprHasYield(e),
            .assign => |a| return exprHasYield(a.value),
            .aug_assign => |a| return exprHasYield(a.value),
            .return_stmt => |opt_e| return if (opt_e) |e| exprHasYield(e) else false,
            .if_stmt => |s| {
                if (exprHasYield(s.condition)) return true;
                if (hasYield(s.then_branch)) return true;
                for (s.elif_branches) |el| {
                    if (exprHasYield(el.condition) or hasYield(el.body)) return true;
                }
                if (s.else_branch) |eb| {
                    if (hasYield(eb)) return true;
                }
                return false;
            },
            .while_stmt => |s| {
                if (exprHasYield(s.condition)) return true;
                if (hasYield(s.body)) return true;
                if (s.else_branch) |eb| {
                    if (hasYield(eb)) return true;
                }
                return false;
            },
            .for_stmt => |s| {
                if (exprHasYield(s.iter)) return true;
                if (hasYield(s.body)) return true;
                if (s.else_branch) |eb| {
                    if (hasYield(eb)) return true;
                }
                return false;
            },
            .with_stmt => |w| {
                if (exprHasYield(w.context_expr)) return true;
                if (hasYield(w.body)) return true;
                return false;
            },
            .try_stmt => |t| {
                if (hasYield(t.body)) return true;
                for (t.handlers) |h| {
                    if (hasYield(h.body)) return true;
                }
                if (t.else_branch) |eb| {
                    if (hasYield(eb)) return true;
                }
                if (t.finally_branch) |fb| {
                    if (hasYield(fb)) return true;
                }
                return false;
            },
            .assert_stmt => |a| {
                if (exprHasYield(a.condition)) return true;
                if (a.message) |m| return exprHasYield(m);
                return false;
            },
            .def_stmt, .class_stmt, .break_stmt, .continue_stmt, .pass_stmt, .import_stmt, .import_from_stmt, .raise_stmt, .global_stmt => return false,
        }
    }

    fn exprHasYield(expr: *Expr) bool {
        switch (expr.*) {
            .yield_expr => return true,
            .await_expr => |a| return exprHasYield(a),
            .binary => |b| return exprHasYield(b.left) or exprHasYield(b.right),
            .unary => |u| return exprHasYield(u.expr),
            .compare => |cmp| {
                if (exprHasYield(cmp.left)) return true;
                for (cmp.rights) |r| {
                    if (exprHasYield(r)) return true;
                }
                return false;
            },
            .bool_op => |bo| {
                for (bo.values) |v| {
                    if (exprHasYield(v)) return true;
                }
                return false;
            },
            .call => |c| {
                if (exprHasYield(c.callee)) return true;
                for (c.args) |a| {
                    if (exprHasYield(a)) return true;
                }
                for (c.kwargs) |kw| {
                    if (exprHasYield(kw.value)) return true;
                }
                return false;
            },
            .attribute => |a| return exprHasYield(a.value),
            .subscript => |s| return exprHasYield(s.value),
            .list_expr => |items| {
                for (items) |it| {
                    if (exprHasYield(it)) return true;
                }
                return false;
            },
            .tuple_expr => |items| {
                for (items) |it| {
                    if (exprHasYield(it)) return true;
                }
                return false;
            },
            .dict_expr => |d| {
                for (d.keys) |k| {
                    if (exprHasYield(k)) return true;
                }
                for (d.values) |v| {
                    if (exprHasYield(v)) return true;
                }
                return false;
            },
            .set_expr => |items| {
                for (items) |it| {
                    if (exprHasYield(it)) return true;
                }
                return false;
            },
            .ternary => |t| return exprHasYield(t.if_val) or exprHasYield(t.condition) or exprHasYield(t.else_val),
            .list_comp => |lc| return exprHasYield(lc.elt) or exprHasYield(lc.iter),
            .literal, .identifier, .lambda, .f_string => return false,
        }
    }

    pub fn evalStmt(self: *Interpreter, stmt: Stmt, env: *Environment) anyerror!Value {
        switch (stmt) {
            .expr_stmt => |e| {
                return self.evalExpr(e, env);
            },
            .assign => |a| {
                const val = try self.evalExpr(a.value, env);
                for (a.targets) |target| {
                    try self.assignTarget(target, val, env);
                }
                return .none;
            },
            .aug_assign => |aa| {
                if (aa.target.* == .identifier) {
                    if (env.getSlotPtr(aa.target.identifier.name)) |slot| {
                        const rhs = try self.evalExpr(aa.value, env);
                        if (slot.* == .int and rhs == .int) {
                            switch (aa.op) {
                                .add => {
                                    slot.*.int += rhs.int;
                                    return .none;
                                },
                                .sub => {
                                    slot.*.int -= rhs.int;
                                    return .none;
                                },
                                .mul => {
                                    slot.*.int *= rhs.int;
                                    return .none;
                                },
                                .floor_div => {
                                    if (rhs.int == 0) return error.ZeroDivisionError;
                                    slot.*.int = @divFloor(slot.*.int, rhs.int);
                                    return .none;
                                },
                                .mod => {
                                    if (rhs.int == 0) return error.ZeroDivisionError;
                                    slot.*.int = @mod(slot.*.int, rhs.int);
                                    return .none;
                                },
                                .bit_and => {
                                    slot.*.int &= rhs.int;
                                    return .none;
                                },
                                .bit_or => {
                                    slot.*.int |= rhs.int;
                                    return .none;
                                },
                                .bit_xor => {
                                    slot.*.int ^= rhs.int;
                                    return .none;
                                },
                                .lshift => {
                                    if (rhs.int >= 0) {
                                        slot.*.int <<= @intCast(rhs.int & 63);
                                        return .none;
                                    }
                                    return error.TypeError;
                                },
                                .rshift => {
                                    if (rhs.int >= 0) {
                                        slot.*.int >>= @intCast(rhs.int & 63);
                                        return .none;
                                    }
                                    return error.TypeError;
                                },
                                else => {},
                            }
                        }
                        slot.* = try self.evalBinaryOp(slot.*, aa.op, rhs);
                        return .none;
                    }
                } else if (aa.target.* == .attribute) {
                    const att = &aa.target.attribute;
                    const obj = try self.evalExpr(att.value, env);
                    if (obj == .instance) {
                        const ins = obj.instance;
                        var slot_ptr: ?*Value = null;
                        if (att.cached_slot < ins.inline_count) {
                            const s = &ins.inline_slots[att.cached_slot];
                            if (s.name.ptr == att.attr.ptr or std.mem.eql(u8, s.name, att.attr)) {
                                slot_ptr = &s.val;
                            }
                        }
                        if (slot_ptr == null) {
                            var i: u8 = 0;
                            while (i < ins.inline_count) : (i += 1) {
                                if (ins.inline_slots[i].name.ptr == att.attr.ptr or std.mem.eql(u8, ins.inline_slots[i].name, att.attr)) {
                                    att.cached_slot = i;
                                    slot_ptr = &ins.inline_slots[i].val;
                                    break;
                                }
                            }
                        }
                        if (slot_ptr) |slot| {
                            const rhs = try self.evalExpr(aa.value, env);
                            if (slot.* == .int and rhs == .int) {
                                switch (aa.op) {
                                    .add => {
                                        slot.*.int += rhs.int;
                                        return .none;
                                    },
                                    .sub => {
                                        slot.*.int -= rhs.int;
                                        return .none;
                                    },
                                    .mul => {
                                        slot.*.int *= rhs.int;
                                        return .none;
                                    },
                                    .floor_div => {
                                        if (rhs.int == 0) return error.ZeroDivisionError;
                                        slot.*.int = @divFloor(slot.*.int, rhs.int);
                                        return .none;
                                    },
                                    .mod => {
                                        if (rhs.int == 0) return error.ZeroDivisionError;
                                        slot.*.int = @mod(slot.*.int, rhs.int);
                                        return .none;
                                    },
                                    .bit_and => {
                                        slot.*.int &= rhs.int;
                                        return .none;
                                    },
                                    .bit_or => {
                                        slot.*.int |= rhs.int;
                                        return .none;
                                    },
                                    .bit_xor => {
                                        slot.*.int ^= rhs.int;
                                        return .none;
                                    },
                                    .lshift => {
                                        if (rhs.int >= 0) {
                                            slot.*.int <<= @intCast(rhs.int & 63);
                                            return .none;
                                        }
                                        return error.TypeError;
                                    },
                                    .rshift => {
                                        if (rhs.int >= 0) {
                                            slot.*.int >>= @intCast(rhs.int & 63);
                                            return .none;
                                        }
                                        return error.TypeError;
                                    },
                                    else => {},
                                }
                            }
                            slot.* = try self.evalBinaryOp(slot.*, aa.op, rhs);
                            return .none;
                        }
                    }
                    const rhs = try self.evalExpr(aa.value, env);
                    const cur = try self.evalExpr(aa.target, env);
                    const updated = try self.evalBinaryOp(cur, aa.op, rhs);
                    try self.assignTarget(aa.target, updated, env);
                    return .none;
                }
                const rhs = try self.evalExpr(aa.value, env);
                const cur = try self.evalExpr(aa.target, env);
                const updated = try self.evalBinaryOp(cur, aa.op, rhs);
                try self.assignTarget(aa.target, updated, env);
                return .none;
            },
            .if_stmt => |i| {
                const cond_val = try self.evalExpr(i.condition, env);
                if (cond_val.isTruthy()) {
                    return self.evalSuite(i.then_branch, env);
                }
                for (i.elif_branches) |branch| {
                    const elif_cond = try self.evalExpr(branch.condition, env);
                    if (elif_cond.isTruthy()) {
                        return self.evalSuite(branch.body, env);
                    }
                }
                if (i.else_branch) |eb| {
                    return self.evalSuite(eb, env);
                }
                return .none;
            },
            .while_stmt => |w| {
                // High-performance loop specialization: while i < limit: s += i; i += 1
                if (w.condition.* == .compare and w.condition.compare.ops.len == 1 and w.condition.compare.ops[0] == .lt) {
                    const left_expr = w.condition.compare.left;
                    const right_expr = w.condition.compare.rights[0];
                    if (left_expr.* == .identifier) {
                        const i_name = left_expr.identifier.name;
                        const i_slot = env.getSlotPtr(i_name);
                        const limit_val = try self.evalExpr(right_expr, env);
                        if (i_slot != null and i_slot.?.* == .int and limit_val == .int) {
                            if (w.body.len == 2 and w.body[0] == .aug_assign and w.body[1] == .aug_assign) {
                                const a0 = w.body[0].aug_assign;
                                const a1 = w.body[1].aug_assign;
                                if (a1.target.* == .identifier and std.mem.eql(u8, a1.target.identifier.name, i_name) and
                                    a1.op == .add and a1.value.* == .literal and a1.value.literal == .int and a1.value.literal.int == 1)
                                {
                                    if (a0.target.* == .identifier and a0.op == .add) {
                                        const s_name = a0.target.identifier.name;
                                        const s_slot = env.getSlotPtr(s_name);
                                        if (s_slot != null and s_slot.?.* == .int) {
                                            var cur_i = i_slot.?.*.int;
                                            var cur_s = s_slot.?.*.int;
                                            const limit = limit_val.int;
                                            if (a0.value.* == .identifier and std.mem.eql(u8, a0.value.identifier.name, i_name)) {
                                                while (cur_i < limit) : (cur_i += 1) {
                                                    cur_s += cur_i;
                                                }
                                                i_slot.?.*.int = cur_i;
                                                s_slot.?.*.int = cur_s;
                                                return .none;
                                            } else if (a0.value.* == .literal and a0.value.literal == .int) {
                                                const inc = a0.value.literal.int;
                                                while (cur_i < limit) : (cur_i += 1) {
                                                    cur_s += inc;
                                                }
                                                i_slot.?.*.int = cur_i;
                                                s_slot.?.*.int = cur_s;
                                                return .none;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                var broke = false;
                while (true) {
                    const cond = try self.evalExpr(w.condition, env);
                    if (!cond.isTruthy()) break;

                    const res = try self.evalSuite(w.body, env);
                    switch (res) {
                        .break_flow => {
                            broke = true;
                            break;
                        },
                        .continue_flow => continue,
                        .return_flow => return res,
                        else => {},
                    }
                }
                if (!broke and w.else_branch != null) {
                    return self.evalSuite(w.else_branch.?, env);
                }
                return .none;
            },
            .for_stmt => |f| {
                const iter_val = try self.evalExpr(f.iter, env);
                var broke = false;

                switch (iter_val) {
                    .range => |r| {
                        const len = r.length();
                        const target_ident: ?[]const u8 = if (f.target.* == .identifier) f.target.identifier.name else null;
                        var cached_slot: ?*Value = if (target_ident) |ti| env.getSlotPtr(ti) else null;
                        if (cached_slot == null and target_ident != null) {
                            try env.set(target_ident.?, Value.makeInt(0));
                            cached_slot = env.getSlotPtr(target_ident.?);
                        }

                        // High-performance loop specialization: for i in range(...): s += i or s += const
                        if (f.body.len == 1 and f.body[0] == .aug_assign and f.body[0].aug_assign.op == .add and target_ident != null) {
                            const aa = f.body[0].aug_assign;
                            if (aa.target.* == .identifier) {
                                const acc_name = aa.target.identifier.name;
                                var acc_slot = env.getSlotPtr(acc_name);
                                if (acc_slot == null) {
                                    try env.set(acc_name, Value.makeInt(0));
                                    acc_slot = env.getSlotPtr(acc_name);
                                }
                                if (acc_slot != null and acc_slot.?.* == .int) {
                                    if (aa.value.* == .identifier and std.mem.eql(u8, aa.value.identifier.name, target_ident.?)) {
                                        // Specialization: s += i
                                        var acc = acc_slot.?.*.int;
                                        var idx: usize = 0;
                                        while (idx < len) : (idx += 1) {
                                            acc += r.start + @as(i64, @intCast(idx)) * r.step;
                                        }
                                        acc_slot.?.*.int = acc;
                                        if (cached_slot) |cs| {
                                            if (len > 0) cs.*.int = r.start + @as(i64, @intCast(len - 1)) * r.step;
                                        }
                                        return .none;
                                    } else if (aa.value.* == .literal and aa.value.literal == .int) {
                                        // Specialization: s += constant
                                        acc_slot.?.*.int += aa.value.literal.int * @as(i64, @intCast(len));
                                        if (cached_slot) |cs| {
                                            if (len > 0) cs.*.int = r.start + @as(i64, @intCast(len - 1)) * r.step;
                                        }
                                        return .none;
                                    }
                                }
                            }
                        }

                        var idx: usize = 0;
                        while (idx < len) : (idx += 1) {
                            const val_int = r.start + @as(i64, @intCast(idx)) * r.step;
                            if (cached_slot) |slot| {
                                slot.* = Value.makeInt(val_int);
                            } else {
                                try self.assignTarget(f.target, Value.makeInt(val_int), env);
                            }
                            const res = try self.evalSuite(f.body, env);
                            switch (res) {
                                .break_flow => {
                                    broke = true;
                                    break;
                                },
                                .continue_flow => continue,
                                .return_flow => return res,
                                else => {},
                            }
                        }
                    },
                    .list => |l| {
                        const target_ident: ?[]const u8 = if (f.target.* == .identifier) f.target.identifier.name else null;
                        var cached_slot: ?*Value = if (target_ident) |ti| env.getSlotPtr(ti) else null;
                        if (cached_slot == null and target_ident != null) {
                            try env.set(target_ident.?, .none);
                            cached_slot = env.getSlotPtr(target_ident.?);
                        }
                        for (l.items.items) |it| {
                            if (cached_slot) |slot| {
                                slot.* = it;
                            } else {
                                try self.assignTarget(f.target, it, env);
                            }
                            const res = try self.evalSuite(f.body, env);
                            switch (res) {
                                .break_flow => {
                                    broke = true;
                                    break;
                                },
                                .continue_flow => continue,
                                .return_flow => return res,
                                else => {},
                            }
                        }
                    },
                    .tuple => |t| {
                        const target_ident: ?[]const u8 = if (f.target.* == .identifier) f.target.identifier.name else null;
                        var cached_slot: ?*Value = if (target_ident) |ti| env.getSlotPtr(ti) else null;
                        if (cached_slot == null and target_ident != null) {
                            try env.set(target_ident.?, .none);
                            cached_slot = env.getSlotPtr(target_ident.?);
                        }
                        for (t.items) |it| {
                            if (cached_slot) |slot| {
                                slot.* = it;
                            } else {
                                try self.assignTarget(f.target, it, env);
                            }
                            const res = try self.evalSuite(f.body, env);
                            switch (res) {
                                .break_flow => {
                                    broke = true;
                                    break;
                                },
                                .continue_flow => continue,
                                .return_flow => return res,
                                else => {},
                            }
                        }
                    },
                    .set => |s| {
                        const target_ident: ?[]const u8 = if (f.target.* == .identifier) f.target.identifier.name else null;
                        var cached_slot: ?*Value = if (target_ident) |ti| env.getSlotPtr(ti) else null;
                        if (cached_slot == null and target_ident != null) {
                            try env.set(target_ident.?, .none);
                            cached_slot = env.getSlotPtr(target_ident.?);
                        }
                        for (s.items.items) |it| {
                            if (cached_slot) |slot| {
                                slot.* = it;
                            } else {
                                try self.assignTarget(f.target, it, env);
                            }
                            const res = try self.evalSuite(f.body, env);
                            switch (res) {
                                .break_flow => {
                                    broke = true;
                                    break;
                                },
                                .continue_flow => continue,
                                .return_flow => return res,
                                else => {},
                            }
                        }
                    },
                    .string => |s| {
                        for (s.bytes) |b| {
                            const cs = try self.allocator.alloc(u8, 1);
                            cs[0] = b;
                            const char_val = try Value.makeString(self.allocator, cs);
                            try self.assignTarget(f.target, char_val, env);
                            const res = try self.evalSuite(f.body, env);
                            switch (res) {
                                .break_flow => {
                                    broke = true;
                                    break;
                                },
                                .continue_flow => continue,
                                .return_flow => return res,
                                else => {},
                            }
                        }
                    },
                    .dict => |d| {
                        for (d.entries.items) |entry| {
                            try self.assignTarget(f.target, entry.key, env);
                            const res = try self.evalSuite(f.body, env);
                            switch (res) {
                                .break_flow => {
                                    broke = true;
                                    break;
                                },
                                .continue_flow => continue,
                                .return_flow => return res,
                                else => {},
                            }
                        }
                    },
                    .generator => |g| {
                        const target_ident: ?[]const u8 = if (f.target.* == .identifier) f.target.identifier.name else null;
                        var cached_slot: ?*Value = if (target_ident) |ti| env.getSlotPtr(ti) else null;
                        if (cached_slot == null and target_ident != null) {
                            try env.set(target_ident.?, .none);
                            cached_slot = env.getSlotPtr(target_ident.?);
                        }
                        while (g.next()) |it| {
                            if (cached_slot) |slot| {
                                slot.* = it;
                            } else {
                                try self.assignTarget(f.target, it, env);
                            }
                            const res = try self.evalSuite(f.body, env);
                            switch (res) {
                                .break_flow => {
                                    broke = true;
                                    break;
                                },
                                .continue_flow => continue,
                                .return_flow => return res,
                                else => {},
                            }
                        }
                    },
                    .iterator => |it| {
                        const target_ident: ?[]const u8 = if (f.target.* == .identifier) f.target.identifier.name else null;
                        var cached_slot: ?*Value = if (target_ident) |ti| env.getSlotPtr(ti) else null;
                        if (cached_slot == null and target_ident != null) {
                            try env.set(target_ident.?, .none);
                            cached_slot = env.getSlotPtr(target_ident.?);
                        }
                        while (it.next(self.allocator)) |item| {
                            if (cached_slot) |slot| {
                                slot.* = item;
                            } else {
                                try self.assignTarget(f.target, item, env);
                            }
                            const res = try self.evalSuite(f.body, env);
                            switch (res) {
                                .break_flow => {
                                    broke = true;
                                    break;
                                },
                                .continue_flow => continue,
                                .return_flow => return res,
                                else => {},
                            }
                        }
                    },
                    else => return error.TypeError,
                }

                if (!broke and f.else_branch != null) {
                    return self.evalSuite(f.else_branch.?, env);
                }
                return .none;
            },
            .def_stmt => |d| {
                var p_names = try self.allocator.alloc([]const u8, d.params.len);
                var defaults = try self.allocator.alloc(Value, d.params.len);
                var vararg: ?[]const u8 = null;
                var kwarg: ?[]const u8 = null;

                for (d.params, 0..) |p, i| {
                    p_names[i] = p.name;
                    defaults[i] = if (p.default) |def_expr|
                        try self.evalExpr(def_expr, env)
                    else
                        .none;
                    if (p.is_vararg) vararg = p.name;
                    if (p.is_kwarg) kwarg = p.name;
                }

                env.markEscaped();
                const is_gen = hasYield(d.body);
                const fn_obj = try self.allocator.create(PyFunction);
                fn_obj.* = .{
                    .name = d.name,
                    .param_names = p_names,
                    .defaults = defaults,
                    .vararg = vararg,
                    .kwarg = kwarg,
                    .body_opaque = @ptrCast(d.body.ptr),
                    .body_len = d.body.len,
                    .closure_env = @ptrCast(env),
                    .chunk = null,
                    .is_generator = is_gen,
                    .is_async = d.is_async,
                };

                // Compile function to Bytecode Chunk for VM execution!
                if (vararg == null and kwarg == null and !is_gen and !d.is_async) {
                    const chunk_ptr = try self.allocator.create(Chunk);
                    chunk_ptr.* = Chunk.init(self.allocator);
                    var comp = Compiler.initFunction(self.allocator, chunk_ptr);

                    var compile_ok = true;
                    for (p_names) |pn| {
                        _ = comp.addLocal(pn) catch {
                            compile_ok = false;
                            break;
                        };
                    }

                    if (compile_ok) {
                        if (comp.compileSuite(d.body)) |_| {
                            _ = comp.emit(.op_none, 0) catch {};
                            _ = comp.emit(.op_return, 0) catch {};
                            comp.chunk.num_locals = comp.local_count;
                            fn_obj.chunk = @ptrCast(chunk_ptr);
                        } else |_| {
                            chunk_ptr.deinit();
                            self.allocator.destroy(chunk_ptr);
                            fn_obj.chunk = null;
                        }
                    } else {
                        chunk_ptr.deinit();
                        self.allocator.destroy(chunk_ptr);
                        fn_obj.chunk = null;
                    }
                }

                var fn_val = Value{ .function = fn_obj };
                if (d.decorators.len > 0) {
                    var i: usize = d.decorators.len;
                    while (i > 0) {
                        i -= 1;
                        const dec_fn = try self.evalExpr(d.decorators[i], env);
                        const wrap_args = [_]Value{fn_val};
                        fn_val = try self.callValue(dec_fn, &wrap_args, &.{});
                    }
                }
                try env.set(d.name, fn_val);
                return .none;
            },
            .class_stmt => |c| {
                var base_classes: std.ArrayList(*PyClass) = .empty;
                for (c.bases) |base_expr| {
                    const base_val = try self.evalExpr(base_expr, env);
                    if (base_val == .class) {
                        try base_classes.append(self.allocator, base_val.class);
                    }
                }

                const cls = try PyClass.init(self.allocator, c.name, base_classes.items);
                const class_env = try Environment.init(self.allocator, env);
                _ = try self.evalSuite(c.body, class_env);

                var i: u8 = 0;
                while (i < class_env.fast_count) : (i += 1) {
                    try cls.attributes.put(class_env.fast_slots[i].name, class_env.fast_slots[i].val);
                }
                if (class_env.bindings) |*b| {
                    var it = b.iterator();
                    while (it.next()) |entry| {
                        try cls.attributes.put(entry.key_ptr.*, entry.value_ptr.*);
                    }
                }

                const cls_val = Value{ .class = cls };
                try env.set(c.name, cls_val);
                return .none;
            },
            .return_stmt => |r| {
                self.return_value = if (r) |ret_expr| try self.evalExpr(ret_expr, env) else Value.none;
                return .return_flow;
            },
            .break_stmt => return .break_flow,
            .continue_stmt => return .continue_flow,
            .pass_stmt => return .none,
            .raise_stmt => |r| {
                if (r) |re| {
                    const val = try self.evalExpr(re, env);
                    const s = try val.str(self.allocator);
                    std.debug.print("Exception raised: {s}\n", .{s});
                }
                return error.PythonException;
            },
            .try_stmt => |t| {
                var exc_raised = false;
                var exc_err: anyerror = undefined;
                _ = self.evalSuite(t.body, env) catch |err| {
                    exc_raised = true;
                    exc_err = err;
                };

                var result: Value = .none;

                if (exc_raised and t.handlers.len > 0) {
                    var handled = false;
                    for (t.handlers) |h| {
                        var matches = false;
                        if (h.exc_type) |et| {
                            const err_name = @errorName(exc_err);
                            if (et.* == .identifier) {
                                const type_name = et.identifier.name;
                                if (std.mem.eql(u8, type_name, "Exception") or
                                    std.mem.eql(u8, type_name, "BaseException") or
                                    std.mem.eql(u8, type_name, err_name))
                                {
                                    matches = true;
                                }
                            } else {
                                matches = true;
                            }
                        } else {
                            matches = true;
                        }

                        if (matches) {
                            if (h.name) |name| {
                                const exc_str = try Value.makeString(self.allocator, @errorName(exc_err));
                                try env.set(name, exc_str);
                            }
                            result = try self.evalSuite(h.body, env);
                            handled = true;
                            break;
                        }
                    }
                    if (!handled) return exc_err;
                } else if (!exc_raised and t.else_branch != null) {
                    result = try self.evalSuite(t.else_branch.?, env);
                } else if (exc_raised and t.handlers.len == 0) {
                    return exc_err;
                }

                if (t.finally_branch) |fb| {
                    _ = try self.evalSuite(fb, env);
                }
                return result;
            },
            .import_stmt => |im| {
                if (self.modules.get(im.module_name)) |mod_val| {
                    const bind_name = im.as_name orelse im.module_name;
                    try env.set(bind_name, mod_val);
                    return .none;
                }
                return error.ImportError;
            },
            .import_from_stmt => |ifm| {
                if (self.modules.get(ifm.module_name)) |mod_val| {
                    if (mod_val == .module) {
                        for (ifm.names, 0..) |n, idx| {
                            const as_n = ifm.as_names[idx] orelse n;
                            if (mod_val.module.attributes.get(n)) |attr_val| {
                                try env.set(as_n, attr_val);
                            } else {
                                return error.ImportError;
                            }
                        }
                    }
                    return .none;
                }
                return error.ImportError;
            },
            .global_stmt => |names| {
                for (names) |n| {
                    try env.markGlobal(n);
                }
                return .none;
            },
            .assert_stmt => |a| {
                const cond = try self.evalExpr(a.condition, env);
                if (!cond.isTruthy()) {
                    if (a.message) |msg_expr| {
                        const msg = try self.evalExpr(msg_expr, env);
                        const s = try msg.str(self.allocator);
                        std.debug.print("AssertionError: {s}\n", .{s});
                    } else {
                        std.debug.print("AssertionError\n", .{});
                    }
                    return error.AssertionError;
                }
                return .none;
            },
            .with_stmt => |w| {
                const ctx_val = try self.evalExpr(w.context_expr, env);
                var enter_res: Value = ctx_val;
                if (self.evalAttribute(ctx_val, "__enter__")) |enter_fn| {
                    enter_res = try self.callValue(enter_fn, &.{}, &.{});
                } else |_| {}

                if (w.optional_vars) |target| {
                    try self.assignTarget(target, enter_res, env);
                }

                var exc_caught: ?anyerror = null;
                const body_res = self.evalSuite(w.body, env) catch |err| blk: {
                    exc_caught = err;
                    break :blk Value.none;
                };

                if (self.evalAttribute(ctx_val, "__exit__")) |exit_fn| {
                    const none_val = Value.makeNone();
                    const exit_args = [_]Value{ none_val, none_val, none_val };
                    _ = self.callValue(exit_fn, &exit_args, &.{}) catch {};
                } else |_| {}

                if (exc_caught) |err| return err;
                return body_res;
            },
        }
    }

    fn assignTarget(self: *Interpreter, target: *Expr, val: Value, env: *Environment) anyerror!void {
        switch (target.*) {
            .identifier => |*id| {
                if (id.slot_idx < env.fast_count) {
                    const slot = &env.fast_slots[id.slot_idx];
                    if (slot.name.ptr == id.name.ptr or std.mem.eql(u8, slot.name, id.name)) {
                        slot.val = val;
                        return;
                    }
                }
                var i: u8 = 0;
                while (i < env.fast_count) : (i += 1) {
                    if (id.name.ptr == env.fast_slots[i].name.ptr or std.mem.eql(u8, env.fast_slots[i].name, id.name)) {
                        id.slot_idx = i;
                        env.fast_slots[i].val = val;
                        return;
                    }
                }
                try env.set(id.name, val);
            },
            .attribute => |*att| {
                const obj = try self.evalExpr(att.value, env);
                if (obj == .instance) {
                    const ins = obj.instance;
                    if (att.cached_slot < ins.inline_count) {
                        const s = &ins.inline_slots[att.cached_slot];
                        if (s.name.ptr == att.attr.ptr or std.mem.eql(u8, s.name, att.attr)) {
                            s.val = val;
                            return;
                        }
                    }
                    var i: u8 = 0;
                    while (i < ins.inline_count) : (i += 1) {
                        if (ins.inline_slots[i].name.ptr == att.attr.ptr or std.mem.eql(u8, ins.inline_slots[i].name, att.attr)) {
                            att.cached_slot = i;
                            ins.inline_slots[i].val = val;
                            return;
                        }
                    }
                    try ins.setAttr(self.allocator, att.attr, val);
                } else if (obj == .module) {
                    try obj.module.attributes.put(att.attr, val);
                } else {
                    return error.AttributeError;
                }
            },
            .subscript => |sub| {
                const obj = try self.evalExpr(sub.value, env);
                if (sub.slice.is_index and sub.slice.lower != null) {
                    const key_val = try self.evalExpr(sub.slice.lower.?, env);
                    if (obj == .list) {
                        if (key_val != .int) return error.TypeError;
                        var idx = key_val.int;
                        const len: i64 = @intCast(obj.list.items.items.len);
                        if (idx < 0) idx += len;
                        if (idx < 0 or idx >= len) return error.IndexError;
                        obj.list.items.items[@intCast(idx)] = val;
                    } else if (obj == .dict) {
                        try obj.dict.put(self.allocator, key_val, val);
                    } else {
                        return error.TypeError;
                    }
                }
            },
            .tuple_expr => |targets| {
                var items: []const Value = &[_]Value{};
                if (val == .tuple) {
                    items = val.tuple.items;
                } else if (val == .list) {
                    items = val.list.items.items;
                }
                if (items.len != targets.len) return error.ValueError;
                for (targets, 0..) |t, idx| {
                    try self.assignTarget(t, items[idx], env);
                }
            },
            else => return error.InvalidAssignmentTarget,
        }
    }

    pub fn evalExpr(self: *Interpreter, expr: *Expr, env: *Environment) anyerror!Value {
        switch (expr.*) {
            .literal => |l| return l,
            .identifier => |*id| {
                if (id.slot_idx < env.fast_count) {
                    const slot = &env.fast_slots[id.slot_idx];
                    if (slot.name.ptr == id.name.ptr or std.mem.eql(u8, slot.name, id.name)) {
                        return slot.val;
                    }
                }
                if (id.cached_val) |cv| {
                    return cv;
                }
                var i: u8 = 0;
                while (i < env.fast_count) : (i += 1) {
                    if (id.name.ptr == env.fast_slots[i].name.ptr or std.mem.eql(u8, env.fast_slots[i].name, id.name)) {
                        id.slot_idx = i;
                        return env.fast_slots[i].val;
                    }
                }
                if (env.get(id.name)) |v| {
                    if (self.builtins_env.get(id.name) != null) {
                        id.cached_val = v;
                    }
                    return v;
                }
                std.debug.print("NameError: name '{s}' is not defined\n", .{id.name});
                return error.NameError;
            },
            .binary => |b| {
                const left = try self.evalExpr(b.left, env);
                const right = try self.evalExpr(b.right, env);
                if (@as(std.meta.Tag(Value), left) == .int and @as(std.meta.Tag(Value), right) == .int) {
                    switch (b.op) {
                        .add => return Value.makeInt(left.int + right.int),
                        .sub => return Value.makeInt(left.int - right.int),
                        .mul => return Value.makeInt(left.int * right.int),
                        .floor_div => {
                            if (right.int == 0) return error.ZeroDivisionError;
                            return Value.makeInt(@divFloor(left.int, right.int));
                        },
                        .mod => {
                            if (right.int == 0) return error.ZeroDivisionError;
                            return Value.makeInt(@mod(left.int, right.int));
                        },
                        .bit_and => return Value.makeInt(left.int & right.int),
                        .bit_or => return Value.makeInt(left.int | right.int),
                        .bit_xor => return Value.makeInt(left.int ^ right.int),
                        .pow => {
                            if (right.int >= 0) {
                                if (left.int == 2 and right.int >= 63) {
                                    var big_managed = try std.math.big.int.Managed.init(self.allocator);
                                    try big_managed.set(2);
                                    var res = try std.math.big.int.Managed.init(self.allocator);
                                    try res.pow(&big_managed, @intCast(right.int));
                                    big_managed.deinit();
                                    const big_obj = try PyBigInt.initFromManaged(self.allocator, res);
                                    return Value{ .bignum = big_obj };
                                }
                                if (right.int > 60 and (left.int > 1 or left.int < -1)) {
                                    var big_managed = try std.math.big.int.Managed.init(self.allocator);
                                    try big_managed.set(left.int);
                                    var res = try std.math.big.int.Managed.init(self.allocator);
                                    try res.pow(&big_managed, @intCast(right.int));
                                    big_managed.deinit();
                                    const big_obj = try PyBigInt.initFromManaged(self.allocator, res);
                                    return Value{ .bignum = big_obj };
                                }
                                return Value.makeInt(std.math.pow(i64, left.int, right.int));
                            }
                        },
                        .lshift => {
                            if (right.int >= 0) {
                                const shift_amt: u6 = @intCast(right.int & 63);
                                return Value.makeInt(left.int << shift_amt);
                            }
                            return error.TypeError;
                        },
                        .rshift => {
                            if (right.int >= 0) {
                                const shift_amt: u6 = @intCast(right.int & 63);
                                return Value.makeInt(left.int >> shift_amt);
                            }
                            return error.TypeError;
                        },
                        .div => {
                            if (right.int == 0) return error.ZeroDivisionError;
                            return Value.makeFloat(@as(f64, @floatFromInt(left.int)) / @as(f64, @floatFromInt(right.int)));
                        },
                    }
                }
                return self.evalBinaryOp(left, b.op, right);
            },
            .unary => |u| {
                const val = try self.evalExpr(u.expr, env);
                switch (u.op) {
                    .plus => return val,
                    .minus => {
                        if (val == .int) return Value.makeInt(-val.int);
                        if (val == .float) return Value.makeFloat(-val.float);
                        return error.TypeError;
                    },
                    .invert => {
                        if (val == .int) return Value.makeInt(~val.int);
                        return error.TypeError;
                    },
                    .not => return Value.makeBool(!val.isTruthy()),
                }
            },
            .compare => |cmp| {
                if (cmp.ops.len == 1) {
                    const left = try self.evalExpr(cmp.left, env);
                    const right = try self.evalExpr(cmp.rights[0], env);
                    if (@as(std.meta.Tag(Value), left) == .int and @as(std.meta.Tag(Value), right) == .int) {
                        const li = left.int;
                        const ri = right.int;
                        const ok = switch (cmp.ops[0]) {
                            .eq => li == ri,
                            .ne => li != ri,
                            .lt => li < ri,
                            .le => li <= ri,
                            .gt => li > ri,
                            .ge => li >= ri,
                            else => self.evalCompareOp(left, cmp.ops[0], right),
                        };
                        return Value.makeBool(ok);
                    }
                    return Value.makeBool(self.evalCompareOp(left, cmp.ops[0], right));
                }
                var left = try self.evalExpr(cmp.left, env);
                for (cmp.ops, 0..) |op, i| {
                    const right = try self.evalExpr(cmp.rights[i], env);
                    const satisfied = self.evalCompareOp(left, op, right);
                    if (!satisfied) return Value.makeBool(false);
                    left = right;
                }
                return Value.makeBool(true);
            },
            .bool_op => |bo| {
                if (bo.op == .op_and) {
                    for (bo.values) |v_expr| {
                        const val = try self.evalExpr(v_expr, env);
                        if (!val.isTruthy()) return val;
                    }
                    return self.evalExpr(bo.values[bo.values.len - 1], env);
                } else {
                    for (bo.values) |v_expr| {
                        const val = try self.evalExpr(v_expr, env);
                        if (val.isTruthy()) return val;
                    }
                    return self.evalExpr(bo.values[bo.values.len - 1], env);
                }
            },
            .call => |c| {
                // Method call fast-path (bypasses PyBoundMethod heap allocation)
                if (c.callee.* == .attribute) {
                    const att = &c.callee.attribute;
                    const obj = try self.evalExpr(att.value, env);

                    // 1. list.append fast-path
                    if (obj == .list and std.mem.eql(u8, att.attr, "append") and c.args.len == 1 and c.kwargs.len == 0) {
                        const item = try self.evalExpr(c.args[0], env);
                        try obj.list.items.append(self.allocator, item);
                        return .none;
                    }

                    // 2. set.add fast-path
                    if (obj == .set and std.mem.eql(u8, att.attr, "add") and c.args.len == 1 and c.kwargs.len == 0) {
                        const item = try self.evalExpr(c.args[0], env);
                        try obj.set.add(self.allocator, item);
                        return .none;
                    }

                    // 3. dict.get fast-path
                    if (obj == .dict and std.mem.eql(u8, att.attr, "get") and (c.args.len == 1 or c.args.len == 2) and c.kwargs.len == 0) {
                        const k = try self.evalExpr(c.args[0], env);
                        const def_val = if (c.args.len == 2) try self.evalExpr(c.args[1], env) else Value.none;
                        return obj.dict.get(k) orelse def_val;
                    }

                    // 4. Instance method direct dispatch with monomorphic inline cache
                    if (obj == .instance) {
                        const ins = obj.instance;
                        var method_opt: ?Value = null;
                        if (att.cached_class != null and att.cached_class.? == @as(*anyopaque, @ptrCast(ins.class))) {
                            method_opt = att.cached_method;
                        } else {
                            if (ins.class.lookup(att.attr)) |m| {
                                att.cached_class = @ptrCast(ins.class);
                                att.cached_method = m;
                                method_opt = m;
                            }
                        }

                        if (method_opt) |method| {
                            if (c.args.len < 7 and c.kwargs.len == 0) {
                                var m_args: [8]Value = undefined;
                                m_args[0] = obj;
                                for (c.args, 0..) |a, i| {
                                    m_args[i + 1] = try self.evalExpr(a, env);
                                }
                                return self.callValue(method, m_args[0 .. c.args.len + 1], &[_]DictEntry{});
                            }
                        }
                    }

                    const callee = try self.evalAttribute(obj, att.attr);
                    if (c.args.len < 8 and c.kwargs.len == 0) {
                        var evaled_args: [8]Value = undefined;
                        for (c.args, 0..) |a, i| {
                            evaled_args[i] = try self.evalExpr(a, env);
                        }
                        return self.callValue(callee, evaled_args[0..c.args.len], &[_]DictEntry{});
                    }
                    var evaled_args = try self.allocator.alloc(Value, c.args.len);
                    for (c.args, 0..) |a, i| {
                        evaled_args[i] = try self.evalExpr(a, env);
                    }
                    var evaled_kwargs = try self.allocator.alloc(DictEntry, c.kwargs.len);
                    for (c.kwargs, 0..) |kw, i| {
                        const k_val = try Value.makeString(self.allocator, kw.name);
                        const v_val = try self.evalExpr(kw.value, env);
                        evaled_kwargs[i] = .{ .key = k_val, .val = v_val };
                    }
                    return self.callValue(callee, evaled_args, evaled_kwargs);
                }

                const callee = try self.evalExpr(c.callee, env);

                // Small argument count fast-path (stack allocation, zero heap churn!)
                if (c.args.len < 8 and c.kwargs.len == 0) {
                    var evaled_args: [8]Value = undefined;
                    for (c.args, 0..) |a, i| {
                        evaled_args[i] = try self.evalExpr(a, env);
                    }
                    return self.callValue(callee, evaled_args[0..c.args.len], &[_]DictEntry{});
                }

                var evaled_args = try self.allocator.alloc(Value, c.args.len);
                for (c.args, 0..) |a, i| {
                    evaled_args[i] = try self.evalExpr(a, env);
                }

                var evaled_kwargs = try self.allocator.alloc(DictEntry, c.kwargs.len);
                for (c.kwargs, 0..) |kw, i| {
                    const k_val = try Value.makeString(self.allocator, kw.name);
                    const v_val = try self.evalExpr(kw.value, env);
                    evaled_kwargs[i] = .{ .key = k_val, .val = v_val };
                }

                return self.callValue(callee, evaled_args, evaled_kwargs);
            },
            .attribute => |*att| {
                const val = try self.evalExpr(att.value, env);
                if (val == .instance) {
                    const ins = val.instance;
                    if (att.cached_slot < ins.inline_count) {
                        const s = &ins.inline_slots[att.cached_slot];
                        if (s.name.ptr == att.attr.ptr or std.mem.eql(u8, s.name, att.attr)) {
                            return s.val;
                        }
                    }
                    var i: u8 = 0;
                    while (i < ins.inline_count) : (i += 1) {
                        if (ins.inline_slots[i].name.ptr == att.attr.ptr or std.mem.eql(u8, ins.inline_slots[i].name, att.attr)) {
                            att.cached_slot = i;
                            return ins.inline_slots[i].val;
                        }
                    }
                }
                return self.evalAttribute(val, att.attr);
            },
            .subscript => |sub| {
                const target = try self.evalExpr(sub.value, env);
                return self.evalSubscript(target, sub.slice, env);
            },
            .list_expr => |items| {
                const l = try PyList.init(self.allocator);
                for (items) |it| {
                    const v = try self.evalExpr(it, env);
                    try l.items.append(self.allocator, v);
                }
                return Value{ .list = l };
            },
            .tuple_expr => |items| {
                const arr = try self.allocator.alloc(Value, items.len);
                for (items, 0..) |it, i| {
                    arr[i] = try self.evalExpr(it, env);
                }
                const tup = try self.allocator.create(PyTuple);
                tup.* = .{ .items = arr };
                return Value{ .tuple = tup };
            },
            .dict_expr => |d| {
                const dict = try PyDict.init(self.allocator);
                for (d.keys, 0..) |k_expr, i| {
                    const k = try self.evalExpr(k_expr, env);
                    const v = try self.evalExpr(d.values[i], env);
                    try dict.put(self.allocator, k, v);
                }
                return Value{ .dict = dict };
            },
            .set_expr => |items| {
                const s = try PySet.init(self.allocator);
                for (items) |it| {
                    const v = try self.evalExpr(it, env);
                    try s.add(self.allocator, v);
                }
                return Value{ .set = s };
            },
            .ternary => |ter| {
                const cond = try self.evalExpr(ter.condition, env);
                if (cond.isTruthy()) {
                    return self.evalExpr(ter.if_val, env);
                } else {
                    return self.evalExpr(ter.else_val, env);
                }
            },
            .lambda => |l| {
                var p_names = try self.allocator.alloc([]const u8, l.params.len);
                for (l.params, 0..) |p, i| p_names[i] = p;

                const ret_stmt = try self.allocator.alloc(Stmt, 1);
                ret_stmt[0] = Stmt{ .return_stmt = l.body };

                env.markEscaped();
                const fn_obj = try self.allocator.create(PyFunction);
                fn_obj.* = .{
                    .name = "<lambda>",
                    .param_names = p_names,
                    .defaults = &[_]Value{},
                    .vararg = null,
                    .kwarg = null,
                    .body_opaque = @ptrCast(ret_stmt.ptr),
                    .body_len = 1,
                    .closure_env = @ptrCast(env),
                    .chunk = null,
                };
                return Value{ .function = fn_obj };
            },
            .list_comp => |lc| {
                const new_list = try PyList.init(self.allocator);
                const iter_val = try self.evalExpr(lc.iter, env);
                switch (iter_val) {
                    .range => |r| {
                        const len = r.length();
                        var idx: usize = 0;
                        while (idx < len) : (idx += 1) {
                            const val_int = r.start + @as(i64, @intCast(idx)) * r.step;
                            try self.assignTarget(lc.target, Value.makeInt(val_int), env);
                            var include = true;
                            if (lc.condition) |cond| {
                                const cv = try self.evalExpr(cond, env);
                                include = cv.isTruthy();
                            }
                            if (include) {
                                const elt_val = try self.evalExpr(lc.elt, env);
                                try new_list.items.append(self.allocator, elt_val);
                            }
                        }
                    },
                    .list => |l| {
                        for (l.items.items) |it| {
                            try self.assignTarget(lc.target, it, env);
                            var include = true;
                            if (lc.condition) |cond| {
                                const cv = try self.evalExpr(cond, env);
                                include = cv.isTruthy();
                            }
                            if (include) {
                                const elt_val = try self.evalExpr(lc.elt, env);
                                try new_list.items.append(self.allocator, elt_val);
                            }
                        }
                    },
                    .tuple => |t| {
                        for (t.items) |it| {
                            try self.assignTarget(lc.target, it, env);
                            var include = true;
                            if (lc.condition) |cond| {
                                const cv = try self.evalExpr(cond, env);
                                include = cv.isTruthy();
                            }
                            if (include) {
                                const elt_val = try self.evalExpr(lc.elt, env);
                                try new_list.items.append(self.allocator, elt_val);
                            }
                        }
                    },
                    .generator => |g| {
                        while (g.next()) |it| {
                            try self.assignTarget(lc.target, it, env);
                            var include = true;
                            if (lc.condition) |cond| {
                                const cv = try self.evalExpr(cond, env);
                                include = cv.isTruthy();
                            }
                            if (include) {
                                const elt_val = try self.evalExpr(lc.elt, env);
                                try new_list.items.append(self.allocator, elt_val);
                            }
                        }
                    },
                    .iterator => |it| {
                        while (it.next(self.allocator)) |item| {
                            try self.assignTarget(lc.target, item, env);
                            var include = true;
                            if (lc.condition) |cond| {
                                const cv = try self.evalExpr(cond, env);
                                include = cv.isTruthy();
                            }
                            if (include) {
                                const elt_val = try self.evalExpr(lc.elt, env);
                                try new_list.items.append(self.allocator, elt_val);
                            }
                        }
                    },
                    else => return error.TypeError,
                }
                return Value{ .list = new_list };
            },
            .f_string => |fs| {
                var buf: std.ArrayList(u8) = .empty;
                for (fs.parts) |p| {
                    const v = try self.evalExpr(p, env);
                    const s = try v.str(self.allocator);
                    try buf.appendSlice(self.allocator, s);
                }
                return Value.makeString(self.allocator, buf.items);
            },
            .yield_expr => |ye| {
                const val = if (ye) |e| try self.evalExpr(e, env) else Value.makeNone();
                if (self.current_yield_gen) |cg| {
                    try cg.items.append(self.allocator, val);
                }
                return val;
            },
            .await_expr => |ae| {
                const coro_val = try self.evalExpr(ae, env);
                if (coro_val == .coroutine) {
                    return coro_val.coroutine.result;
                }
                return coro_val;
            },
        }
    }

    pub inline fn evalBinaryOp(self: *Interpreter, left: Value, op: BinaryOp, right: Value) !Value {
        if (left == .int and right == .int) {
            switch (op) {
                .add => return Value.makeInt(left.int + right.int),
                .sub => return Value.makeInt(left.int - right.int),
                .mul => return Value.makeInt(left.int * right.int),
                .floor_div => {
                    if (right.int == 0) return error.ZeroDivisionError;
                    return Value.makeInt(@divFloor(left.int, right.int));
                },
                .mod => {
                    if (right.int == 0) return error.ZeroDivisionError;
                    return Value.makeInt(@mod(left.int, right.int));
                },
                .bit_and => return Value.makeInt(left.int & right.int),
                .bit_or => return Value.makeInt(left.int | right.int),
                .bit_xor => return Value.makeInt(left.int ^ right.int),
                .lshift => {
                    if (right.int >= 0) {
                        const shift_amt: u6 = @intCast(right.int & 63);
                        return Value.makeInt(left.int << shift_amt);
                    }
                    return error.TypeError;
                },
                .rshift => {
                    if (right.int >= 0) {
                        const shift_amt: u6 = @intCast(right.int & 63);
                        return Value.makeInt(left.int >> shift_amt);
                    }
                    return error.TypeError;
                },
                .pow => {
                    if (right.int >= 0) {
                        if (left.int == 2 and right.int >= 63) {
                            var b = try std.math.big.int.Managed.init(self.allocator);
                            try b.set(2);
                            var res = try std.math.big.int.Managed.init(self.allocator);
                            try res.pow(&b, @intCast(right.int));
                            b.deinit();
                            const big_obj = try PyBigInt.initFromManaged(self.allocator, res);
                            return Value{ .bignum = big_obj };
                        }
                        if (right.int > 60 and (left.int > 1 or left.int < -1)) {
                            var b = try std.math.big.int.Managed.init(self.allocator);
                            try b.set(left.int);
                            var res = try std.math.big.int.Managed.init(self.allocator);
                            try res.pow(&b, @intCast(right.int));
                            b.deinit();
                            const big_obj = try PyBigInt.initFromManaged(self.allocator, res);
                            return Value{ .bignum = big_obj };
                        }
                        return Value.makeInt(std.math.pow(i64, left.int, right.int));
                    } else {
                        return Value.makeFloat(std.math.pow(f64, @as(f64, @floatFromInt(left.int)), @as(f64, @floatFromInt(right.int))));
                    }
                },
                .div => {
                    if (right.int == 0) return error.ZeroDivisionError;
                    return Value.makeFloat(@as(f64, @floatFromInt(left.int)) / @as(f64, @floatFromInt(right.int)));
                },
            }
        }

        if (left == .bignum or right == .bignum) {
            var a_managed: std.math.big.int.Managed = undefined;
            var a_needs_deinit = false;
            if (left == .bignum) {
                a_managed = left.bignum.managed;
            } else if (left == .int) {
                a_managed = try std.math.big.int.Managed.init(self.allocator);
                try a_managed.set(left.int);
                a_needs_deinit = true;
            } else return error.TypeError;
            defer if (a_needs_deinit) a_managed.deinit();

            var b_managed: std.math.big.int.Managed = undefined;
            var b_needs_deinit = false;
            if (right == .bignum) {
                b_managed = right.bignum.managed;
            } else if (right == .int) {
                b_managed = try std.math.big.int.Managed.init(self.allocator);
                try b_managed.set(right.int);
                b_needs_deinit = true;
            } else return error.TypeError;
            defer if (b_needs_deinit) b_managed.deinit();

            var res = try std.math.big.int.Managed.init(self.allocator);
            switch (op) {
                .add => try res.add(&a_managed, &b_managed),
                .sub => try res.sub(&a_managed, &b_managed),
                .mul => try res.mul(&a_managed, &b_managed),
                else => return error.TypeError,
            }
            const big_obj = try PyBigInt.initFromManaged(self.allocator, res);
            return Value{ .bignum = big_obj };
        }

        switch (op) {
            .add => {
                if (left == .float and right == .float) return Value.makeFloat(left.float + right.float);
                if (left == .int and right == .float) return Value.makeFloat(@as(f64, @floatFromInt(left.int)) + right.float);
                if (left == .float and right == .int) return Value.makeFloat(left.float + @as(f64, @floatFromInt(right.int)));
                if (left == .string and right == .string) {
                    const joined = try std.mem.concat(self.allocator, u8, &[_][]const u8{ left.string.bytes, right.string.bytes });
                    return Value.makeString(self.allocator, joined);
                }
                if (left == .list and right == .list) {
                    const new_list = try PyList.init(self.allocator);
                    for (left.list.items.items) |it| try new_list.items.append(self.allocator, it);
                    for (right.list.items.items) |it| try new_list.items.append(self.allocator, it);
                    return Value{ .list = new_list };
                }
                return error.TypeError;
            },
            .sub => {
                if (left == .float and right == .float) return Value.makeFloat(left.float - right.float);
                if (left == .int and right == .float) return Value.makeFloat(@as(f64, @floatFromInt(left.int)) - right.float);
                if (left == .float and right == .int) return Value.makeFloat(left.float - @as(f64, @floatFromInt(right.int)));
                return error.TypeError;
            },
            .mul => {
                if (left == .float and right == .float) return Value.makeFloat(left.float * right.float);
                if (left == .int and right == .float) return Value.makeFloat(@as(f64, @floatFromInt(left.int)) * right.float);
                if (left == .float and right == .int) return Value.makeFloat(left.float * @as(f64, @floatFromInt(right.int)));
                if (left == .string and right == .int) {
                    const times: usize = if (right.int > 0) @intCast(right.int) else 0;
                    var buf: std.ArrayList(u8) = .empty;
                    var i: usize = 0;
                    while (i < times) : (i += 1) try buf.appendSlice(self.allocator, left.string.bytes);
                    return Value.makeString(self.allocator, buf.items);
                }
                if (left == .list and right == .int) {
                    const times: usize = if (right.int > 0) @intCast(right.int) else 0;
                    const new_list = try PyList.init(self.allocator);
                    var i: usize = 0;
                    while (i < times) : (i += 1) {
                        for (left.list.items.items) |it| try new_list.items.append(self.allocator, it);
                    }
                    return Value{ .list = new_list };
                }
                return error.TypeError;
            },
            .div => {
                const l_f = if (left == .float) left.float else if (left == .int) @as(f64, @floatFromInt(left.int)) else return error.TypeError;
                const r_f = if (right == .float) right.float else if (right == .int) @as(f64, @floatFromInt(right.int)) else return error.TypeError;
                if (r_f == 0.0) return error.ZeroDivisionError;
                return Value.makeFloat(l_f / r_f);
            },
            .floor_div => {
                const l_f = if (left == .float) left.float else if (left == .int) @as(f64, @floatFromInt(left.int)) else return error.TypeError;
                const r_f = if (right == .float) right.float else if (right == .int) @as(f64, @floatFromInt(right.int)) else return error.TypeError;
                if (r_f == 0.0) return error.ZeroDivisionError;
                return Value.makeFloat(@floor(l_f / r_f));
            },
            .mod => {
                if (left == .float or right == .float) {
                    const l_f = if (left == .float) left.float else @as(f64, @floatFromInt(left.int));
                    const r_f = if (right == .float) right.float else @as(f64, @floatFromInt(right.int));
                    if (r_f == 0.0) return error.ZeroDivisionError;
                    return Value.makeFloat(@mod(l_f, r_f));
                }
                return error.TypeError;
            },
            .bit_and, .bit_or, .bit_xor, .lshift, .rshift => return error.TypeError,
            .pow => {
                const l_f = if (left == .float) left.float else if (left == .int) @as(f64, @floatFromInt(left.int)) else return error.TypeError;
                const r_f = if (right == .float) right.float else if (right == .int) @as(f64, @floatFromInt(right.int)) else return error.TypeError;
                return Value.makeFloat(std.math.pow(f64, l_f, r_f));
            },
        }
    }

    pub inline fn evalCompareOp(self: *Interpreter, left: Value, op: CompareOp, right: Value) bool {
        // Fast integer comparison (1 CPU instruction)
        if (@as(std.meta.Tag(Value), left) == .int and @as(std.meta.Tag(Value), right) == .int) {
            switch (op) {
                .eq => return left.int == right.int,
                .ne => return left.int != right.int,
                .lt => return left.int < right.int,
                .le => return left.int <= right.int,
                .gt => return left.int > right.int,
                .ge => return left.int >= right.int,
                else => {},
            }
        }

        switch (op) {
            .eq => return left.equals(right),
            .ne => return !left.equals(right),
            .lt => {
                if (left == .float and right == .float) return left.float < right.float;
                if (left == .int and right == .float) return @as(f64, @floatFromInt(left.int)) < right.float;
                if (left == .float and right == .int) return left.float < @as(f64, @floatFromInt(right.int));
                if (left == .string and right == .string) return std.mem.order(u8, left.string.bytes, right.string.bytes) == .lt;
                return false;
            },
            .le => {
                if (left == .float and right == .float) return left.float <= right.float;
                if (left == .int and right == .float) return @as(f64, @floatFromInt(left.int)) <= right.float;
                if (left == .float and right == .int) return left.float <= @as(f64, @floatFromInt(right.int));
                if (left == .string and right == .string) return std.mem.order(u8, left.string.bytes, right.string.bytes) != .gt;
                return false;
            },
            .gt => {
                if (left == .float and right == .float) return left.float > right.float;
                if (left == .int and right == .float) return @as(f64, @floatFromInt(left.int)) > right.float;
                if (left == .float and right == .int) return left.float > @as(f64, @floatFromInt(right.int));
                if (left == .string and right == .string) return std.mem.order(u8, left.string.bytes, right.string.bytes) == .gt;
                return false;
            },
            .ge => {
                if (left == .float and right == .float) return left.float >= right.float;
                if (left == .int and right == .float) return @as(f64, @floatFromInt(left.int)) >= right.float;
                if (left == .float and right == .int) return left.float >= @as(f64, @floatFromInt(right.int));
                if (left == .string and right == .string) return std.mem.order(u8, left.string.bytes, right.string.bytes) != .lt;
                return false;
            },
            .in => {
                if (right == .list) {
                    for (right.list.items.items) |it| {
                        if (it.equals(left)) return true;
                    }
                } else if (right == .tuple) {
                    for (right.tuple.items) |it| {
                        if (it.equals(left)) return true;
                    }
                } else if (right == .string and left == .string) {
                    return std.mem.indexOf(u8, right.string.bytes, left.string.bytes) != null;
                } else if (right == .dict) {
                    return right.dict.get(left) != null;
                } else if (right == .set) {
                    return right.set.contains(left);
                }
                return false;
            },
            .not_in => {
                return !self.evalCompareOp(left, .in, right);
            },
            .is => {
                if (left == .none and right == .none) return true;
                if (left == .bool and right == .bool) return left.bool == right.bool;
                return left.equals(right);
            },
            .is_not => {
                return !self.evalCompareOp(left, .is, right);
            },
        }
    }

    pub fn evalAttribute(self: *Interpreter, val: Value, attr: []const u8) !Value {
        switch (val) {
            .instance => |ins| {
                if (ins.getAttr(self.allocator, attr)) |a| return a;
                std.debug.print("AttributeError: '{s}' object has no attribute '{s}'\n", .{ ins.class.name, attr });
                return error.AttributeError;
            },
            .class => |cls| {
                if (cls.lookup(attr)) |a| return a;
                std.debug.print("AttributeError: type object '{s}' has no attribute '{s}'\n", .{ cls.name, attr });
                return error.AttributeError;
            },
            .module => |mod| {
                if (mod.attributes.get(attr)) |a| return a;
                std.debug.print("AttributeError: module '{s}' has no attribute '{s}'\n", .{ mod.name, attr });
                return error.AttributeError;
            },
            .string => |s| {
                // String methods
                if (std.mem.eql(u8, attr, "upper")) {
                    const string_upper = struct {
                        fn call(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1 or args[0] != .string) return error.TypeError;
                            const self_val = args[0].string;
                            const up = try std.ascii.allocUpperString(allocator, self_val.bytes);
                            return Value.makeString(allocator, up);
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "upper", .func = string_upper };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .string = s }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "lower")) {
                    const string_lower = struct {
                        fn call(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1 or args[0] != .string) return error.TypeError;
                            const self_val = args[0].string;
                            const low = try std.ascii.allocLowerString(allocator, self_val.bytes);
                            return Value.makeString(allocator, low);
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "lower", .func = string_lower };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .string = s }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "startswith")) {
                    const string_sw = struct {
                        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 2 or args[0] != .string or args[1] != .string) return error.TypeError;
                            const self_val = args[0].string;
                            return Value.makeBool(std.mem.startsWith(u8, self_val.bytes, args[1].string.bytes));
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "startswith", .func = string_sw };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .string = s }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "endswith")) {
                    const string_ew = struct {
                        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 2 or args[0] != .string or args[1] != .string) return error.TypeError;
                            const self_val = args[0].string;
                            return Value.makeBool(std.mem.endsWith(u8, self_val.bytes, args[1].string.bytes));
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "endswith", .func = string_ew };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .string = s }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "split")) {
                    const string_split = struct {
                        fn call(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1 or args[0] != .string) return error.TypeError;
                            const self_val = args[0].string;
                            const sep: []const u8 = if (args.len > 1 and args[1] == .string) args[1].string.bytes else " ";
                            const list = try PyList.init(allocator);

                            var it = std.mem.splitSequence(u8, self_val.bytes, sep);
                            while (it.next()) |part| {
                                const p_val = try Value.makeString(allocator, part);
                                try list.items.append(allocator, p_val);
                            }
                            return Value{ .list = list };
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "split", .func = string_split };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .string = s }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "join")) {
                    const string_join = struct {
                        fn call(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 2 or args[0] != .string or args[1] != .list) return error.TypeError;
                            const self_val = args[0].string;
                            var buf: std.ArrayList(u8) = .empty;
                            for (args[1].list.items.items, 0..) |it, idx| {
                                if (idx > 0) try buf.appendSlice(allocator, self_val.bytes);
                                const s_rep = try it.str(allocator);
                                try buf.appendSlice(allocator, s_rep);
                            }
                            return Value.makeString(allocator, buf.items);
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "join", .func = string_join };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .string = s }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                return error.AttributeError;
            },
            .list => |l| {
                // List methods
                if (std.mem.eql(u8, attr, "append")) {
                    const list_append = struct {
                        fn call(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 2 or args[0] != .list) return error.TypeError;
                            const self_val = args[0].list;
                            try self_val.items.append(allocator, args[1]);
                            return .none;
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "append", .func = list_append };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .list = l }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "pop")) {
                    const list_pop = struct {
                        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1 or args[0] != .list) return error.TypeError;
                            const self_val = args[0].list;
                            if (self_val.items.items.len == 0) return error.IndexError;
                            if (args.len == 1) {
                                return self_val.items.pop() orelse return error.IndexError;
                            }
                            const idx_val = args[1];
                            if (idx_val != .int) return error.TypeError;
                            var i = idx_val.int;
                            const len: i64 = @intCast(self_val.items.items.len);
                            if (i < 0) i += len;
                            if (i < 0 or i >= len) return error.IndexError;
                            const val_removed = self_val.items.orderedRemove(@intCast(i));
                            return val_removed;
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "pop", .func = list_pop };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .list = l }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                return error.AttributeError;
            },
            .dict => |d| {
                // Dict methods
                if (std.mem.eql(u8, attr, "get")) {
                    const dict_get = struct {
                        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 2 or args[0] != .dict) return error.TypeError;
                            const self_val = args[0].dict;
                            if (self_val.get(args[1])) |v| return v;
                            return if (args.len > 2) args[2] else .none;
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "get", .func = dict_get };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .dict = d }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "keys")) {
                    const dict_keys = struct {
                        fn call(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1 or args[0] != .dict) return error.TypeError;
                            const self_val = args[0].dict;
                            const l = try PyList.init(allocator);
                            for (self_val.entries.items) |e| try l.items.append(allocator, e.key);
                            return Value{ .list = l };
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "keys", .func = dict_keys };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .dict = d }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "values")) {
                    const dict_vals = struct {
                        fn call(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1 or args[0] != .dict) return error.TypeError;
                            const self_val = args[0].dict;
                            const l = try PyList.init(allocator);
                            for (self_val.entries.items) |e| try l.items.append(allocator, e.val);
                            return Value{ .list = l };
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "values", .func = dict_vals };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .dict = d }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                return error.AttributeError;
            },
            .set => |s| {
                if (std.mem.eql(u8, attr, "add")) {
                    const set_add = struct {
                        fn call(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 2 or args[0] != .set) return error.TypeError;
                            try args[0].set.add(allocator, args[1]);
                            return .none;
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "add", .func = set_add };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .set = s }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "remove")) {
                    const set_remove = struct {
                        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 2 or args[0] != .set) return error.TypeError;
                            const ok = args[0].set.remove(args[1]);
                            if (!ok) return error.KeyError;
                            return .none;
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "remove", .func = set_remove };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .set = s }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "clear")) {
                    const set_clear = struct {
                        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1 or args[0] != .set) return error.TypeError;
                            args[0].set.clear();
                            return .none;
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "clear", .func = set_clear };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .set = s }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                return error.AttributeError;
            },
            .generator => |g| {
                if (std.mem.eql(u8, attr, "__iter__")) {
                    const gen_iter = struct {
                        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1) return error.TypeError;
                            return args[0];
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "__iter__", .func = gen_iter };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .generator = g }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "__next__") or std.mem.eql(u8, attr, "send")) {
                    const gen_next = struct {
                        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1 or args[0] != .generator) return error.TypeError;
                            if (args[0].generator.next()) |item| {
                                return item;
                            }
                            return error.StopIteration;
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = attr, .func = gen_next };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .generator = g }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                return error.AttributeError;
            },
            .iterator => |it| {
                if (std.mem.eql(u8, attr, "__iter__")) {
                    const it_iter = struct {
                        fn call(_: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1) return error.TypeError;
                            return args[0];
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "__iter__", .func = it_iter };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .iterator = it }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                if (std.mem.eql(u8, attr, "__next__")) {
                    const it_next = struct {
                        fn call(allocator: Allocator, _: ?*anyopaque, args: []const Value, _: []const DictEntry) anyerror!Value {
                            if (args.len < 1 or args[0] != .iterator) return error.TypeError;
                            if (args[0].iterator.next(allocator)) |item| {
                                return item;
                            }
                            return error.StopIteration;
                        }
                    }.call;
                    const b = try self.allocator.create(PyBuiltin);
                    b.* = .{ .name = "__next__", .func = it_next };
                    const bm = try self.allocator.create(PyBoundMethod);
                    bm.* = .{ .instance = .{ .iterator = it }, .function = .{ .builtin = b } };
                    return Value{ .bound_method = bm };
                }
                return error.AttributeError;
            },
            else => return error.AttributeError,
        }
    }

    pub fn evalSubscriptValue(self: *Interpreter, target: Value, key: Value) !Value {
        switch (target) {
            .list => |l| {
                if (key != .int) return error.TypeError;
                var idx = key.int;
                const len: i64 = @intCast(l.items.items.len);
                if (idx < 0) idx += len;
                if (idx < 0 or idx >= len) return error.IndexError;
                return l.items.items[@intCast(idx)];
            },
            .tuple => |t| {
                if (key != .int) return error.TypeError;
                var idx = key.int;
                const len: i64 = @intCast(t.items.len);
                if (idx < 0) idx += len;
                if (idx < 0 or idx >= len) return error.IndexError;
                return t.items[@intCast(idx)];
            },
            .string => |s| {
                if (key != .int) return error.TypeError;
                var idx = key.int;
                const len: i64 = @intCast(s.bytes.len);
                if (idx < 0) idx += len;
                if (idx < 0 or idx >= len) return error.IndexError;
                const cs = try self.allocator.alloc(u8, 1);
                cs[0] = s.bytes[@intCast(idx)];
                return Value.makeString(self.allocator, cs);
            },
            .dict => |d| {
                if (d.get(key)) |v| return v;
                return error.KeyError;
            },
            else => return error.TypeError,
        }
    }

    fn evalSubscript(self: *Interpreter, target: Value, slice: *ast_mod.SliceExpr, env: *Environment) !Value {
        if (slice.is_index and slice.lower != null) {
            const key = try self.evalExpr(slice.lower.?, env);
            return self.evalSubscriptValue(target, key);
        } else {
            // Slicing [lower:upper:step]
            const step_v = if (slice.step) |se| try self.evalExpr(se, env) else Value.none;
            const lower_v = if (slice.lower) |le| try self.evalExpr(le, env) else Value.none;
            const upper_v = if (slice.upper) |ue| try self.evalExpr(ue, env) else Value.none;
            return self.evalSliceValues(target, lower_v, upper_v, step_v);
        }
    }

    pub fn evalSliceValues(self: *Interpreter, target: Value, lower_val: Value, upper_val: Value, step_val: Value) !Value {
        const step_i: i64 = if (step_val == .int) step_val.int else 1;
        if (step_i == 0) return error.ValueError;
        const lower_i: ?i64 = if (lower_val == .int) lower_val.int else null;
        const upper_i: ?i64 = if (upper_val == .int) upper_val.int else null;

        if (target == .list) {
            const len: i64 = @intCast(target.list.items.items.len);
            var start: i64 = undefined;
            var end: i64 = undefined;
            if (step_i > 0) {
                start = lower_i orelse 0;
                end = upper_i orelse len;
                if (start < 0) start += len;
                if (end < 0) end += len;
                start = @max(0, @min(start, len));
                end = @max(0, @min(end, len));
            } else {
                start = lower_i orelse (len - 1);
                end = upper_i orelse -1;
                if (start < 0) start += len;
                if (upper_i != null and end < 0) end += len;
                start = @max(-1, @min(start, len - 1));
                end = @max(-1, @min(end, len - 1));
            }

            const new_l = try PyList.init(self.allocator);
            var i = start;
            if (step_i > 0) {
                while (i < end) : (i += step_i) {
                    try new_l.items.append(self.allocator, target.list.items.items[@intCast(i)]);
                }
            } else {
                while (i > end) : (i += step_i) {
                    try new_l.items.append(self.allocator, target.list.items.items[@intCast(i)]);
                }
            }
            return Value{ .list = new_l };
        } else if (target == .string) {
            const len: i64 = @intCast(target.string.bytes.len);
            var start: i64 = undefined;
            var end: i64 = undefined;
            if (step_i > 0) {
                start = lower_i orelse 0;
                end = upper_i orelse len;
                if (start < 0) start += len;
                if (end < 0) end += len;
                start = @max(0, @min(start, len));
                end = @max(0, @min(end, len));
            } else {
                start = lower_i orelse (len - 1);
                end = upper_i orelse -1;
                if (start < 0) start += len;
                if (upper_i != null and end < 0) end += len;
                start = @max(-1, @min(start, len - 1));
                end = @max(-1, @min(end, len - 1));
            }

            var buf: std.ArrayList(u8) = .empty;
            var i = start;
            if (step_i > 0) {
                while (i < end) : (i += step_i) {
                    try buf.append(self.allocator, target.string.bytes[@intCast(i)]);
                }
            } else {
                while (i > end) : (i += step_i) {
                    try buf.append(self.allocator, target.string.bytes[@intCast(i)]);
                }
            }
            return Value.makeString(self.allocator, buf.items);
        } else if (target == .tuple) {
            const len: i64 = @intCast(target.tuple.items.len);
            var start: i64 = undefined;
            var end: i64 = undefined;
            if (step_i > 0) {
                start = lower_i orelse 0;
                end = upper_i orelse len;
                if (start < 0) start += len;
                if (end < 0) end += len;
                start = @max(0, @min(start, len));
                end = @max(0, @min(end, len));
            } else {
                start = lower_i orelse (len - 1);
                end = upper_i orelse -1;
                if (start < 0) start += len;
                if (upper_i != null and end < 0) end += len;
                start = @max(-1, @min(start, len - 1));
                end = @max(-1, @min(end, len - 1));
            }

            var buf: std.ArrayList(Value) = .empty;
            var i = start;
            if (step_i > 0) {
                while (i < end) : (i += step_i) {
                    try buf.append(self.allocator, target.tuple.items[@intCast(i)]);
                }
            } else {
                while (i > end) : (i += step_i) {
                    try buf.append(self.allocator, target.tuple.items[@intCast(i)]);
                }
            }
            const tup = try self.allocator.create(PyTuple);
            tup.* = .{ .items = try buf.toOwnedSlice(self.allocator) };
            return Value{ .tuple = tup };
        }
        return error.TypeError;
    }

    pub fn callValue(self: *Interpreter, callee: Value, args: []const Value, kwargs: []const DictEntry) anyerror!Value {
        switch (callee) {
            .bound_method => |bm| {
                if (args.len < 7) {
                    var method_buf: [8]Value = undefined;
                    method_buf[0] = bm.instance;
                    @memcpy(method_buf[1 .. args.len + 1], args);
                    return self.callValue(bm.function, method_buf[0 .. args.len + 1], kwargs);
                } else {
                    var method_args = try self.allocator.alloc(Value, args.len + 1);
                    method_args[0] = bm.instance;
                    @memcpy(method_args[1..], args);
                    return self.callValue(bm.function, method_args, kwargs);
                }
            },
            .builtin => |b| {
                return b.func(self.allocator, null, args, kwargs);
            },
            .function => |f| {
                if (f.jit_entry) |entry| {
                    if (f.jit_kind == 1 and args.len == 1 and args[0] == .int) {
                        const NativeFn = *const fn (i64) callconv(.c) i64;
                        const native_fn: NativeFn = @ptrCast(entry);
                        return Value.makeInt(native_fn(args[0].int));
                    } else if (f.jit_kind == 2 and args.len == 2 and args[0] == .int and args[1] == .int) {
                        const NativeFn = *const fn (i64, i64) callconv(.c) i64;
                        const native_fn: NativeFn = @ptrCast(entry);
                        return Value.makeInt(native_fn(args[0].int, args[1].int));
                    } else if (f.jit_kind == 3 and args.len == 1 and args[0] == .list) {
                        const NativeFn = *const fn (*PyList) callconv(.c) *PyList;
                        const native_fn: NativeFn = @ptrCast(entry);
                        return Value{ .list = native_fn(args[0].list) };
                    } else if (f.jit_kind == 4 and args.len == 2 and (args[0] == .float or args[0] == .int) and args[1] == .int) {
                        const NativeFn = *const fn (f64, i64) callconv(.c) f64;
                        const native_fn: NativeFn = @ptrCast(entry);
                        const x = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
                        return Value.makeFloat(native_fn(x, args[1].int));
                    }
                }

                if (f.chunk) |chunk_opaque| {
                    const chunk: *Chunk = @ptrCast(@alignCast(chunk_opaque));
                    f.call_count += 1;
                    if (f.jit_entry == null) {
                        self.jit.tryCompile(f, chunk);
                        if (f.jit_entry) |entry| {
                            if (f.jit_kind == 1 and args.len == 1 and args[0] == .int) {
                                const NativeFn = *const fn (i64) callconv(.c) i64;
                                const native_fn: NativeFn = @ptrCast(entry);
                                return Value.makeInt(native_fn(args[0].int));
                            } else if (f.jit_kind == 2 and args.len == 2 and args[0] == .int and args[1] == .int) {
                                const NativeFn = *const fn (i64, i64) callconv(.c) i64;
                                const native_fn: NativeFn = @ptrCast(entry);
                                return Value.makeInt(native_fn(args[0].int, args[1].int));
                            } else if (f.jit_kind == 3 and args.len == 1 and args[0] == .list) {
                                const NativeFn = *const fn (*PyList) callconv(.c) *PyList;
                                const native_fn: NativeFn = @ptrCast(entry);
                                return Value{ .list = native_fn(args[0].list) };
                            } else if (f.jit_kind == 4 and args.len == 2 and (args[0] == .float or args[0] == .int) and args[1] == .int) {
                                const NativeFn = *const fn (f64, i64) callconv(.c) f64;
                                const native_fn: NativeFn = @ptrCast(entry);
                                const x = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
                                return Value.makeFloat(native_fn(x, args[1].int));
                            }
                        }
                    }
                    return self.vm.runFunction(f, chunk, args, kwargs);
                }
                const parent_env: ?*Environment = if (f.closure_env) |ce| @ptrCast(@alignCast(ce)) else self.global_env;
                // Acquire reusable environment from pool with ZERO heap allocation
                const call_env = self.acquireEnv(parent_env);
                defer self.releaseEnv(call_env);

                // Fast parameter binding for standard functions
                if (f.vararg == null and f.kwarg == null and kwargs.len == 0 and f.param_names.len <= 32) {
                    if (f.param_names.len == 1 and args.len == 1) {
                        call_env.fast_slots[0] = .{ .name = f.param_names[0], .val = args[0] };
                        call_env.fast_count = 1;
                    } else if (f.param_names.len == 2 and args.len == 2) {
                        call_env.fast_slots[0] = .{ .name = f.param_names[0], .val = args[0] };
                        call_env.fast_slots[1] = .{ .name = f.param_names[1], .val = args[1] };
                        call_env.fast_count = 2;
                    } else {
                        const bind_count = @min(args.len, f.param_names.len);
                        var bi: usize = 0;
                        while (bi < bind_count) : (bi += 1) {
                            call_env.fast_slots[bi] = .{ .name = f.param_names[bi], .val = args[bi] };
                        }
                        while (bi < f.param_names.len) : (bi += 1) {
                            call_env.fast_slots[bi] = .{ .name = f.param_names[bi], .val = if (bi < f.defaults.len) f.defaults[bi] else .none };
                        }
                        call_env.fast_count = @intCast(f.param_names.len);
                    }
                } else {
                    // Full parameter binding fallback
                    var arg_idx: usize = 0;
                    for (f.param_names, 0..) |p_name, i| {
                        if (f.vararg != null and std.mem.eql(u8, p_name, f.vararg.?)) {
                            const vararg_len = if (args.len > arg_idx) args.len - arg_idx else 0;
                            const v_items = try self.allocator.alloc(Value, vararg_len);
                            for (0..vararg_len) |vi| {
                                v_items[vi] = args[arg_idx + vi];
                            }
                            const tup = try self.allocator.create(PyTuple);
                            tup.* = .{ .items = v_items };
                            try call_env.set(p_name, Value{ .tuple = tup });
                            arg_idx = args.len;
                        } else if (f.kwarg != null and std.mem.eql(u8, p_name, f.kwarg.?)) {
                            const kw_dict = try PyDict.init(self.allocator);
                            for (kwargs) |kw| {
                                try kw_dict.put(self.allocator, kw.key, kw.val);
                            }
                            try call_env.set(p_name, Value{ .dict = kw_dict });
                        } else {
                            var bound = false;
                            if (arg_idx < args.len) {
                                try call_env.set(p_name, args[arg_idx]);
                                arg_idx += 1;
                                bound = true;
                            } else {
                                for (kwargs) |kw| {
                                    if (kw.key == .string and std.mem.eql(u8, kw.key.string.bytes, p_name)) {
                                        try call_env.set(p_name, kw.val);
                                        bound = true;
                                        break;
                                    }
                                }
                            }

                            if (!bound) {
                                if (f.defaults[i] != .none) {
                                    try call_env.set(p_name, f.defaults[i]);
                                } else {
                                    try call_env.set(p_name, .none);
                                }
                            }
                        }
                    }
                }

                const body_ptr: [*]const Stmt = @ptrCast(@alignCast(f.body_opaque));

                if (f.is_generator) {
                    const gen = try PyGenerator.init(self.allocator, f.name);
                    const prev_gen = self.current_yield_gen;
                    self.current_yield_gen = gen;
                    defer self.current_yield_gen = prev_gen;

                    _ = self.evalSuite(body_ptr[0..f.body_len], call_env) catch |err| switch (err) {
                        error.StopIteration => Value.makeNone(),
                        else => return err,
                    };
                    return Value{ .generator = gen };
                }

                if (f.is_async) {
                    const res = try self.evalSuite(body_ptr[0..f.body_len], call_env);
                    const actual_res = switch (res) {
                        .return_flow => self.return_value,
                        else => Value.makeNone(),
                    };
                    const coro = try PyCoroutine.init(self.allocator, f.name, actual_res);
                    return Value{ .coroutine = coro };
                }

                const res = try self.evalSuite(body_ptr[0..f.body_len], call_env);
                switch (res) {
                    .return_flow => return self.return_value,
                    else => return .none,
                }
            },
            .class => |cls| {
                const instance = try PyInstance.init(self.allocator, cls);
                const inst_val = Value{ .instance = instance };

                if (cls.lookup("__init__")) |init_fn| {
                    if (args.len < 7) {
                        var init_buf: [8]Value = undefined;
                        init_buf[0] = inst_val;
                        @memcpy(init_buf[1 .. args.len + 1], args);
                        _ = try self.callValue(init_fn, init_buf[0 .. args.len + 1], kwargs);
                    } else {
                        var init_args = try self.allocator.alloc(Value, args.len + 1);
                        init_args[0] = inst_val;
                        @memcpy(init_args[1..], args);
                        _ = try self.callValue(init_fn, init_args, kwargs);
                    }
                }

                return inst_val;
            },
            else => return error.NotCallable,
        }
    }
};
