const std = @import("std");
const Allocator = std.mem.Allocator;
const Interpreter = @import("interpreter.zig").Interpreter;
const Parser = @import("parser.zig").Parser;
const Value = @import("value.zig").Value;

fn writeStdout(bytes: []const u8) void {
    _ = std.posix.system.write(1, bytes.ptr, bytes.len);
}

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
        writeStdout("Zython 0.6.0 (Python 3.15 compatibility layer, Zig 0.17.1)\n");
        writeStdout("Type 'exit()' to exit.\n");

        var line_buf: [4096]u8 = undefined;
        var multiline_buf: std.ArrayList(u8) = .empty;
        defer multiline_buf.deinit(self.allocator);

        while (true) {
            const is_continuation = multiline_buf.items.len > 0;
            const prompt: []const u8 = if (is_continuation) "... " else ">>> ";
            writeStdout(prompt);

            const bytes_read = std.posix.system.read(0, &line_buf, line_buf.len);
            if (bytes_read <= 0) break; // EOF (Ctrl+D)

            const line = line_buf[0..@intCast(bytes_read)];
            const trimmed = std.mem.trimEnd(u8, line, "\r\n");

            if (!is_continuation and std.mem.eql(u8, trimmed, "exit()")) {
                break;
            }

            if (is_continuation and trimmed.len == 0) {
                // Empty line in multiline mode signals execution
                const src = multiline_buf.items;
                self.executeSource(src);
                multiline_buf.clearRetainingCapacity();
                continue;
            }

            if (is_continuation) {
                try multiline_buf.appendSlice(self.allocator, line);
                continue;
            }

            // Check if this line starts a block (e.g. ends with ':')
            if (std.mem.endsWith(u8, trimmed, ":")) {
                try multiline_buf.appendSlice(self.allocator, line);
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
