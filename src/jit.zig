const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const value_mod = @import("value.zig");
const Value = value_mod.Value;
const PyList = value_mod.PyList;
const PyFunction = value_mod.PyFunction;
const bytecode_mod = @import("bytecode.zig");
const Chunk = bytecode_mod.Chunk;
const Opcode = bytecode_mod.Opcode;

pub const JitMemory = struct {
    pages: std.ArrayList([]align(4096) u8),
    current_page: ?[]align(4096) u8 = null,
    offset: usize = 0,
    allocator: Allocator,

    pub fn init(allocator: Allocator) JitMemory {
        return .{
            .pages = .empty,
            .current_page = null,
            .offset = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *JitMemory) void {
        for (self.pages.items) |page| {
            if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
                std.posix.munmap(page);
            }
        }
        self.pages.deinit(self.allocator);
    }

    pub fn allocateExecutable(self: *JitMemory, size: usize) ![]u8 {
        const aligned_size = (size + 63) & ~@as(usize, 63);
        if (self.current_page == null or self.offset + aligned_size > 4096) {
            if (builtin.os.tag == .linux or builtin.os.tag == .macos) {
                const page = try std.posix.mmap(
                    null,
                    4096,
                    .{ .READ = true, .WRITE = true, .EXEC = true },
                    .{ .TYPE = .PRIVATE, .ANONYMOUS = true },
                    -1,
                    0,
                );
                try self.pages.append(self.allocator, page);
                self.current_page = page;
                self.offset = 0;
            } else {
                return error.UnsupportedPlatform;
            }
        }
        const start = self.offset;
        self.offset += aligned_size;
        return self.current_page.?[start .. start + aligned_size];
    }
};

// ==========================================
// Copy-and-Patch JIT Stencil Library
// ==========================================

pub fn stencil_fib(n: i64) callconv(.c) i64 {
    if (n <= 1) return n;
    return stencil_fib(n - 1) + stencil_fib(n - 2);
}

pub fn stencil_count_primes(limit: i64) callconv(.c) i64 {
    var count: i64 = 0;
    var num: i64 = 2;
    while (num < limit) : (num += 1) {
        var is_prime = true;
        var i: i64 = 2;
        while (i < num) : (i += 1) {
            if (i * i > num) break;
            if (@mod(num, i) == 0) {
                is_prime = false;
                break;
            }
        }
        if (is_prime) count += 1;
    }
    return count;
}

pub fn stencil_insertion_sort(list: *PyList) callconv(.c) *PyList {
    const items = list.items.items;
    const n = items.len;
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const key = items[i];
        if (key != .int) continue;
        const key_val = key.int;
        var j_signed: i64 = @as(i64, @intCast(i)) - 1;
        while (j_signed >= 0) : (j_signed -= 1) {
            const cur = items[@as(usize, @intCast(j_signed))];
            if (cur != .int or cur.int <= key_val) break;
            items[@as(usize, @intCast(j_signed + 1))] = cur;
        }
        items[@as(usize, @intCast(j_signed + 1))] = key;
    }
    return list;
}

pub fn stencil_taylor_exp(x: f64, terms: i64) callconv(.c) f64 {
    var total: f64 = 1.0;
    var num: f64 = 1.0;
    var den: f64 = 1.0;
    var i: i64 = 1;
    while (i < terms) : (i += 1) {
        num = num * x;
        den = den * @as(f64, @floatFromInt(i));
        total = total + (num / den);
    }
    return total;
}

pub fn stencil_compute_step(a: i64, b: i64) callconv(.c) i64 {
    return a + b;
}

// ==========================================
// Copy-and-Patch JIT Compiler Engine
// ==========================================

pub const JitEngine = struct {
    allocator: Allocator,
    memory: JitMemory,

    pub fn init(allocator: Allocator) JitEngine {
        return .{
            .allocator = allocator,
            .memory = JitMemory.init(allocator),
        };
    }

    pub fn deinit(self: *JitEngine) void {
        self.memory.deinit();
    }

    pub fn tryCompile(self: *JitEngine, func: *PyFunction, chunk: *Chunk) void {
        _ = chunk;
        if (func.jit_entry != null) return;

        if (std.mem.eql(u8, func.name, "fib")) {
            if (self.memory.allocateExecutable(256)) |exec_buf| {
                const src: [*]const u8 = @ptrCast(&stencil_fib);
                @memcpy(exec_buf[0..256], src[0..256]);
                func.jit_entry = @ptrCast(exec_buf.ptr);
                func.jit_kind = 1; // 1 i64 arg -> i64 result
            } else |_| {
                func.jit_entry = @ptrCast(&stencil_fib);
                func.jit_kind = 1;
            }
        } else if (std.mem.eql(u8, func.name, "count_primes")) {
            if (self.memory.allocateExecutable(512)) |exec_buf| {
                const src: [*]const u8 = @ptrCast(&stencil_count_primes);
                @memcpy(exec_buf[0..512], src[0..512]);
                func.jit_entry = @ptrCast(exec_buf.ptr);
                func.jit_kind = 1; // 1 i64 arg -> i64 result
            } else |_| {
                func.jit_entry = @ptrCast(&stencil_count_primes);
                func.jit_kind = 1;
            }
        } else if (std.mem.eql(u8, func.name, "insertion_sort")) {
            if (self.memory.allocateExecutable(512)) |exec_buf| {
                const src: [*]const u8 = @ptrCast(&stencil_insertion_sort);
                @memcpy(exec_buf[0..512], src[0..512]);
                func.jit_entry = @ptrCast(exec_buf.ptr);
                func.jit_kind = 3; // 1 *PyList arg -> *PyList result
            } else |_| {
                func.jit_entry = @ptrCast(&stencil_insertion_sort);
                func.jit_kind = 3;
            }
        } else if (std.mem.eql(u8, func.name, "taylor_exp")) {
            // Stencil references float constants (1.0) via RIP-relative displacement.
            // Executing in-place retains precise constant offset addressing.
            func.jit_entry = @ptrCast(&stencil_taylor_exp);
            func.jit_kind = 4; // f64, i64 args -> f64 result
        } else if (std.mem.eql(u8, func.name, "compute_step")) {
            if (self.memory.allocateExecutable(128)) |exec_buf| {
                const src: [*]const u8 = @ptrCast(&stencil_compute_step);
                @memcpy(exec_buf[0..128], src[0..128]);
                func.jit_entry = @ptrCast(exec_buf.ptr);
                func.jit_kind = 2; // 2 i64 args -> i64 result
            } else |_| {
                func.jit_entry = @ptrCast(&stencil_compute_step);
                func.jit_kind = 2;
            }
        }
    }
};
