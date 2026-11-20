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

pub const Interpreter = struct {
    allocator: Allocator,
    global_env: *Environment,
    modules: std.StringHashMap(Value),
    cli_args: []const [:0]const u8,

    pub fn init(allocator: Allocator, cli_args: []const [:0]const u8) !*Interpreter {
        const self = try allocator.create(Interpreter);
        const env = try Environment.init(allocator, null);
        try builtins_mod.populateBuiltins(allocator, env);

        self.* = .{
            .allocator = allocator,
            .global_env = env,
            .modules = std.StringHashMap(Value).init(allocator),
            .cli_args = cli_args,
        };

        // Preload standard modules
        const mod_math = try builtins_mod.makeMathModule(allocator);
        try self.modules.put("math", mod_math);

        const mod_time = try builtins_mod.makeTimeModule(allocator);
        try self.modules.put("time", mod_time);

        const mod_sys = try builtins_mod.makeSysModule(allocator, cli_args);
        try self.modules.put("sys", mod_sys);

        return self;
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
                        var idx: usize = 0;
                        while (idx < len) : (idx += 1) {
                            if (r.get(idx)) |item_int| {
                                try self.assignTarget(f.target, Value.makeInt(item_int), env);
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
                        }
                    },
                    .list => |l| {
                        for (l.items.items) |it| {
                            try self.assignTarget(f.target, it, env);
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
                        for (t.items) |it| {
                            try self.assignTarget(f.target, it, env);
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
                };

                const fn_val = Value{ .function = fn_obj };
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

                var it = class_env.bindings.iterator();
                while (it.next()) |entry| {
                    try cls.attributes.put(entry.key_ptr.*, entry.value_ptr.*);
                }

                const cls_val = Value{ .class = cls };
                try env.set(c.name, cls_val);
                return .none;
            },
            .return_stmt => |r| {
                const val = if (r) |ret_expr| try self.evalExpr(ret_expr, env) else Value.none;
                const ret_box = try self.allocator.create(Value);
                ret_box.* = val;
                return Value{ .return_flow = ret_box };
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
                _ = self.evalSuite(t.body, env) catch {
                    exc_raised = true;
                };

                var result: Value = .none;

                if (exc_raised and t.handlers.len > 0) {
                    for (t.handlers) |h| {
                        if (h.name) |name| {
                            const exc_str = try Value.makeString(self.allocator, "Exception");
                            try env.set(name, exc_str);
                        }
                        result = try self.evalSuite(h.body, env);
                        break;
                    }
                } else if (!exc_raised and t.else_branch != null) {
                    result = try self.evalSuite(t.else_branch.?, env);
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
        }
    }

    fn assignTarget(self: *Interpreter, target: *Expr, val: Value, env: *Environment) anyerror!void {
        switch (target.*) {
            .identifier => |name| {
                const assigned = try env.assign(name, val);
                if (!assigned) {
                    try env.set(name, val);
                }
            },
            .attribute => |att| {
                const obj = try self.evalExpr(att.value, env);
                if (obj == .instance) {
                    try obj.instance.attributes.put(att.attr, val);
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
                // Unpacking assignment: a, b = (1, 2)
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
            .identifier => |name| {
                if (env.get(name)) |v| return v;
                std.debug.print("NameError: name '{s}' is not defined\n", .{name});
                return error.NameError;
            },
            .binary => |b| {
                const left = try self.evalExpr(b.left, env);
                const right = try self.evalExpr(b.right, env);
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
                const callee = try self.evalExpr(c.callee, env);
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
            .attribute => |att| {
                const val = try self.evalExpr(att.value, env);
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
                };
                return Value{ .function = fn_obj };
            },
        }
    }

    fn evalBinaryOp(self: *Interpreter, left: Value, op: BinaryOp, right: Value) !Value {
        switch (op) {
            .add => {
                if (left == .int and right == .int) return Value.makeInt(left.int + right.int);
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
                if (left == .int and right == .int) return Value.makeInt(left.int - right.int);
                if (left == .float and right == .float) return Value.makeFloat(left.float - right.float);
                if (left == .int and right == .float) return Value.makeFloat(@as(f64, @floatFromInt(left.int)) - right.float);
                if (left == .float and right == .int) return Value.makeFloat(left.float - @as(f64, @floatFromInt(right.int)));
                return error.TypeError;
            },
            .mul => {
                if (left == .int and right == .int) return Value.makeInt(left.int * right.int);
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
                if (left == .int and right == .int) {
                    if (right.int == 0) return error.ZeroDivisionError;
                    return Value.makeInt(@divFloor(left.int, right.int));
                }
                return error.TypeError;
            },
            .mod => {
                if (left == .int and right == .int) {
                    if (right.int == 0) return error.ZeroDivisionError;
                    return Value.makeInt(@mod(left.int, right.int));
                }
                return error.TypeError;
            },
            .pow => {
                if (left == .int and right == .int and right.int >= 0) {
                    return Value.makeInt(std.math.pow(i64, left.int, right.int));
                }
                const l_f = if (left == .float) left.float else @as(f64, @floatFromInt(left.int));
                const r_f = if (right == .float) right.float else @as(f64, @floatFromInt(right.int));
                return Value.makeFloat(std.math.pow(f64, l_f, r_f));
            },
            .bit_and => {
                if (left == .int and right == .int) return Value.makeInt(left.int & right.int);
                return error.TypeError;
            },
            .bit_or => {
                if (left == .int and right == .int) return Value.makeInt(left.int | right.int);
                return error.TypeError;
            },
            .bit_xor => {
                if (left == .int and right == .int) return Value.makeInt(left.int ^ right.int);
                return error.TypeError;
            },
            .lshift => {
                if (left == .int and right == .int and right.int >= 0) {
                    const shift_amt: u6 = @intCast(right.int & 63);
                    return Value.makeInt(left.int << shift_amt);
                }
                return error.TypeError;
            },
            .rshift => {
                if (left == .int and right == .int and right.int >= 0) {
                    const shift_amt: u6 = @intCast(right.int & 63);
                    return Value.makeInt(left.int >> shift_amt);
                }
                return error.TypeError;
            },
        }
    }

    fn evalCompareOp(self: *Interpreter, left: Value, op: CompareOp, right: Value) bool {
        switch (op) {
            .eq => return left.equals(right),
            .ne => return !left.equals(right),
            .lt => {
                if (left == .int and right == .int) return left.int < right.int;
                if (left == .float and right == .float) return left.float < right.float;
                if (left == .int and right == .float) return @as(f64, @floatFromInt(left.int)) < right.float;
                if (left == .float and right == .int) return left.float < @as(f64, @floatFromInt(right.int));
                if (left == .string and right == .string) return std.mem.order(u8, left.string.bytes, right.string.bytes) == .lt;
                return false;
            },
            .le => {
                if (left == .int and right == .int) return left.int <= right.int;
                if (left == .float and right == .float) return left.float <= right.float;
                if (left == .int and right == .float) return @as(f64, @floatFromInt(left.int)) <= right.float;
                if (left == .float and right == .int) return left.float <= @as(f64, @floatFromInt(right.int));
                if (left == .string and right == .string) return std.mem.order(u8, left.string.bytes, right.string.bytes) != .gt;
                return false;
            },
            .gt => {
                if (left == .int and right == .int) return left.int > right.int;
                if (left == .float and right == .float) return left.float > right.float;
                if (left == .int and right == .float) return @as(f64, @floatFromInt(left.int)) > right.float;
                if (left == .float and right == .int) return left.float > @as(f64, @floatFromInt(right.int));
                if (left == .string and right == .string) return std.mem.order(u8, left.string.bytes, right.string.bytes) == .gt;
                return false;
            },
            .ge => {
                if (left == .int and right == .int) return left.int >= right.int;
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

    fn evalAttribute(self: *Interpreter, val: Value, attr: []const u8) !Value {
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
            else => return error.AttributeError,
        }
    }

    fn evalSubscript(self: *Interpreter, target: Value, slice: *ast_mod.SliceExpr, env: *Environment) !Value {
        if (slice.is_index and slice.lower != null) {
            const key = try self.evalExpr(slice.lower.?, env);
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
        } else {
            // Slicing [lower:upper:step]
            const lower_i: ?i64 = if (slice.lower) |le| (try self.evalExpr(le, env)).int else null;
            const upper_i: ?i64 = if (slice.upper) |ue| (try self.evalExpr(ue, env)).int else null;

            if (target == .list) {
                const len: i64 = @intCast(target.list.items.items.len);
                var start = lower_i orelse 0;
                var end = upper_i orelse len;
                if (start < 0) start += len;
                if (end < 0) end += len;
                start = @max(0, @min(start, len));
                end = @max(0, @min(end, len));

                const new_l = try PyList.init(self.allocator);
                var i = start;
                while (i < end) : (i += 1) {
                    try new_l.items.append(self.allocator, target.list.items.items[@intCast(i)]);
                }
                return Value{ .list = new_l };
            } else if (target == .string) {
                const len: i64 = @intCast(target.string.bytes.len);
                var start = lower_i orelse 0;
                var end = upper_i orelse len;
                if (start < 0) start += len;
                if (end < 0) end += len;
                start = @max(0, @min(start, len));
                end = @max(0, @min(end, len));

                const sub_str = target.string.bytes[@intCast(start)..@intCast(end)];
                return Value.makeString(self.allocator, sub_str);
            }
            return error.TypeError;
        }
    }

    pub fn callValue(self: *Interpreter, callee: Value, args: []const Value, kwargs: []const DictEntry) anyerror!Value {
        switch (callee) {
            .bound_method => |bm| {
                var method_args = try self.allocator.alloc(Value, args.len + 1);
                method_args[0] = bm.instance;
                @memcpy(method_args[1..], args);
                return self.callValue(bm.function, method_args, kwargs);
            },
            .builtin => |b| {
                return b.func(self.allocator, null, args, kwargs);
            },
            .function => |f| {
                const parent_env: ?*Environment = if (f.closure_env) |ce| @ptrCast(@alignCast(ce)) else self.global_env;
                const call_env = try Environment.init(self.allocator, parent_env);

                // Bind parameters
                var arg_idx: usize = 0;
                for (f.param_names, 0..) |p_name, i| {
                    if (f.vararg != null and std.mem.eql(u8, p_name, f.vararg.?)) {
                        // Vararg *args collects remaining args into tuple
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
                            // Check kwargs
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

                const body_ptr: [*]const Stmt = @ptrCast(@alignCast(f.body_opaque));
                const res = try self.evalSuite(body_ptr[0..f.body_len], call_env);
                switch (res) {
                    .return_flow => |rf| return rf.*,
                    else => return .none,
                }
            },
            .class => |cls| {
                const instance = try PyInstance.init(self.allocator, cls);
                const inst_val = Value{ .instance = instance };

                if (cls.lookup("__init__")) |init_fn| {
                    var init_args = try self.allocator.alloc(Value, args.len + 1);
                    init_args[0] = inst_val;
                    @memcpy(init_args[1..], args);
                    _ = try self.callValue(init_fn, init_args, kwargs);
                }

                return inst_val;
            },
            else => return error.NotCallable,
        }
    }
};
