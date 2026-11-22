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
const PyIterator = value_mod.PyIterator;
const DictEntry = value_mod.DictEntry;
const ast_mod = @import("ast.zig");
const CompareOp = ast_mod.CompareOp;
const BinaryOp = ast_mod.BinaryOp;
const bytecode_mod = @import("bytecode.zig");
const Opcode = bytecode_mod.Opcode;
const Instruction = bytecode_mod.Instruction;
const Chunk = bytecode_mod.Chunk;
const environment_mod = @import("environment.zig");
const Environment = environment_mod.Environment;
const interpreter_mod = @import("interpreter.zig");
const Interpreter = interpreter_mod.Interpreter;

pub const CallFrame = struct {
    chunk: *const Chunk,
    ip: usize = 0,
    base_sp: usize = 0,
    env: ?*Environment = null,
};

pub const VM = struct {
    allocator: Allocator,
    interpreter: *Interpreter,
    stack: [16384]Value = undefined,
    sp: usize = 0,
    frames: [512]CallFrame = undefined,
    frame_count: usize = 0,

    pub fn init(allocator: Allocator, interpreter: *Interpreter) VM {
        return .{
            .allocator = allocator,
            .interpreter = interpreter,
            .sp = 0,
            .frame_count = 0,
        };
    }

    pub inline fn push(self: *VM, val: Value) void {
        self.stack[self.sp] = val;
        self.sp += 1;
    }

    pub inline fn pop(self: *VM) Value {
        self.sp -= 1;
        return self.stack[self.sp];
    }

    pub inline fn peek(self: *VM) Value {
        return self.stack[self.sp - 1];
    }

    pub fn runFunction(self: *VM, func: *PyFunction, chunk: *const Chunk, args: []const Value, kwargs: []const DictEntry) anyerror!Value {
        _ = kwargs;
        const prev_sp = self.sp;
        const prev_frames = self.frame_count;

        // Reserve callee slot on stack
        self.push(Value{ .function = func });
        const base_sp = self.sp;

        // Push arguments
        const bind_count = @min(args.len, func.param_names.len);
        for (0..bind_count) |i| {
            self.push(args[i]);
        }
        // Fill defaults if fewer arguments were passed
        for (bind_count..func.param_names.len) |i| {
            const def_val = if (i < func.defaults.len) func.defaults[i] else .none;
            self.push(def_val);
        }

        // Allocate slots for all function locals
        while (self.sp < base_sp + chunk.num_locals) {
            self.push(.none);
        }

        self.frames[self.frame_count] = .{
            .chunk = chunk,
            .ip = 0,
            .base_sp = base_sp,
            .env = if (func.closure_env) |ce| @ptrCast(@alignCast(ce)) else self.interpreter.global_env,
        };
        self.frame_count += 1;

        const res = self.execute() catch |err| {
            self.sp = prev_sp;
            self.frame_count = prev_frames;
            return err;
        };

        self.sp = prev_sp;
        self.frame_count = prev_frames;
        return res;
    }

    pub fn runChunk(self: *VM, chunk: *const Chunk, env: *Environment) anyerror!Value {
        const prev_sp = self.sp;
        const prev_frames = self.frame_count;

        self.push(.none); // placeholder callee
        const base_sp = self.sp;

        self.frames[self.frame_count] = .{
            .chunk = chunk,
            .ip = 0,
            .base_sp = base_sp,
            .env = env,
        };
        self.frame_count += 1;

        const res = self.execute() catch |err| {
            self.sp = prev_sp;
            self.frame_count = prev_frames;
            return err;
        };

        self.sp = prev_sp;
        self.frame_count = prev_frames;
        return res;
    }

    pub fn execute(self: *VM) anyerror!Value {
        const initial_frame_count = self.frame_count;
        if (initial_frame_count == 0) return .none;

        while (self.frame_count >= initial_frame_count) {
            var frame = &self.frames[self.frame_count - 1];
            if (frame.ip >= frame.chunk.code.items.len) {
                const ret_val = Value.none;
                self.sp = if (frame.base_sp > 0) frame.base_sp - 1 else 0;
                self.frame_count -= 1;
                if (self.frame_count < initial_frame_count) return ret_val;
                self.push(ret_val);
                continue;
            }

            const inst = frame.chunk.code.items[frame.ip];
            frame.ip += 1;

            switch (inst.op) {
                .op_pop => _ = self.pop(),
                .op_dup => self.push(self.peek()),
                .op_dup2 => {
                    const a = self.stack[self.sp - 2];
                    const b = self.stack[self.sp - 1];
                    self.push(a);
                    self.push(b);
                },
                .op_swap => {
                    const top = self.stack[self.sp - 1];
                    self.stack[self.sp - 1] = self.stack[self.sp - 2];
                    self.stack[self.sp - 2] = top;
                },
                .op_rot_three => {
                    const top = self.stack[self.sp - 1];
                    const mid = self.stack[self.sp - 2];
                    const bot = self.stack[self.sp - 3];
                    self.stack[self.sp - 3] = top;
                    self.stack[self.sp - 2] = bot;
                    self.stack[self.sp - 1] = mid;
                },
                .op_none => self.push(.none),
                .op_true => self.push(Value.makeBool(true)),
                .op_false => self.push(Value.makeBool(false)),
                .op_const => self.push(frame.chunk.constants.items[inst.arg]),

                // Variables & Scopes
                .op_load_fast => {
                    self.push(self.stack[frame.base_sp + inst.arg]);
                },
                .op_store_fast => {
                    const val = self.pop();
                    self.stack[frame.base_sp + inst.arg] = val;
                },
                .op_load_global => {
                    const name = frame.chunk.names.items[inst.arg];
                    const env = frame.env orelse self.interpreter.global_env;
                    if (env.get(name)) |val| {
                        self.push(val);
                    } else if (self.interpreter.builtins_env.get(name)) |bv| {
                        self.push(bv);
                    } else {
                        return error.NameError;
                    }
                },
                .op_store_global => {
                    const val = self.pop();
                    const name = frame.chunk.names.items[inst.arg];
                    const env = frame.env orelse self.interpreter.global_env;
                    try env.set(name, val);
                },

                // Binary Arithmetic
                .op_add => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeInt(a.int +% b.int));
                    } else if (a == .float and b == .float) {
                        self.push(Value.makeFloat(a.float + b.float));
                    } else if (a == .int and b == .float) {
                        self.push(Value.makeFloat(@as(f64, @floatFromInt(a.int)) + b.float));
                    } else if (a == .float and b == .int) {
                        self.push(Value.makeFloat(a.float + @as(f64, @floatFromInt(b.int))));
                    } else if (a == .string and b == .string) {
                        const cat = try PyString.concat(self.allocator, a.string.bytes, b.string.bytes);
                        self.push(Value{ .string = cat });
                    } else {
                        self.push(try self.interpreter.evalBinaryOp(a, .add, b));
                    }
                },
                .op_sub => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeInt(a.int -% b.int));
                    } else if (a == .float and b == .float) {
                        self.push(Value.makeFloat(a.float - b.float));
                    } else if (a == .int and b == .float) {
                        self.push(Value.makeFloat(@as(f64, @floatFromInt(a.int)) - b.float));
                    } else if (a == .float and b == .int) {
                        self.push(Value.makeFloat(a.float - @as(f64, @floatFromInt(b.int))));
                    } else {
                        self.push(try self.interpreter.evalBinaryOp(a, .sub, b));
                    }
                },
                .op_mul => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeInt(a.int *% b.int));
                    } else if (a == .float and b == .float) {
                        self.push(Value.makeFloat(a.float * b.float));
                    } else if (a == .int and b == .float) {
                        self.push(Value.makeFloat(@as(f64, @floatFromInt(a.int)) * b.float));
                    } else if (a == .float and b == .int) {
                        self.push(Value.makeFloat(a.float * @as(f64, @floatFromInt(b.int))));
                    } else {
                        self.push(try self.interpreter.evalBinaryOp(a, .mul, b));
                    }
                },
                .op_div => {
                    const b = self.pop();
                    const a = self.pop();
                    const fa = if (a == .float) a.float else if (a == .int) @as(f64, @floatFromInt(a.int)) else return error.TypeError;
                    const fb = if (b == .float) b.float else if (b == .int) @as(f64, @floatFromInt(b.int)) else return error.TypeError;
                    if (fb == 0.0) return error.ZeroDivisionError;
                    self.push(Value.makeFloat(fa / fb));
                },
                .op_floor_div => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        if (b.int == 0) return error.ZeroDivisionError;
                        self.push(Value.makeInt(@divFloor(a.int, b.int)));
                    } else {
                        self.push(try self.interpreter.evalBinaryOp(a, .floor_div, b));
                    }
                },
                .op_mod => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        if (b.int == 0) return error.ZeroDivisionError;
                        self.push(Value.makeInt(@mod(a.int, b.int)));
                    } else {
                        self.push(try self.interpreter.evalBinaryOp(a, .mod, b));
                    }
                },
                .op_pow => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(try self.interpreter.evalBinaryOp(a, .pow, b));
                },
                .op_bit_and => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeInt(a.int & b.int));
                    } else return error.TypeError;
                },
                .op_bit_or => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeInt(a.int | b.int));
                    } else return error.TypeError;
                },
                .op_bit_xor => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeInt(a.int ^ b.int));
                    } else return error.TypeError;
                },
                .op_lshift => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        const shift: u6 = @intCast(b.int & 63);
                        self.push(Value.makeInt(a.int << shift));
                    } else return error.TypeError;
                },
                .op_rshift => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        const shift: u6 = @intCast(b.int & 63);
                        self.push(Value.makeInt(a.int >> shift));
                    } else return error.TypeError;
                },

                // Unary
                .op_neg => {
                    const val = self.pop();
                    if (val == .int) {
                        self.push(Value.makeInt(-val.int));
                    } else if (val == .float) {
                        self.push(Value.makeFloat(-val.float));
                    } else return error.TypeError;
                },
                .op_not => {
                    const val = self.pop();
                    self.push(Value.makeBool(!val.isTruthy()));
                },
                .op_invert => {
                    const val = self.pop();
                    if (val == .int) {
                        self.push(Value.makeInt(~val.int));
                    } else return error.TypeError;
                },

                // Comparisons
                .op_eq, .op_ne, .op_lt, .op_le, .op_gt, .op_ge => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        const res = switch (inst.op) {
                            .op_eq => a.int == b.int,
                            .op_ne => a.int != b.int,
                            .op_lt => a.int < b.int,
                            .op_le => a.int <= b.int,
                            .op_gt => a.int > b.int,
                            .op_ge => a.int >= b.int,
                            else => unreachable,
                        };
                        self.push(Value.makeBool(res));
                    } else if (a == .float and b == .float) {
                        const res = switch (inst.op) {
                            .op_eq => a.float == b.float,
                            .op_ne => a.float != b.float,
                            .op_lt => a.float < b.float,
                            .op_le => a.float <= b.float,
                            .op_gt => a.float > b.float,
                            .op_ge => a.float >= b.float,
                            else => unreachable,
                        };
                        self.push(Value.makeBool(res));
                    } else {
                        const cmp_op: CompareOp = switch (inst.op) {
                            .op_eq => .eq,
                            .op_ne => .ne,
                            .op_lt => .lt,
                            .op_le => .le,
                            .op_gt => .gt,
                            .op_ge => .ge,
                            else => unreachable,
                        };
                        self.push(Value.makeBool(self.interpreter.evalCompareOp(a, cmp_op, b)));
                    }
                },
                .op_in => {
                    const container = self.pop();
                    const item = self.pop();
                    self.push(Value.makeBool(self.interpreter.evalCompareOp(item, .in, container)));
                },
                .op_not_in => {
                    const container = self.pop();
                    const item = self.pop();
                    self.push(Value.makeBool(self.interpreter.evalCompareOp(item, .not_in, container)));
                },
                .op_is => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.makeBool(a.equals(b)));
                },
                .op_is_not => {
                    const b = self.pop();
                    const a = self.pop();
                    self.push(Value.makeBool(!a.equals(b)));
                },

                // Control Flow & Branching
                .op_jump => {
                    frame.ip = inst.arg;
                },
                .op_jump_if_false => {
                    if (!self.peek().isTruthy()) {
                        frame.ip = inst.arg;
                    }
                },
                .op_pop_jump_if_false => {
                    const val = self.pop();
                    if (!val.isTruthy()) {
                        frame.ip = inst.arg;
                    }
                },
                .op_jump_if_true => {
                    if (self.peek().isTruthy()) {
                        frame.ip = inst.arg;
                    }
                },
                .op_pop_jump_if_true => {
                    const val = self.pop();
                    if (val.isTruthy()) {
                        frame.ip = inst.arg;
                    }
                },

                // Loops & Iteration
                .op_get_iter => {
                    const iterable = self.pop();
                    const iter_obj = try self.allocator.create(PyIterator);
                    switch (iterable) {
                        .range => |r| {
                            iter_obj.* = .{ .kind = .{ .range = .{ .current = r.start, .stop = r.stop, .step = r.step } } };
                        },
                        .list => |l| {
                            iter_obj.* = .{ .kind = .{ .list = .{ .list = l, .index = 0 } } };
                        },
                        .tuple => |t| {
                            iter_obj.* = .{ .kind = .{ .tuple = .{ .items = t.items, .index = 0 } } };
                        },
                        .set => |s| {
                            iter_obj.* = .{ .kind = .{ .set = .{ .items = s.items.items, .index = 0 } } };
                        },
                        .string => |s| {
                            iter_obj.* = .{ .kind = .{ .string = .{ .str = s.bytes, .index = 0 } } };
                        },
                        else => return error.TypeError,
                    }
                    self.push(Value{ .iterator = iter_obj });
                },
                .op_for_iter => {
                    const iter_val = self.peek();
                    if (iter_val != .iterator) {
                        std.debug.print("DEBUG FOR_ITER FAIL: sp={d}, base_sp={d}, val_type={s}\n", .{ self.sp, frame.base_sp, iter_val.typeName() });
                        return error.TypeError;
                    }
                    if (iter_val.iterator.next(self.allocator)) |item| {
                        self.push(item);
                    } else {
                        _ = self.pop(); // pop exhausted iterator
                        frame.ip = inst.arg; // jump past loop
                    }
                },

                // Subscripts & Attributes
                .op_get_subscript => {
                    const key = self.pop();
                    const target = self.pop();
                    if (target == .list and key == .int) {
                        const len = target.list.items.items.len;
                        const idx: usize = if (key.int < 0) @as(usize, @intCast(@as(i64, @intCast(len)) + key.int)) else @as(usize, @intCast(key.int));
                        if (idx >= len) return error.IndexError;
                        self.push(target.list.items.items[idx]);
                    } else if (target == .tuple and key == .int) {
                        const len = target.tuple.items.len;
                        const idx: usize = if (key.int < 0) @as(usize, @intCast(@as(i64, @intCast(len)) + key.int)) else @as(usize, @intCast(key.int));
                        if (idx >= len) return error.IndexError;
                        self.push(target.tuple.items[idx]);
                    } else if (target == .dict) {
                        self.push(target.dict.get(key) orelse return error.KeyError);
                    } else {
                        self.push(try self.interpreter.evalSubscriptValue(target, key));
                    }
                },
                .op_set_subscript => {
                    const key = self.pop();
                    const target = self.pop();
                    const val = self.pop();
                    if (target == .list and key == .int) {
                        const len = target.list.items.items.len;
                        const idx: usize = if (key.int < 0) @as(usize, @intCast(@as(i64, @intCast(len)) + key.int)) else @as(usize, @intCast(key.int));
                        if (idx >= len) return error.IndexError;
                        target.list.items.items[idx] = val;
                    } else if (target == .dict) {
                        try target.dict.put(self.allocator, key, val);
                    } else {
                        return error.TypeError;
                    }
                },
                .op_get_slice => {
                    const step = self.pop();
                    const upper = self.pop();
                    const lower = self.pop();
                    const target = self.pop();
                    self.push(try self.interpreter.evalSliceValues(target, lower, upper, step));
                },
                .op_get_attr => {
                    const target = self.pop();
                    const name = frame.chunk.names.items[inst.arg];
                    self.push(try self.interpreter.evalAttribute(target, name));
                },
                .op_set_attr => {
                    const val = self.pop();
                    const target = self.pop();
                    const name = frame.chunk.names.items[inst.arg];
                    if (target == .instance) {
                        try target.instance.setAttr(self.allocator, name, val);
                    } else {
                        return error.AttributeError;
                    }
                },

                // Collections
                .op_build_list => {
                    const count = inst.arg;
                    const list = try PyList.init(self.allocator);
                    const start_idx = self.sp - count;
                    for (self.stack[start_idx..self.sp]) |it| {
                        try list.append(self.allocator, it);
                    }
                    self.sp = start_idx;
                    self.push(Value{ .list = list });
                },
                .op_build_tuple => {
                    const count = inst.arg;
                    const items = try self.allocator.alloc(Value, count);
                    const start_idx = self.sp - count;
                    @memcpy(items, self.stack[start_idx..self.sp]);
                    self.sp = start_idx;
                    const tup = try self.allocator.create(PyTuple);
                    tup.* = .{ .items = items };
                    self.push(Value{ .tuple = tup });
                },
                .op_build_dict => {
                    const count = inst.arg;
                    const dict = try PyDict.init(self.allocator);
                    const start_idx = self.sp - count * 2;
                    var di: usize = 0;
                    while (di < count) : (di += 1) {
                        const k = self.stack[start_idx + di * 2];
                        const v = self.stack[start_idx + di * 2 + 1];
                        try dict.put(self.allocator, k, v);
                    }
                    self.sp = start_idx;
                    self.push(Value{ .dict = dict });
                },
                .op_build_set => {
                    const count = inst.arg;
                    const set = try PySet.init(self.allocator);
                    const start_idx = self.sp - count;
                    for (self.stack[start_idx..self.sp]) |it| {
                        try set.add(self.allocator, it);
                    }
                    self.sp = start_idx;
                    self.push(Value{ .set = set });
                },
                .op_list_append => {
                    const val = self.pop();
                    const list_val = self.stack[self.sp - 2];
                    if (list_val != .list) return error.TypeError;
                    try list_val.list.append(self.allocator, val);
                },
                .op_unpack_tuple => {
                    const count = inst.arg;
                    const tup_val = self.pop();
                    const items: []const Value = switch (tup_val) {
                        .tuple => |t| t.items,
                        .list => |l| l.items.items,
                        else => return error.TypeError,
                    };
                    if (items.len != count) return error.ValueError;
                    var ui: usize = count;
                    while (ui > 0) {
                        ui -= 1;
                        self.push(items[ui]);
                    }
                },

                // Functions & Execution
                .op_call => {
                    const argc = inst.arg;
                    const callee = self.stack[self.sp - argc - 1];
                    const args = self.stack[self.sp - argc .. self.sp];

                    if (callee == .function and callee.function.chunk != null and self.frame_count < self.frames.len) {
                        const fn_obj = callee.function;
                        const chunk: *const Chunk = @ptrCast(@alignCast(fn_obj.chunk.?));
                        const base_sp = self.sp - argc;

                        var param_idx: usize = argc;
                        while (param_idx < fn_obj.param_names.len) : (param_idx += 1) {
                            const def_val = if (param_idx < fn_obj.defaults.len) fn_obj.defaults[param_idx] else .none;
                            self.push(def_val);
                        }

                        // Allocate slots for all function locals
                        while (self.sp < base_sp + chunk.num_locals) {
                            self.push(.none);
                        }

                        self.frames[self.frame_count] = .{
                            .chunk = chunk,
                            .ip = 0,
                            .base_sp = base_sp,
                            .env = if (fn_obj.closure_env) |ce| @ptrCast(@alignCast(ce)) else self.interpreter.global_env,
                        };
                        self.frame_count += 1;
                        continue;
                    }

                    const result = try self.interpreter.callValue(callee, args, &[_]DictEntry{});
                    self.sp -= (argc + 1);
                    self.push(result);
                },
                .op_return => {
                    const ret_val = self.pop();
                    self.sp = if (frame.base_sp > 0) frame.base_sp - 1 else 0;
                    self.frame_count -= 1;
                    if (self.frame_count < initial_frame_count) {
                        return ret_val;
                    }
                    self.push(ret_val);
                },
                .op_format_value => {
                    const val = self.pop();
                    const str_bytes = try val.str(self.allocator);
                    const py_s = try PyString.init(self.allocator, str_bytes);
                    self.push(Value{ .string = py_s });
                },
                .op_build_string => {
                    const count = inst.arg;
                    const start_idx = self.sp - count;
                    var total_len: usize = 0;
                    for (self.stack[start_idx..self.sp]) |sv| {
                        if (sv == .string) total_len += sv.string.bytes.len;
                    }
                    var out = try self.allocator.alloc(u8, total_len);
                    var pos: usize = 0;
                    for (self.stack[start_idx..self.sp]) |sv| {
                        if (sv == .string) {
                            @memcpy(out[pos .. pos + sv.string.bytes.len], sv.string.bytes);
                            pos += sv.string.bytes.len;
                        }
                    }
                    self.sp = start_idx;
                    const py_s = try PyString.init(self.allocator, out);
                    self.push(Value{ .string = py_s });
                },
                .op_halt => {
                    return if (self.sp > 0) self.pop() else .none;
                },
            }
        }

        return .none;
    }
};
