const std = @import("std");
const Allocator = std.mem.Allocator;
const Interpreter = @import("interpreter.zig").Interpreter;
const Parser = @import("parser.zig").Parser;
const Value = @import("value.zig").Value;

fn writeStdout(bytes: []const u8) void {
    _ = std.posix.system.write(1, bytes.ptr, bytes.len);
}

const TermColor = struct {
    pub const amber = "\x1b[38;2;247;164;29m"; // Zig Golden Amber #F7A41D
    pub const blue = "\x1b[38;2;55;118;171m"; // Python Steel Blue #3776AB
    pub const jetbrains = "\x1b[38;2;88;166;255m"; // JetBrains Blue #58A6FF
    pub const green = "\x1b[38;2;76;175;80m"; // Success Green #4CAF50
    pub const red = "\x1b[38;2;239;83;80m"; // Error Red #EF5350
    pub const border = "\x1b[38;2;75;85;99m"; // Slate Border #4B5563
    pub const dim = "\x1b[90m";
    pub const bold = "\x1b[1m";
    pub const reset = "\x1b[0m";
};

fn printRepeated(bytes: []const u8, count: usize) void {
    var i: usize = 0;
    while (i < count) : (i += 1) {
        writeStdout(bytes);
    }
}

fn isTty(fd: i32) bool {
    const ws = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    };
    var w: ws = undefined;
    const TIOCGWINSZ = 0x5413;
    const rc = std.posix.system.ioctl(fd, TIOCGWINSZ, @intFromPtr(&w));
    return rc == 0;
}

fn getTerminalWidth() usize {
    const ws = extern struct {
        ws_row: u16,
        ws_col: u16,
        ws_xpixel: u16,
        ws_ypixel: u16,
    };
    var w: ws = undefined;
    const TIOCGWINSZ = 0x5413;
    const rc = std.posix.system.ioctl(1, TIOCGWINSZ, @intFromPtr(&w));
    if (rc == 0 and w.ws_col >= 40) {
        if (w.ws_col > 80) return 80;
        return @intCast(w.ws_col);
    }
    return 72;
}

fn getMonotonicNs() i128 {
    var ts: std.posix.timespec = undefined;
    _ = std.posix.system.clock_gettime(std.posix.system.CLOCK.MONOTONIC, &ts);
    return @as(i128, ts.sec) * 1_000_000_000 + ts.nsec;
}

fn formatDuration(buf: []u8, ns: i128) []const u8 {
    if (ns < 1_000) {
        return std.fmt.bufPrint(buf, "{d}ns", .{ns}) catch "0ns";
    } else if (ns < 1_000_000) {
        const us = @as(f64, @floatFromInt(ns)) / 1_000.0;
        return std.fmt.bufPrint(buf, "{d:.1}µs", .{us}) catch "0µs";
    } else if (ns < 1_000_000_000) {
        const ms = @as(f64, @floatFromInt(ns)) / 1_000_000.0;
        return std.fmt.bufPrint(buf, "{d:.2}ms", .{ms}) catch "0ms";
    } else {
        const s = @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
        return std.fmt.bufPrint(buf, "{d:.2}s", .{s}) catch "0s";
    }
}

fn printCellHeader(idx: usize) void {
    const width = getTerminalWidth();
    writeStdout(TermColor.border ++ "╭── " ++ TermColor.blue ++ TermColor.bold);
    var buf: [32]u8 = undefined;
    const label = std.fmt.bufPrint(&buf, "In [{d}]", .{idx}) catch "In [?]";
    writeStdout(label);
    writeStdout(TermColor.reset ++ TermColor.border ++ " ");
    const used = 4 + label.len + 1;
    if (width > used) {
        printRepeated("─", width - used);
    }
    writeStdout(TermColor.reset ++ "\n");
}

fn printOutputDivider(idx: usize) void {
    const width = getTerminalWidth();
    writeStdout(TermColor.border ++ "├── " ++ TermColor.green ++ TermColor.bold);
    var buf: [32]u8 = undefined;
    const label = std.fmt.bufPrint(&buf, "Out [{d}]", .{idx}) catch "Out [?]";
    writeStdout(label);
    writeStdout(TermColor.reset ++ TermColor.border ++ " ");
    const used = 4 + label.len + 1;
    if (width > used) {
        printRepeated("─", width - used);
    }
    writeStdout(TermColor.reset ++ "\n");
}

