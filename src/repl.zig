const std = @import("std");
const Allocator = std.mem.Allocator;
const Interpreter = @import("interpreter.zig").Interpreter;
const Parser = @import("parser.zig").Parser;
const Value = @import("value.zig").Value;

fn writeStdout(bytes: []const u8) void {
    _ = std.posix.system.write(1, bytes.ptr, bytes.len);
}

const LineReader = struct {
    buf: [4096]u8 = undefined,
    start: usize = 0,
    end: usize = 0,

    pub fn readLine(self: *LineReader, allocator: Allocator) !?[]const u8 {
        var line: std.ArrayList(u8) = .empty;
        while (true) {
            if (self.start >= self.end) {
                const n = std.posix.system.read(0, &self.buf, self.buf.len);
                if (n <= 0) {
                    if (line.items.len > 0) return try line.toOwnedSlice(allocator);
                    return null;
                }
                self.start = 0;
                self.end = @intCast(n);
            }

            while (self.start < self.end) {
                const b = self.buf[self.start];
                self.start += 1;
                if (b == '\n') {
                    return try line.toOwnedSlice(allocator);
                }
                if (b != '\r') {
                    try line.append(allocator, b);
                }
            }
        }
    }
};

pub const Repl = struct {
    allocator: Allocator,
    interpreter: *Interpreter,

    pub fn init(allocator: Allocator, interpreter: *Interpreter) Repl {
        return .{
            .allocator = allocator,
            .interpreter = interpreter,
        };
    }

    pub fn run(self: *Repl) !void {
        writeStdout("Zython 0.7.0 (Python 3.15 compatibility layer, Zig 0.17.1)\n");
        writeStdout("Type 'exit()' to exit.\n");

        var reader = LineReader{};
        var multiline_buf: std.ArrayList(u8) = .empty;
        defer multiline_buf.deinit(self.allocator);
        var indent_level: usize = 0;

        while (true) {
            const is_continuation = multiline_buf.items.len > 0;
            if (is_continuation) {
                writeStdout("... ");
                var pi: usize = 0;
                while (pi < indent_level) : (pi += 1) {
                    writeStdout(" ");
                }
            } else {
                writeStdout(">>> ");
            }

            const opt_line = try reader.readLine(self.allocator);
            if (opt_line == null) break; // EOF (Ctrl+D)
            const raw_line = opt_line.?;
            defer self.allocator.free(raw_line);

            const trimmed = std.mem.trimEnd(u8, raw_line, "\r\n");

            if (!is_continuation and (std.mem.eql(u8, trimmed, "exit()") or
                std.mem.eql(u8, trimmed, "exit") or
                std.mem.eql(u8, trimmed, "quit()") or
                std.mem.eql(u8, trimmed, "quit")))
            {
                break;
            }

            if (is_continuation and trimmed.len == 0) {
                // Empty line in multiline mode signals execution
                const src = multiline_buf.items;
                self.executeSource(src);
                multiline_buf.clearRetainingCapacity();
                indent_level = 0;
                continue;
            }

            if (is_continuation) {
                var leading_spaces: usize = 0;
                while (leading_spaces < trimmed.len and (trimmed[leading_spaces] == ' ' or trimmed[leading_spaces] == '\t')) : (leading_spaces += 1) {}

                const content = std.mem.trimStart(u8, trimmed, " \t");
                if (std.mem.startsWith(u8, content, "else:") or
                    std.mem.startsWith(u8, content, "elif ") or
                    std.mem.startsWith(u8, content, "except") or
                    std.mem.startsWith(u8, content, "finally:"))
                {
                    if (indent_level >= 4) indent_level -= 4;
                }

                // Auto-pad leading spaces to match the visual indent level
                if (leading_spaces < indent_level and trimmed.len > 0) {
                    var pad = leading_spaces;
                    while (pad < indent_level) : (pad += 1) {
                        try multiline_buf.append(self.allocator, ' ');
                    }
                }

                try multiline_buf.appendSlice(self.allocator, raw_line);
                try multiline_buf.append(self.allocator, '\n');

                if (std.mem.endsWith(u8, trimmed, ":")) {
                    indent_level += 4;
                }
                continue;
            }

            // Check if this line starts a block (e.g. ends with ':')
            if (std.mem.endsWith(u8, trimmed, ":")) {
                try multiline_buf.appendSlice(self.allocator, raw_line);
                try multiline_buf.append(self.allocator, '\n');
                indent_level = 4;
                continue;
            }

            // Single line execution
            self.executeSource(trimmed);
        }

        writeStdout("\n");
    }

    fn executeSource(self: *Repl, src: []const u8) void {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const a = arena.allocator();

        var parser = Parser.init(a, src) catch |err| {
            std.debug.print("SyntaxError: {s}\n", .{@errorName(err)});
            return;
        };
        defer parser.deinit();

        const stmts = parser.parseModule() catch |err| {
            std.debug.print("SyntaxError: {s}\n", .{@errorName(err)});
            return;
        };

        if (stmts.len == 0) return;

        // If single expr_stmt, print its repr like standard python REPL
        if (stmts.len == 1 and stmts[0] == .expr_stmt) {
            const val = self.interpreter.evalExpr(stmts[0].expr_stmt, self.interpreter.global_env) catch |err| {
                std.debug.print("Error: {s}\n", .{@errorName(err)});
                return;
            };
            if (val != .none) {
                const rep = val.repr(a) catch return;
                writeStdout(rep);
                writeStdout("\n");
            }
        } else {
            _ = self.interpreter.evalSuite(stmts, self.interpreter.global_env) catch |err| {
                std.debug.print("Error: {s}\n", .{@errorName(err)});
            };
        }
    }
};
