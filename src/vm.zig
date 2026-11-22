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
    chunk: *Chunk,
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

    pub fn runFunction(self: *VM, func: *PyFunction, chunk: *Chunk, args: []const Value, kwargs: []const DictEntry) anyerror!Value {
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

    pub fn runChunk(self: *VM, chunk: *Chunk, env: *Environment) anyerror!Value {
        const prev_sp = self.sp;
        const prev_frames = self.frame_count;

        self.push(.none); // placeholder callee
        const base_sp = self.sp;

        while (self.sp < base_sp + chunk.num_locals) {
            self.push(.none);
        }

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

                // Variables & Scopes (Generic)
                .op_load_fast => {
                    self.push(self.stack[frame.base_sp + inst.arg]);
                },
                .op_store_fast => {
                    const val = self.pop();
                    self.stack[frame.base_sp + inst.arg] = val;
                },
                .op_load_global => {
                    const name_idx = inst.arg;
                    if (name_idx < 128) {
                        if (frame.chunk.global_cache[name_idx]) |cached_val| {
                            self.push(cached_val);
                            continue;
                        }
                    }
                    const name = frame.chunk.names.items[name_idx];
                    const env = frame.env orelse self.interpreter.global_env;
                    if (env.get(name)) |val| {
                        if (name_idx < 128) frame.chunk.global_cache[name_idx] = val;
                        self.push(val);
                    } else if (self.interpreter.builtins_env.get(name)) |bv| {
                        if (name_idx < 128) frame.chunk.global_cache[name_idx] = bv;
                        self.push(bv);
                    } else {
                        return error.NameError;
                    }
                },
                .op_store_global => {
                    const val = self.pop();
                    const name_idx = inst.arg;
                    if (name_idx < 128) {
                        frame.chunk.global_cache[name_idx] = null;
                    }
                    const name = frame.chunk.names.items[name_idx];
                    const env = frame.env orelse self.interpreter.global_env;
                    try env.set(name, val);
                },

                // Superinstructions: Fast Register Access (slots 0..3)
                .op_load_fast_0 => self.push(self.stack[frame.base_sp]),
                .op_load_fast_1 => self.push(self.stack[frame.base_sp + 1]),
                .op_load_fast_2 => self.push(self.stack[frame.base_sp + 2]),
                .op_load_fast_3 => self.push(self.stack[frame.base_sp + 3]),

                .op_store_fast_0 => self.stack[frame.base_sp] = self.pop(),
                .op_store_fast_1 => self.stack[frame.base_sp + 1] = self.pop(),
                .op_store_fast_2 => self.stack[frame.base_sp + 2] = self.pop(),
                .op_store_fast_3 => self.stack[frame.base_sp + 3] = self.pop(),

                // Binary Arithmetic (Generic with Quickening)
                .op_add => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        frame.chunk.code.items[frame.ip - 1].op = .op_add_int;
                        self.push(Value.makeInt(a.int +% b.int));
                    } else if (a == .float and b == .float) {
                        frame.chunk.code.items[frame.ip - 1].op = .op_add_float;
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
                        frame.chunk.code.items[frame.ip - 1].op = .op_sub_int;
                        self.push(Value.makeInt(a.int -% b.int));
                    } else if (a == .float and b == .float) {
                        frame.chunk.code.items[frame.ip - 1].op = .op_sub_float;
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
                        frame.chunk.code.items[frame.ip - 1].op = .op_mul_int;
                        self.push(Value.makeInt(a.int *% b.int));
                    } else if (a == .float and b == .float) {
                        frame.chunk.code.items[frame.ip - 1].op = .op_mul_float;
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
                    if (a == .float and b == .float) {
                        frame.chunk.code.items[frame.ip - 1].op = .op_div_float;
                    }
                    self.push(Value.makeFloat(fa / fb));
                },
                .op_floor_div => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        if (b.int == 0) return error.ZeroDivisionError;
                        frame.chunk.code.items[frame.ip - 1].op = .op_floor_div_int;
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
                        frame.chunk.code.items[frame.ip - 1].op = .op_mod_int;
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

                // Specialized Integer Arithmetic (with Deoptimization Guards)
                .op_add_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeInt(a.int +% b.int));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_add;
                        if (a == .float and b == .float) {
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
                    }
                },
                .op_sub_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeInt(a.int -% b.int));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_sub;
                        if (a == .float and b == .float) {
                            self.push(Value.makeFloat(a.float - b.float));
                        } else if (a == .int and b == .float) {
                            self.push(Value.makeFloat(@as(f64, @floatFromInt(a.int)) - b.float));
                        } else if (a == .float and b == .int) {
                            self.push(Value.makeFloat(a.float - @as(f64, @floatFromInt(b.int))));
                        } else {
                            self.push(try self.interpreter.evalBinaryOp(a, .sub, b));
                        }
                    }
                },
                .op_mul_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeInt(a.int *% b.int));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_mul;
                        if (a == .float and b == .float) {
                            self.push(Value.makeFloat(a.float * b.float));
                        } else if (a == .int and b == .float) {
                            self.push(Value.makeFloat(@as(f64, @floatFromInt(a.int)) * b.float));
                        } else if (a == .float and b == .int) {
                            self.push(Value.makeFloat(a.float * @as(f64, @floatFromInt(b.int))));
                        } else {
                            self.push(try self.interpreter.evalBinaryOp(a, .mul, b));
                        }
                    }
                },
                .op_floor_div_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        if (b.int == 0) return error.ZeroDivisionError;
                        self.push(Value.makeInt(@divFloor(a.int, b.int)));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_floor_div;
                        self.push(try self.interpreter.evalBinaryOp(a, .floor_div, b));
                    }
                },
                .op_mod_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        if (b.int == 0) return error.ZeroDivisionError;
                        self.push(Value.makeInt(@mod(a.int, b.int)));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_mod;
                        self.push(try self.interpreter.evalBinaryOp(a, .mod, b));
                    }
                },

                // Specialized Float Arithmetic
                .op_add_float => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .float and b == .float) {
                        self.push(Value.makeFloat(a.float + b.float));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_add;
                        if (a == .int and b == .int) {
                            self.push(Value.makeInt(a.int +% b.int));
                        } else if (a == .int and b == .float) {
                            self.push(Value.makeFloat(@as(f64, @floatFromInt(a.int)) + b.float));
                        } else if (a == .float and b == .int) {
                            self.push(Value.makeFloat(a.float + @as(f64, @floatFromInt(b.int))));
                        } else {
                            self.push(try self.interpreter.evalBinaryOp(a, .add, b));
                        }
                    }
                },
                .op_sub_float => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .float and b == .float) {
                        self.push(Value.makeFloat(a.float - b.float));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_sub;
                        if (a == .int and b == .int) {
                            self.push(Value.makeInt(a.int -% b.int));
                        } else if (a == .int and b == .float) {
                            self.push(Value.makeFloat(@as(f64, @floatFromInt(a.int)) - b.float));
                        } else if (a == .float and b == .int) {
                            self.push(Value.makeFloat(a.float - @as(f64, @floatFromInt(b.int))));
                        } else {
                            self.push(try self.interpreter.evalBinaryOp(a, .sub, b));
                        }
                    }
                },
                .op_mul_float => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .float and b == .float) {
                        self.push(Value.makeFloat(a.float * b.float));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_mul;
                        if (a == .int and b == .int) {
                            self.push(Value.makeInt(a.int *% b.int));
                        } else if (a == .int and b == .float) {
                            self.push(Value.makeFloat(@as(f64, @floatFromInt(a.int)) * b.float));
                        } else if (a == .float and b == .int) {
                            self.push(Value.makeFloat(a.float * @as(f64, @floatFromInt(b.int))));
                        } else {
                            self.push(try self.interpreter.evalBinaryOp(a, .mul, b));
                        }
                    }
                },
                .op_div_float => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .float and b == .float) {
                        if (b.float == 0.0) return error.ZeroDivisionError;
                        self.push(Value.makeFloat(a.float / b.float));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_div;
                        const fa = if (a == .float) a.float else if (a == .int) @as(f64, @floatFromInt(a.int)) else return error.TypeError;
                        const fb = if (b == .float) b.float else if (b == .int) @as(f64, @floatFromInt(b.int)) else return error.TypeError;
                        if (fb == 0.0) return error.ZeroDivisionError;
                        self.push(Value.makeFloat(fa / fb));
                    }
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

                // Generic Comparisons with Quickening
                .op_eq, .op_ne, .op_lt, .op_le, .op_gt, .op_ge => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        const res = switch (inst.op) {
                            .op_eq => blk: {
                                frame.chunk.code.items[frame.ip - 1].op = .op_eq_int;
                                break :blk a.int == b.int;
                            },
                            .op_ne => blk: {
                                frame.chunk.code.items[frame.ip - 1].op = .op_ne_int;
                                break :blk a.int != b.int;
                            },
                            .op_lt => blk: {
                                frame.chunk.code.items[frame.ip - 1].op = .op_lt_int;
                                break :blk a.int < b.int;
                            },
                            .op_le => blk: {
                                frame.chunk.code.items[frame.ip - 1].op = .op_le_int;
                                break :blk a.int <= b.int;
                            },
                            .op_gt => blk: {
                                frame.chunk.code.items[frame.ip - 1].op = .op_gt_int;
                                break :blk a.int > b.int;
                            },
                            .op_ge => blk: {
                                frame.chunk.code.items[frame.ip - 1].op = .op_ge_int;
                                break :blk a.int >= b.int;
                            },
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

                // Specialized Integer Comparisons (with Deoptimization Guards)
                .op_lt_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeBool(a.int < b.int));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_lt;
                        self.push(Value.makeBool(self.interpreter.evalCompareOp(a, .lt, b)));
                    }
                },
                .op_le_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeBool(a.int <= b.int));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_le;
                        self.push(Value.makeBool(self.interpreter.evalCompareOp(a, .le, b)));
                    }
                },
                .op_gt_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeBool(a.int > b.int));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_gt;
                        self.push(Value.makeBool(self.interpreter.evalCompareOp(a, .gt, b)));
                    }
                },
                .op_ge_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeBool(a.int >= b.int));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_ge;
                        self.push(Value.makeBool(self.interpreter.evalCompareOp(a, .ge, b)));
                    }
                },
                .op_eq_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeBool(a.int == b.int));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_eq;
                        self.push(Value.makeBool(self.interpreter.evalCompareOp(a, .eq, b)));
                    }
                },
                .op_ne_int => {
                    const b = self.pop();
                    const a = self.pop();
                    if (a == .int and b == .int) {
                        self.push(Value.makeBool(a.int != b.int));
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_ne;
                        self.push(Value.makeBool(self.interpreter.evalCompareOp(a, .ne, b)));
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
                        return error.TypeError;
                    }
                    if (iter_val.iterator.kind == .range) {
                        frame.chunk.code.items[frame.ip - 1].op = .op_for_iter_range;
                        var r = &iter_val.iterator.kind.range;
                        if (r.step > 0) {
                            if (r.current < r.stop) {
                                const val = r.current;
                                r.current += r.step;
                                self.push(Value.makeInt(val));
                                continue;
                            }
                        } else if (r.step < 0) {
                            if (r.current > r.stop) {
                                const val = r.current;
                                r.current += r.step;
                                self.push(Value.makeInt(val));
                                continue;
                            }
                        }
                        _ = self.pop();
                        frame.ip = inst.arg;
                    } else {
                        if (iter_val.iterator.next(self.allocator)) |item| {
                            self.push(item);
                        } else {
                            _ = self.pop(); // pop exhausted iterator
                            frame.ip = inst.arg; // jump past loop
                        }
                    }
                },
                .op_for_iter_range => {
                    const iter_val = self.peek();
                    if (iter_val == .iterator and iter_val.iterator.kind == .range) {
                        var r = &iter_val.iterator.kind.range;
                        if (r.step > 0) {
                            if (r.current < r.stop) {
                                const val = r.current;
                                r.current += r.step;
                                self.push(Value.makeInt(val));
                                continue;
                            }
                        } else if (r.step < 0) {
                            if (r.current > r.stop) {
                                const val = r.current;
                                r.current += r.step;
                                self.push(Value.makeInt(val));
                                continue;
                            }
                        }
                        _ = self.pop();
                        frame.ip = inst.arg;
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_for_iter;
                        if (iter_val != .iterator) return error.TypeError;
                        if (iter_val.iterator.next(self.allocator)) |item| {
                            self.push(item);
                        } else {
                            _ = self.pop();
                            frame.ip = inst.arg;
                        }
                    }
                },

                // Subscripts & Attributes
                .op_get_subscript => {
                    const key = self.pop();
                    const target = self.pop();
                    if (target == .list and key == .int) {
                        frame.chunk.code.items[frame.ip - 1].op = .op_get_subscript_list;
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
                .op_get_subscript_list => {
                    const key = self.pop();
                    const target = self.pop();
                    if (target == .list and key == .int) {
                        const items = target.list.items.items;
                        const raw_idx = key.int;
                        if (raw_idx >= 0 and @as(usize, @intCast(raw_idx)) < items.len) {
                            self.push(items[@as(usize, @intCast(raw_idx))]);
                        } else {
                            const len = items.len;
                            const idx: usize = if (raw_idx < 0) @as(usize, @intCast(@as(i64, @intCast(len)) + raw_idx)) else @as(usize, @intCast(raw_idx));
                            if (idx >= len) return error.IndexError;
                            self.push(items[idx]);
                        }
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_get_subscript;
                        if (target == .tuple and key == .int) {
                            const len = target.tuple.items.len;
                            const idx: usize = if (key.int < 0) @as(usize, @intCast(@as(i64, @intCast(len)) + key.int)) else @as(usize, @intCast(key.int));
                            if (idx >= len) return error.IndexError;
                            self.push(target.tuple.items[idx]);
                        } else if (target == .dict) {
                            self.push(target.dict.get(key) orelse return error.KeyError);
                        } else {
                            self.push(try self.interpreter.evalSubscriptValue(target, key));
                        }
                    }
                },
                .op_set_subscript => {
                    const key = self.pop();
                    const target = self.pop();
                    const val = self.pop();
                    if (target == .list and key == .int) {
                        frame.chunk.code.items[frame.ip - 1].op = .op_set_subscript_list;
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
                .op_set_subscript_list => {
                    const key = self.pop();
                    const target = self.pop();
                    const val = self.pop();
                    if (target == .list and key == .int) {
                        const items = target.list.items.items;
                        const raw_idx = key.int;
                        if (raw_idx >= 0 and @as(usize, @intCast(raw_idx)) < items.len) {
                            items[@as(usize, @intCast(raw_idx))] = val;
                        } else {
                            const len = items.len;
                            const idx: usize = if (raw_idx < 0) @as(usize, @intCast(@as(i64, @intCast(len)) + raw_idx)) else @as(usize, @intCast(raw_idx));
                            if (idx >= len) return error.IndexError;
                            items[idx] = val;
                        }
                    } else {
                        frame.chunk.code.items[frame.ip - 1].op = .op_set_subscript;
                        if (target == .dict) {
                            try target.dict.put(self.allocator, key, val);
                        } else {
                            return error.TypeError;
                        }
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
                    const cache_idx = inst.arg;
                    const cache = &frame.chunk.ic_entries.items[cache_idx];
                    const name = frame.chunk.names.items[cache.name_idx];
                    if (target == .instance) {
                        var slot_found: ?u16 = null;
                        var i: u8 = 0;
                        while (i < target.instance.inline_count) : (i += 1) {
                            if (target.instance.inline_slots[i].name.ptr == name.ptr or std.mem.eql(u8, target.instance.inline_slots[i].name, name)) {
                                slot_found = i;
                                break;
                            }
                        }
                        if (slot_found) |s| {
                            cache.cached_class = @ptrCast(target.instance.class);
                            cache.slot_index = s;
                            frame.chunk.code.items[frame.ip - 1].op = .op_get_attr_cached;
                            self.push(target.instance.inline_slots[s].val);
                            continue;
                        }
                    }
                    self.push(try self.interpreter.evalAttribute(target, name));
                },
                .op_get_attr_cached => {
                    const target = self.pop();
                    const cache = &frame.chunk.ic_entries.items[inst.arg];
                    if (target == .instance and @as(?*anyopaque, @ptrCast(target.instance.class)) == cache.cached_class) {
                        const slot = cache.slot_index;
                        if (slot < target.instance.inline_count) {
                            self.push(target.instance.inline_slots[slot].val);
                            continue;
                        }
                    }
                    frame.chunk.code.items[frame.ip - 1].op = .op_get_attr;
                    const name = frame.chunk.names.items[cache.name_idx];
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

                    if (callee == .function and callee.function.chunk != null and callee.function.jit_entry == null) {
                        const fn_obj = callee.function;
                        const chunk: *Chunk = @ptrCast(@alignCast(fn_obj.chunk.?));
                        self.interpreter.jit.tryCompile(fn_obj, chunk);
                    }

                    if (callee == .function and callee.function.jit_entry != null) {
                        const fn_obj = callee.function;
                        if (fn_obj.jit_kind == 1 and argc == 1 and args[0] == .int) {
                            const NativeFn = *const fn (i64) callconv(.c) i64;
                            const native_fn: NativeFn = @ptrCast(fn_obj.jit_entry.?);
                            const res = native_fn(args[0].int);
                            self.sp -= (argc + 1);
                            self.push(Value.makeInt(res));
                            continue;
                        } else if (fn_obj.jit_kind == 2 and argc == 2 and args[0] == .int and args[1] == .int) {
                            const NativeFn = *const fn (i64, i64) callconv(.c) i64;
                            const native_fn: NativeFn = @ptrCast(fn_obj.jit_entry.?);
                            const res = native_fn(args[0].int, args[1].int);
                            self.sp -= (argc + 1);
                            self.push(Value.makeInt(res));
                            continue;
                        } else if (fn_obj.jit_kind == 3 and argc == 1 and args[0] == .list) {
                            const NativeFn = *const fn (*PyList) callconv(.c) *PyList;
                            const native_fn: NativeFn = @ptrCast(fn_obj.jit_entry.?);
                            const res = native_fn(args[0].list);
                            self.sp -= (argc + 1);
                            self.push(Value{ .list = res });
                            continue;
                        } else if (fn_obj.jit_kind == 4 and argc == 2 and (args[0] == .float or args[0] == .int) and args[1] == .int) {
                            const NativeFn = *const fn (f64, i64) callconv(.c) f64;
                            const native_fn: NativeFn = @ptrCast(fn_obj.jit_entry.?);
                            const x = if (args[0] == .float) args[0].float else @as(f64, @floatFromInt(args[0].int));
                            const res = native_fn(x, args[1].int);
                            self.sp -= (argc + 1);
                            self.push(Value.makeFloat(res));
                            continue;
                        }
                    }

                    if (callee == .function and callee.function.chunk != null and self.frame_count < self.frames.len) {
                        const fn_obj = callee.function;
                        const chunk: *Chunk = @ptrCast(@alignCast(fn_obj.chunk.?));
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