fn printErrorDivider(err_name: []const u8) void {
    const width = getTerminalWidth();
    writeStdout(TermColor.border ++ "├── " ++ TermColor.red ++ TermColor.bold ++ "✗ ");
    writeStdout(err_name);
    writeStdout(TermColor.reset ++ TermColor.border ++ " ");
    const used = 6 + err_name.len + 1;
    if (width > used) {
        printRepeated("─", width - used);
    }
    writeStdout(TermColor.reset ++ "\n");
}

fn printCellFooter(success: bool, dur_str: []const u8) void {
    const width = getTerminalWidth();
    writeStdout(TermColor.border ++ "╰── ");
    if (success) {
        writeStdout(TermColor.green ++ "✓ " ++ TermColor.reset);
    } else {
        writeStdout(TermColor.red ++ "✗ " ++ TermColor.reset);
    }
    writeStdout(TermColor.amber ++ "⚡ ");
    writeStdout(dur_str);
    writeStdout(TermColor.reset ++ TermColor.border ++ " ");
    const used = 4 + 2 + 2 + dur_str.len + 1;
    if (width > used) {
        printRepeated("─", width - used);
    }
    writeStdout(TermColor.reset ++ "\n\n");
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
    cell_counter: usize = 1,
    arena: std.heap.ArenaAllocator,

    pub fn init(allocator: Allocator, interpreter: *Interpreter) Repl {
        return .{
            .allocator = allocator,
            .interpreter = interpreter,
            .cell_counter = 1,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Repl) void {
        self.arena.deinit();
    }

    pub fn run(self: *Repl) !void {
        defer self.deinit();
        writeStdout("\n" ++ TermColor.amber ++ TermColor.bold ++ "⚡ Zython 0.10.0 " ++ TermColor.reset ++ TermColor.dim ++ "[Python 3.15 Engine • Zig 0.17.1]\n" ++ TermColor.reset);
        writeStdout(TermColor.dim ++ "Interactive Block Terminal • Type 'exit()' to exit\n\n" ++ TermColor.reset);

        var reader = LineReader{};
        var multiline_buf: std.ArrayList(u8) = .empty;
        defer multiline_buf.deinit(self.allocator);
        var indent_level: usize = 0;
        var cell_started = false;

        while (true) {
            const is_continuation = multiline_buf.items.len > 0;
            if (!cell_started) {
                printCellHeader(self.cell_counter);
                cell_started = true;
            }

            if (is_continuation) {
                writeStdout(TermColor.border ++ "│ " ++ TermColor.reset ++ TermColor.dim ++ "... " ++ TermColor.reset);
            } else {
                writeStdout(TermColor.border ++ "│ " ++ TermColor.reset ++ TermColor.amber ++ ">>> " ++ TermColor.reset);
            }

            const opt_line = try reader.readLine(self.allocator);
            if (opt_line == null) {
                // EOF (Ctrl+D)
                writeStdout("\n" ++ TermColor.border ++ "╰── " ++ TermColor.dim ++ "Session terminated" ++ TermColor.reset ++ "\n\n");
                break;
            }
            const raw_line = opt_line.?;
            defer self.allocator.free(raw_line);

            const trimmed = std.mem.trimEnd(u8, raw_line, "\r\n");

            if (!isTty(0)) {
                writeStdout(trimmed);
                writeStdout("\n");
            }

            if (!is_continuation and (std.mem.eql(u8, trimmed, "exit()") or
                std.mem.eql(u8, trimmed, "exit") or
                std.mem.eql(u8, trimmed, "quit()") or
                std.mem.eql(u8, trimmed, "quit")))
            {
                writeStdout(TermColor.border ++ "╰── " ++ TermColor.dim ++ "Session terminated" ++ TermColor.reset ++ "\n\n");
                break;
            }

            // If empty line on top-level prompt, keep waiting inside the same cell
            if (!is_continuation and trimmed.len == 0) {
                continue;
            }

            if (is_continuation and trimmed.len == 0) {
                // Empty line in multiline mode signals execution
                const src = multiline_buf.items;
                self.executeSource(src);
                multiline_buf.clearRetainingCapacity();
                indent_level = 0;
                cell_started = false;
                self.cell_counter += 1;
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
            cell_started = false;
            self.cell_counter += 1;
        }
    }

    fn executeSource(self: *Repl, src: []const u8) void {
        const a = self.arena.allocator();
        const persistent_src = a.dupe(u8, src) catch src;

        self.interpreter.last_error_msg = null;
        const t0 = getMonotonicNs();

        var parser = Parser.init(a, persistent_src) catch |err| {
            const t1 = getMonotonicNs();
            var dur_buf: [32]u8 = undefined;
            const dur_str = formatDuration(&dur_buf, t1 - t0);

            printErrorDivider("SyntaxError");
            writeStdout(TermColor.border ++ "│ " ++ TermColor.reset ++ TermColor.red ++ "▌ " ++ TermColor.reset ++ TermColor.red ++ "SyntaxError: " ++ TermColor.reset);
            if (err == error.UnterminatedString) {
                writeStdout("unterminated string literal (detected at end of line)\n");
            } else {
                writeStdout(@errorName(err));
                writeStdout("\n");
            }
            printCellFooter(false, dur_str);
            return;
        };
        defer parser.deinit();

        const stmts = parser.parseModule() catch |err| {
            const t1 = getMonotonicNs();
            var dur_buf: [32]u8 = undefined;
            const dur_str = formatDuration(&dur_buf, t1 - t0);

            printErrorDivider("SyntaxError");
            writeStdout(TermColor.border ++ "│ " ++ TermColor.reset ++ TermColor.red ++ "▌ " ++ TermColor.reset ++ TermColor.red ++ "SyntaxError: " ++ TermColor.reset);
            if (parser.last_error) |le| {
                writeStdout(le);
            } else {
                writeStdout(@errorName(err));
            }
            writeStdout("\n");
            printCellFooter(false, dur_str);
            return;
        };

        if (stmts.len == 0) {
            const t1 = getMonotonicNs();
            var dur_buf: [32]u8 = undefined;
            const dur_str = formatDuration(&dur_buf, t1 - t0);
            printCellFooter(true, dur_str);
            return;
        }

        // If single expr_stmt, print its repr like standard python REPL
        if (stmts.len == 1 and stmts[0] == .expr_stmt) {
            const val = self.interpreter.evalExpr(stmts[0].expr_stmt, self.interpreter.global_env) catch |err| {
                const t1 = getMonotonicNs();
                var dur_buf: [32]u8 = undefined;
                const dur_str = formatDuration(&dur_buf, t1 - t0);

                printErrorDivider(@errorName(err));
                writeStdout(TermColor.border ++ "│ " ++ TermColor.reset ++ TermColor.red ++ "▌ " ++ TermColor.reset ++ TermColor.red);
                writeStdout(@errorName(err));
                writeStdout(": " ++ TermColor.reset);
                if (self.interpreter.last_error_msg) |msg| {
                    writeStdout(msg);
                } else {
                    writeStdout(@errorName(err));
                }
                writeStdout("\n");
                printCellFooter(false, dur_str);
                return;
            };

            const t1 = getMonotonicNs();
            var dur_buf: [32]u8 = undefined;
            const dur_str = formatDuration(&dur_buf, t1 - t0);

            if (val != .none) {
                const rep = val.repr(a) catch "Error: repr failed";
                printOutputDivider(self.cell_counter);
                writeStdout(TermColor.border ++ "│ " ++ TermColor.reset);
                writeStdout(rep);
                writeStdout("\n");
            }
            printCellFooter(true, dur_str);
        } else {
            _ = self.interpreter.evalSuite(stmts, self.interpreter.global_env) catch |err| {
                const t1 = getMonotonicNs();
                var dur_buf: [32]u8 = undefined;
                const dur_str = formatDuration(&dur_buf, t1 - t0);

                printErrorDivider(@errorName(err));
                writeStdout(TermColor.border ++ "│ " ++ TermColor.reset ++ TermColor.red ++ "▌ " ++ TermColor.reset ++ TermColor.red);
                writeStdout(@errorName(err));
                writeStdout(": " ++ TermColor.reset);
                if (self.interpreter.last_error_msg) |msg| {
                    writeStdout(msg);
                } else {
                    writeStdout(@errorName(err));
                }
                writeStdout("\n");
                printCellFooter(false, dur_str);
                return;
            };

            const t1 = getMonotonicNs();
            var dur_buf: [32]u8 = undefined;
            const dur_str = formatDuration(&dur_buf, t1 - t0);
            printCellFooter(true, dur_str);
        }
    }
};
