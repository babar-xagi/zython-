const std = @import("std");
const Allocator = std.mem.Allocator;
const Interpreter = @import("interpreter.zig").Interpreter;
const Repl = @import("repl.zig").Repl;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buf: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;

    if (args.len <= 1) {
        // REPL mode
        const interp = try Interpreter.init(arena, args);
        var repl = Repl.init(arena, interp);
        try repl.run();
        return;
    }

    const first_arg = args[1];

    if (std.mem.eql(u8, first_arg, "-v") or std.mem.eql(u8, first_arg, "--version")) {
        try stdout.print("Zython 0.8.0 (Python 3.15.0 compatibility engine, built with Zig 0.17.1)\n", .{});
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, first_arg, "-h") or std.mem.eql(u8, first_arg, "--help")) {
        try stdout.print(
            \\usage: zython [option | script.py] [arg] ...
            \\Options and arguments:
            \\  -c cmd : program passed in as string
            \\  -v, --version : print the Python/Zython version and exit
            \\  -h, --help    : print this help message and exit
            \\  file          : program read from script file
            \\
        , .{});
        try stdout.flush();
        return;
    }

    if (std.mem.eql(u8, first_arg, "-c")) {
        if (args.len < 3) {
            try stdout.print("Argument expected for the -c option\n", .{});
            try stdout.flush();
            std.process.exit(2);
        }
        const cmd_str = args[2];
        const script_args = if (args.len > 2) args[2..] else args[0..0];
        const interp = try Interpreter.init(arena, script_args);
        _ = interp.evalSource(cmd_str) catch |err| {
            std.debug.print("RuntimeError: {s}\n", .{@errorName(err)});
            std.process.exit(1);
        };
        return;
    }

    // Execute script file
    const file_path = first_arg;
    const script_args = args[1..];

    const cwd = std.Io.Dir.cwd();
    const content = cwd.readFileAlloc(io, file_path, arena, .unlimited) catch |err| {
        std.debug.print("zython: can't open file '{s}': {s}\n", .{ file_path, @errorName(err) });
        std.process.exit(1);
    };

    const interp = try Interpreter.init(arena, script_args);
    _ = interp.evalSource(content) catch |err| {
        std.debug.print("RuntimeError: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

test "lexing python code" {
    const lexer_mod = @import("lexer.zig");
    const Lexer = lexer_mod.Lexer;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lex = Lexer.init(a, "x = 42\nif x > 10:\n    print(x)\n");
    defer lex.deinit();

    const t1 = try lex.nextToken();
    try std.testing.expectEqual(.identifier, t1.tag);
    try std.testing.expectEqualStrings("x", t1.lexeme);

    const t2 = try lex.nextToken();
    try std.testing.expectEqual(.equal, t2.tag);

    const t3 = try lex.nextToken();
    try std.testing.expectEqual(.int_lit, t3.tag);
}

test "value operations" {
    const value_mod = @import("value.zig");
    const Value = value_mod.Value;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const v1 = Value.makeInt(10);
    const v2 = Value.makeInt(20);
    try std.testing.expect(v1.isTruthy());
    try std.testing.expect(!Value.makeNone().isTruthy());
    try std.testing.expect(!v1.equals(v2));

    const s = try Value.makeString(a, "Zython");
    const rep = try s.repr(a);
    try std.testing.expectEqualStrings("'Zython'", rep);
}

test "interpreter execution" {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const interp = try Interpreter.init(a, &[_][:0]const u8{});
    const code =
        \\def square(x):
        \\    return x * x
        \\result = square(8)
    ;
    _ = try interp.evalSource(code);
    const res = interp.global_env.get("result");
    try std.testing.expect(res != null);
    try std.testing.expectEqual(@as(i64, 64), res.?.int);
}
