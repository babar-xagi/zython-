const std = @import("std");
const Allocator = std.mem.Allocator;
const token_mod = @import("token.zig");
const Token = token_mod.Token;
const TokenType = token_mod.TokenType;
const lexer_mod = @import("lexer.zig");
const Lexer = lexer_mod.Lexer;
const ast_mod = @import("ast.zig");
const Expr = ast_mod.Expr;
const Stmt = ast_mod.Stmt;
const BinaryOp = ast_mod.BinaryOp;
const UnaryOp = ast_mod.UnaryOp;
const CompareOp = ast_mod.CompareOp;
const BoolOp = ast_mod.BoolOp;
const Kwarg = ast_mod.Kwarg;
const SliceExpr = ast_mod.SliceExpr;
const Param = ast_mod.Param;
const ElifBranch = ast_mod.ElifBranch;
const ExceptHandler = ast_mod.ExceptHandler;
const value_mod = @import("value.zig");
const Value = value_mod.Value;

pub const Parser = struct {
    allocator: Allocator,
    lexer: Lexer,
    current: Token,
    previous: Token,

    pub fn init(allocator: Allocator, source: []const u8) !Parser {
        var lex = Lexer.init(allocator, source);
        const cur = try lex.nextToken();
        return Parser{
            .allocator = allocator,
            .lexer = lex,
            .current = cur,
            .previous = cur,
        };
    }

    pub fn deinit(self: *Parser) void {
        self.lexer.deinit();
    }

    fn advance(self: *Parser) !void {
        self.previous = self.current;
        self.current = try self.lexer.nextToken();
    }

    fn check(self: *Parser, tag: TokenType) bool {
        return self.current.tag == tag;
    }

    fn match(self: *Parser, tag: TokenType) !bool {
        if (self.check(tag)) {
            try self.advance();
            return true;
        }
        return false;
    }

    fn consume(self: *Parser, tag: TokenType, msg: []const u8) !Token {
        if (self.check(tag)) {
            try self.advance();
            return self.previous;
        }
        std.debug.print("Parser error at line {d}:{d}: expected {s}, got {s}. {s}\n", .{
            self.current.line,
            self.current.column,
            @tagName(tag),
            @tagName(self.current.tag),
            msg,
        });
        return error.ParseError;
    }

    fn skipNewlines(self: *Parser) !void {
        while (self.check(.newline) or self.check(.semicolon)) {
            try self.advance();
        }
    }

    pub fn parseModule(self: *Parser) ![]Stmt {
        var statements: std.ArrayList(Stmt) = .empty;
        try self.skipNewlines();

        while (!self.check(.eof)) {
            const stmt = try self.parseStmt();
            try statements.append(self.allocator, stmt);
            try self.skipNewlines();
        }

        return statements.items;
    }

    fn parseStmt(self: *Parser) anyerror!Stmt {
        if (try self.match(.kw_def)) return self.parseDef();
        if (try self.match(.kw_class)) return self.parseClass();
        if (try self.match(.kw_if)) return self.parseIf();
        if (try self.match(.kw_while)) return self.parseWhile();
        if (try self.match(.kw_for)) return self.parseFor();
        if (try self.match(.kw_try)) return self.parseTry();
        if (try self.match(.kw_return)) return self.parseReturn();
        if (try self.match(.kw_break)) return .break_stmt;
        if (try self.match(.kw_continue)) return .continue_stmt;
        if (try self.match(.kw_pass)) return .pass_stmt;
        if (try self.match(.kw_raise)) return self.parseRaise();
        if (try self.match(.kw_import)) return self.parseImport();
        if (try self.match(.kw_from)) return self.parseFromImport();
        if (try self.match(.kw_global)) return self.parseGlobal();
        if (try self.match(.kw_assert)) return self.parseAssert();

        return self.parseSimpleStmt();
    }

    fn parseSuite(self: *Parser) anyerror![]Stmt {
        _ = try self.consume(.colon, "Expected ':' before suite");

        if (try self.match(.newline)) {
            _ = try self.consume(.indent, "Expected indented block");
            var stmts: std.ArrayList(Stmt) = .empty;

            while (!self.check(.dedent) and !self.check(.eof)) {
                try self.skipNewlines();
                if (self.check(.dedent) or self.check(.eof)) break;
                const s = try self.parseStmt();
                try stmts.append(self.allocator, s);
                try self.skipNewlines();
            }

            _ = try self.consume(.dedent, "Expected dedent at end of block");
            return stmts.items;
        } else {
            // Single-line suite
            const s = try self.parseStmt();
            const single = try self.allocator.alloc(Stmt, 1);
            single[0] = s;
            return single;
        }
    }

    fn parseDef(self: *Parser) !Stmt {
        const name_tok = try self.consume(.identifier, "Expected function name");
        _ = try self.consume(.lparen, "Expected '(' after function name");

        var params: std.ArrayList(Param) = .empty;
        if (!self.check(.rparen)) {
            while (true) {
                var is_vararg = false;
                var is_kwarg = false;

                if (try self.match(.star_star)) {
                    is_kwarg = true;
                } else if (try self.match(.star)) {
                    is_vararg = true;
                }

                const p_tok = try self.consume(.identifier, "Expected parameter name");
                var default_expr: ?*Expr = null;

                // Optional type annotation e.g. x: int
                if (try self.match(.colon)) {
                    _ = try self.parseExpr();
                }

                if (try self.match(.equal)) {
                    default_expr = try self.parseExpr();
                }

                try params.append(self.allocator, .{
                    .name = p_tok.lexeme,
                    .default = default_expr,
                    .is_vararg = is_vararg,
                    .is_kwarg = is_kwarg,
                });

                if (!try self.match(.comma)) break;
                if (self.check(.rparen)) break;
            }
        }
        _ = try self.consume(.rparen, "Expected ')' after parameters");

        // Optional return type annotation e.g. -> int
        if (try self.match(.arrow)) {
            _ = try self.parseExpr();
        }

        const body = try self.parseSuite();
        return Stmt{
            .def_stmt = .{
                .name = name_tok.lexeme,
                .params = params.items,
                .body = body,
            },
        };
    }

    fn parseClass(self: *Parser) !Stmt {
        const name_tok = try self.consume(.identifier, "Expected class name");
        var bases: std.ArrayList(*Expr) = .empty;

        if (try self.match(.lparen)) {
            if (!self.check(.rparen)) {
                while (true) {
                    const base_expr = try self.parseExpr();
                    try bases.append(self.allocator, base_expr);
                    if (!try self.match(.comma)) break;
                    if (self.check(.rparen)) break;
                }
            }
            _ = try self.consume(.rparen, "Expected ')' after class bases");
        }

        const body = try self.parseSuite();
        return Stmt{
            .class_stmt = .{
                .name = name_tok.lexeme,
                .bases = bases.items,
                .body = body,
            },
        };
    }

    fn parseIf(self: *Parser) !Stmt {
        const cond = try self.parseExpr();
        const then_branch = try self.parseSuite();
        var elif_branches: std.ArrayList(ElifBranch) = .empty;
        var else_branch: ?[]Stmt = null;

        while (try self.match(.kw_elif)) {
            const elif_cond = try self.parseExpr();
            const elif_body = try self.parseSuite();
            try elif_branches.append(self.allocator, .{
                .condition = elif_cond,
                .body = elif_body,
            });
        }

        if (try self.match(.kw_else)) {
            else_branch = try self.parseSuite();
        }

        return Stmt{
            .if_stmt = .{
                .condition = cond,
                .then_branch = then_branch,
                .elif_branches = elif_branches.items,
                .else_branch = else_branch,
            },
        };
    }

    fn parseWhile(self: *Parser) !Stmt {
        const cond = try self.parseExpr();
        const body = try self.parseSuite();
        var else_branch: ?[]Stmt = null;
        if (try self.match(.kw_else)) {
            else_branch = try self.parseSuite();
        }
        return Stmt{
            .while_stmt = .{
                .condition = cond,
                .body = body,
                .else_branch = else_branch,
            },
        };
    }

    fn parseForTarget(self: *Parser) anyerror!*Expr {
        const first = try self.parseBitwiseOr();
        if (try self.match(.comma)) {
            var items: std.ArrayList(*Expr) = .empty;
            try items.append(self.allocator, first);
            while (true) {
                if (self.check(.kw_in)) break;
                const next_item = try self.parseBitwiseOr();
                try items.append(self.allocator, next_item);
                if (!try self.match(.comma)) break;
            }
            const node = try self.allocator.create(Expr);
            node.* = .{ .tuple_expr = items.items };
            return node;
        }
        return first;
    }

    fn parseFor(self: *Parser) !Stmt {
        const target = try self.parseForTarget();
        _ = try self.consume(.kw_in, "Expected 'in' in for loop");
        const iter = try self.parseExpr();
        const body = try self.parseSuite();
        var else_branch: ?[]Stmt = null;
        if (try self.match(.kw_else)) {
            else_branch = try self.parseSuite();
        }
        return Stmt{
            .for_stmt = .{
                .target = target,
                .iter = iter,
                .body = body,
                .else_branch = else_branch,
            },
        };
    }

    fn parseTry(self: *Parser) !Stmt {
        const body = try self.parseSuite();
        var handlers: std.ArrayList(ExceptHandler) = .empty;
        var else_branch: ?[]Stmt = null;
        var finally_branch: ?[]Stmt = null;

        while (try self.match(.kw_except)) {
            var exc_type: ?*Expr = null;
            var name: ?[]const u8 = null;

            if (!self.check(.colon)) {
                exc_type = try self.parseExpr();
                if (try self.match(.kw_as)) {
                    const n_tok = try self.consume(.identifier, "Expected variable name after 'as'");
                    name = n_tok.lexeme;
                }
            }

            const handler_body = try self.parseSuite();
            try handlers.append(self.allocator, .{
                .exc_type = exc_type,
                .name = name,
                .body = handler_body,
            });
        }

        if (try self.match(.kw_else)) {
            else_branch = try self.parseSuite();
        }
        if (try self.match(.kw_finally)) {
            finally_branch = try self.parseSuite();
        }

        return Stmt{
            .try_stmt = .{
                .body = body,
                .handlers = handlers.items,
                .else_branch = else_branch,
                .finally_branch = finally_branch,
            },
        };
    }

    fn parseReturn(self: *Parser) !Stmt {
        var expr: ?*Expr = null;
        if (!self.check(.newline) and !self.check(.semicolon) and !self.check(.eof)) {
            expr = try self.parseExpr();
        }
        return Stmt{ .return_stmt = expr };
    }

    fn parseRaise(self: *Parser) !Stmt {
        var expr: ?*Expr = null;
        if (!self.check(.newline) and !self.check(.semicolon) and !self.check(.eof)) {
            expr = try self.parseExpr();
        }
        return Stmt{ .raise_stmt = expr };
    }

    fn parseImport(self: *Parser) !Stmt {
        const mod_tok = try self.consume(.identifier, "Expected module name after 'import'");
        var as_name: ?[]const u8 = null;
        if (try self.match(.kw_as)) {
            const as_tok = try self.consume(.identifier, "Expected alias name after 'as'");
            as_name = as_tok.lexeme;
        }
        return Stmt{
            .import_stmt = .{
                .module_name = mod_tok.lexeme,
                .as_name = as_name,
            },
        };
    }

    fn parseFromImport(self: *Parser) !Stmt {
        const mod_tok = try self.consume(.identifier, "Expected module name after 'from'");
        _ = try self.consume(.kw_import, "Expected 'import' after module name");

        var names: std.ArrayList([]const u8) = .empty;
        var as_names: std.ArrayList(?[]const u8) = .empty;

        while (true) {
            const n_tok = try self.consume(.identifier, "Expected imported name");
            try names.append(self.allocator, n_tok.lexeme);

            var as_name: ?[]const u8 = null;
            if (try self.match(.kw_as)) {
                const as_tok = try self.consume(.identifier, "Expected alias after 'as'");
                as_name = as_tok.lexeme;
            }
            try as_names.append(self.allocator, as_name);

            if (!try self.match(.comma)) break;
        }

        return Stmt{
            .import_from_stmt = .{
                .module_name = mod_tok.lexeme,
                .names = names.items,
                .as_names = as_names.items,
            },
        };
    }

    fn parseGlobal(self: *Parser) !Stmt {
        var names: std.ArrayList([]const u8) = .empty;
        while (true) {
            const n_tok = try self.consume(.identifier, "Expected variable name in global statement");
            try names.append(self.allocator, n_tok.lexeme);
            if (!try self.match(.comma)) break;
        }
        return Stmt{ .global_stmt = names.items };
    }

    fn parseAssert(self: *Parser) !Stmt {
        const cond = try self.parseExpr();
        var msg: ?*Expr = null;
        if (try self.match(.comma)) {
            msg = try self.parseExpr();
        }
        return Stmt{
            .assert_stmt = .{
                .condition = cond,
                .message = msg,
            },
        };
    }

    fn parseSimpleStmt(self: *Parser) !Stmt {
        var first = try self.parseExpr();
        if (try self.match(.comma)) {
            var items: std.ArrayList(*Expr) = .empty;
            try items.append(self.allocator, first);
            while (true) {
                const next_item = try self.parseExpr();
                try items.append(self.allocator, next_item);
                if (!try self.match(.comma)) break;
            }
            const tup_node = try self.allocator.create(Expr);
            tup_node.* = .{ .tuple_expr = items.items };
            first = tup_node;
        }

        // Check for aug_assign
        const aug_op: ?BinaryOp = if (try self.match(.plus_equal))
            .add
        else if (try self.match(.minus_equal))
            .sub
        else if (try self.match(.star_equal))
            .mul
        else if (try self.match(.slash_equal))
            .div
        else if (try self.match(.slash_slash_equal))
            .floor_div
        else if (try self.match(.percent_equal))
            .mod
        else if (try self.match(.star_star_equal))
            .pow
        else if (try self.match(.amp_equal))
            .bit_and
        else if (try self.match(.pipe_equal))
            .bit_or
        else if (try self.match(.caret_equal))
            .bit_xor
        else if (try self.match(.lshift_equal))
            .lshift
        else if (try self.match(.rshift_equal))
            .rshift
        else
            null;

        if (aug_op) |op| {
            const value = try self.parseExpr();
            return Stmt{
                .aug_assign = .{
                    .target = first,
                    .op = op,
                    .value = value,
                },
            };
        }

        // Check for standard assign =
        if (try self.match(.equal)) {
            var targets: std.ArrayList(*Expr) = .empty;
            try targets.append(self.allocator, first);

            var next_expr = try self.parseExpr();
            if (try self.match(.comma)) {
                var items: std.ArrayList(*Expr) = .empty;
                try items.append(self.allocator, next_expr);
                while (true) {
                    const next_item = try self.parseExpr();
                    try items.append(self.allocator, next_item);
                    if (!try self.match(.comma)) break;
                }
                const tup_node = try self.allocator.create(Expr);
                tup_node.* = .{ .tuple_expr = items.items };
                next_expr = tup_node;
            }

            while (try self.match(.equal)) {
                try targets.append(self.allocator, next_expr);
                next_expr = try self.parseExpr();
                if (try self.match(.comma)) {
                    var items: std.ArrayList(*Expr) = .empty;
                    try items.append(self.allocator, next_expr);
                    while (true) {
                        const next_item = try self.parseExpr();
                        try items.append(self.allocator, next_item);
                        if (!try self.match(.comma)) break;
                    }
                    const tup_node = try self.allocator.create(Expr);
                    tup_node.* = .{ .tuple_expr = items.items };
                    next_expr = tup_node;
                }
            }

            return Stmt{
                .assign = .{
                    .targets = targets.items,
                    .value = next_expr,
                },
            };
        }

        return Stmt{ .expr_stmt = first };
    }

    // Expression parsing (Pratt precedence)
    pub fn parseExpr(self: *Parser) anyerror!*Expr {
        return self.parseTernary();
    }

    fn parseTernary(self: *Parser) anyerror!*Expr {
        const expr = try self.parseLambda();
        if (try self.match(.kw_if)) {
            const cond = try self.parseExpr();
            _ = try self.consume(.kw_else, "Expected 'else' in conditional expression");
            const else_val = try self.parseExpr();
            const node = try self.allocator.create(Expr);
            node.* = .{
                .ternary = .{
                    .if_val = expr,
                    .condition = cond,
                    .else_val = else_val,
                },
            };
            return node;
        }
        return expr;
    }

    fn parseLambda(self: *Parser) anyerror!*Expr {
        if (try self.match(.kw_lambda)) {
            var params: std.ArrayList([]const u8) = .empty;
            if (!self.check(.colon)) {
                while (true) {
                    const p_tok = try self.consume(.identifier, "Expected parameter name in lambda");
                    try params.append(self.allocator, p_tok.lexeme);
                    if (!try self.match(.comma)) break;
                }
            }
            _ = try self.consume(.colon, "Expected ':' after lambda arguments");
            const body = try self.parseExpr();
            const node = try self.allocator.create(Expr);
            node.* = .{
                .lambda = .{
                    .params = params.items,
                    .body = body,
                },
            };
            return node;
        }
        return self.parseOr();
    }

    fn parseOr(self: *Parser) anyerror!*Expr {
        var expr = try self.parseAnd();
        while (try self.match(.kw_or)) {
            const right = try self.parseAnd();
            var vals = try self.allocator.alloc(*Expr, 2);
            vals[0] = expr;
            vals[1] = right;
            const node = try self.allocator.create(Expr);
            node.* = .{ .bool_op = .{ .op = .op_or, .values = vals } };
            expr = node;
        }
        return expr;
    }

    fn parseAnd(self: *Parser) anyerror!*Expr {
        var expr = try self.parseNot();
        while (try self.match(.kw_and)) {
            const right = try self.parseNot();
            var vals = try self.allocator.alloc(*Expr, 2);
            vals[0] = expr;
            vals[1] = right;
            const node = try self.allocator.create(Expr);
            node.* = .{ .bool_op = .{ .op = .op_and, .values = vals } };
            expr = node;
        }
        return expr;
    }

    fn parseNot(self: *Parser) anyerror!*Expr {
        if (try self.match(.kw_not)) {
            const expr = try self.parseNot();
            const node = try self.allocator.create(Expr);
            node.* = .{ .unary = .{ .op = .not, .expr = expr } };
            return node;
        }
        return self.parseComparison();
    }

    fn parseComparison(self: *Parser) anyerror!*Expr {
        const expr = try self.parseBitwiseOr();

        var ops: std.ArrayList(CompareOp) = .empty;
        var rights: std.ArrayList(*Expr) = .empty;

        while (true) {
            var op: ?CompareOp = null;
            if (try self.match(.equal_equal)) op = .eq;
            if (op == null and try self.match(.not_equal)) op = .ne;
            if (op == null and try self.match(.less_equal)) op = .le;
            if (op == null and try self.match(.less)) op = .lt;
            if (op == null and try self.match(.greater_equal)) op = .ge;
            if (op == null and try self.match(.greater)) op = .gt;
            if (op == null and try self.match(.kw_in)) op = .in;
            if (op == null and try self.match(.kw_is)) {
                if (try self.match(.kw_not)) {
                    op = .is_not;
                } else {
                    op = .is;
                }
            }

            if (op) |cmp_op| {
                const right = try self.parseBitwiseOr();
                try ops.append(self.allocator, cmp_op);
                try rights.append(self.allocator, right);
            } else {
                break;
            }
        }

        if (ops.items.len > 0) {
            const node = try self.allocator.create(Expr);
            node.* = .{
                .compare = .{
                    .left = expr,
                    .ops = ops.items,
                    .rights = rights.items,
                },
            };
            return node;
        }

        return expr;
    }

    fn parseBitwiseOr(self: *Parser) anyerror!*Expr {
        var expr = try self.parseBitwiseXor();
        while (try self.match(.pipe)) {
            const right = try self.parseBitwiseXor();
            const node = try self.allocator.create(Expr);
            node.* = .{ .binary = .{ .left = expr, .op = .bit_or, .right = right } };
            expr = node;
        }
        return expr;
    }

    fn parseBitwiseXor(self: *Parser) anyerror!*Expr {
        var expr = try self.parseBitwiseAnd();
        while (try self.match(.caret)) {
            const right = try self.parseBitwiseAnd();
            const node = try self.allocator.create(Expr);
            node.* = .{ .binary = .{ .left = expr, .op = .bit_xor, .right = right } };
            expr = node;
        }
        return expr;
    }

    fn parseBitwiseAnd(self: *Parser) anyerror!*Expr {
        var expr = try self.parseShift();
        while (try self.match(.ampersand)) {
            const right = try self.parseShift();
            const node = try self.allocator.create(Expr);
            node.* = .{ .binary = .{ .left = expr, .op = .bit_and, .right = right } };
            expr = node;
        }
        return expr;
    }

    fn parseShift(self: *Parser) anyerror!*Expr {
        var expr = try self.parseAddition();
        while (true) {
            var op: ?BinaryOp = null;
            if (try self.match(.lshift)) op = .lshift;
            if (op == null and try self.match(.rshift)) op = .rshift;

            if (op) |bin_op| {
                const right = try self.parseAddition();
                const node = try self.allocator.create(Expr);
                node.* = .{ .binary = .{ .left = expr, .op = bin_op, .right = right } };
                expr = node;
            } else break;
        }
        return expr;
    }

    fn parseAddition(self: *Parser) anyerror!*Expr {
        var expr = try self.parseMultiplication();
        while (true) {
            var op: ?BinaryOp = null;
            if (try self.match(.plus)) op = .add;
            if (op == null and try self.match(.minus)) op = .sub;

            if (op) |bin_op| {
                const right = try self.parseMultiplication();
                const node = try self.allocator.create(Expr);
                node.* = .{ .binary = .{ .left = expr, .op = bin_op, .right = right } };
                expr = node;
            } else break;
        }
        return expr;
    }

    fn parseMultiplication(self: *Parser) anyerror!*Expr {
        var expr = try self.parseUnary();
        while (true) {
            var op: ?BinaryOp = null;
            if (try self.match(.star)) op = .mul;
            if (op == null and try self.match(.slash_slash)) op = .floor_div;
            if (op == null and try self.match(.slash)) op = .div;
            if (op == null and try self.match(.percent)) op = .mod;

            if (op) |bin_op| {
                const right = try self.parseUnary();
                const node = try self.allocator.create(Expr);
                node.* = .{ .binary = .{ .left = expr, .op = bin_op, .right = right } };
                expr = node;
            } else break;
        }
        return expr;
    }

    fn parseUnary(self: *Parser) anyerror!*Expr {
        if (try self.match(.plus)) {
            const expr = try self.parseUnary();
            const node = try self.allocator.create(Expr);
            node.* = .{ .unary = .{ .op = .plus, .expr = expr } };
            return node;
        }
        if (try self.match(.minus)) {
            const expr = try self.parseUnary();
            const node = try self.allocator.create(Expr);
            node.* = .{ .unary = .{ .op = .minus, .expr = expr } };
            return node;
        }
        if (try self.match(.tilde)) {
            const expr = try self.parseUnary();
            const node = try self.allocator.create(Expr);
            node.* = .{ .unary = .{ .op = .invert, .expr = expr } };
            return node;
        }
        return self.parsePower();
    }

    fn parsePower(self: *Parser) anyerror!*Expr {
        var expr = try self.parseCall();
        if (try self.match(.star_star)) {
            const right = try self.parseUnary(); // right-associative
            const node = try self.allocator.create(Expr);
            node.* = .{ .binary = .{ .left = expr, .op = .pow, .right = right } };
            expr = node;
        }
        return expr;
    }

    fn parseCall(self: *Parser) anyerror!*Expr {
        var expr = try self.parsePrimary();

        while (true) {
            if (try self.match(.lparen)) {
                var args: std.ArrayList(*Expr) = .empty;
                var kwargs: std.ArrayList(Kwarg) = .empty;

                if (!self.check(.rparen)) {
                    while (true) {
                        // Check if keyword arg: identifier = expr
                        if (self.check(.identifier)) {
                            const name_tok = self.current;
                            // Look ahead if '=' follows
                            var temp_lex = self.lexer;
                            const next_tok = try temp_lex.nextToken();
                            if (next_tok.tag == .equal) {
                                try self.advance(); // consume identifier
                                try self.advance(); // consume '='
                                const val_expr = try self.parseExpr();
                                try kwargs.append(self.allocator, .{
                                    .name = name_tok.lexeme,
                                    .value = val_expr,
                                });
                                if (!try self.match(.comma)) break;
                                if (self.check(.rparen)) break;
                                continue;
                            }
                        }

                        const arg = try self.parseExpr();
                        try args.append(self.allocator, arg);
                        if (!try self.match(.comma)) break;
                        if (self.check(.rparen)) break;
                    }
                }
                _ = try self.consume(.rparen, "Expected ')' after call arguments");
                const node = try self.allocator.create(Expr);
                node.* = .{
                    .call = .{
                        .callee = expr,
                        .args = args.items,
                        .kwargs = kwargs.items,
                    },
                };
                expr = node;
            } else if (try self.match(.dot)) {
                const attr_tok = try self.consume(.identifier, "Expected attribute name after '.'");
                const node = try self.allocator.create(Expr);
                node.* = .{
                    .attribute = .{
                        .value = expr,
                        .attr = attr_tok.lexeme,
                    },
                };
                expr = node;
            } else if (try self.match(.lbracket)) {
                var lower: ?*Expr = null;
                var upper: ?*Expr = null;
                var step: ?*Expr = null;
                var is_index = true;

                if (!self.check(.colon)) {
                    lower = try self.parseExpr();
                }

                if (try self.match(.colon)) {
                    is_index = false;
                    if (!self.check(.rbracket) and !self.check(.colon)) {
                        upper = try self.parseExpr();
                    }
                    if (try self.match(.colon)) {
                        if (!self.check(.rbracket)) {
                            step = try self.parseExpr();
                        }
                    }
                }

                _ = try self.consume(.rbracket, "Expected ']' after slice or index");
                const slice_node = try self.allocator.create(SliceExpr);
                slice_node.* = .{
                    .lower = lower,
                    .upper = upper,
                    .step = step,
                    .is_index = is_index,
                };
                const node = try self.allocator.create(Expr);
                node.* = .{
                    .subscript = .{
                        .value = expr,
                        .slice = slice_node,
                    },
                };
                expr = node;
            } else {
                break;
            }
        }

        return expr;
    }

    fn parsePrimary(self: *Parser) anyerror!*Expr {
        const node = try self.allocator.create(Expr);

        if (try self.match(.kw_none)) {
            node.* = .{ .literal = .none };
            return node;
        }
        if (try self.match(.kw_true)) {
            node.* = .{ .literal = .{ .bool = true } };
            return node;
        }
        if (try self.match(.kw_false)) {
            node.* = .{ .literal = .{ .bool = false } };
            return node;
        }
        if (try self.match(.int_lit)) {
            const lex = self.previous.lexeme;
            var num: i64 = 0;
            if (std.mem.startsWith(u8, lex, "0x") or std.mem.startsWith(u8, lex, "0X")) {
                num = try std.fmt.parseInt(i64, lex[2..], 16);
            } else if (std.mem.startsWith(u8, lex, "0b") or std.mem.startsWith(u8, lex, "0B")) {
                num = try std.fmt.parseInt(i64, lex[2..], 2);
            } else if (std.mem.startsWith(u8, lex, "0o") or std.mem.startsWith(u8, lex, "0O")) {
                num = try std.fmt.parseInt(i64, lex[2..], 8);
            } else {
                num = try std.fmt.parseInt(i64, lex, 10);
            }
            node.* = .{ .literal = .{ .int = num } };
            return node;
        }
        if (try self.match(.float_lit)) {
            const f = try std.fmt.parseFloat(f64, self.previous.lexeme);
            node.* = .{ .literal = .{ .float = f } };
            return node;
        }
        if (try self.match(.string_lit)) {
            const s = try Value.makeString(self.allocator, self.previous.lexeme);
            node.* = .{ .literal = s };
            return node;
        }
        if (try self.match(.fstring_lit)) {
            const lex = self.previous.lexeme;
            var parts: std.ArrayList(*Expr) = .empty;
            var i: usize = 0;
            var literal_start: usize = 0;
            while (i < lex.len) {
                if (lex[i] == '{') {
                    if (i > literal_start) {
                        const lit_str = lex[literal_start..i];
                        const lit_node = try self.allocator.create(Expr);
                        const val = try Value.makeString(self.allocator, lit_str);
                        lit_node.* = .{ .literal = val };
                        try parts.append(self.allocator, lit_node);
                    }
                    i += 1;
                    const expr_start = i;
                    var depth: usize = 1;
                    while (i < lex.len and depth > 0) : (i += 1) {
                        if (lex[i] == '{') depth += 1;
                        if (lex[i] == '}') {
                            depth -= 1;
                            if (depth == 0) break;
                        }
                    }
                    const expr_str = lex[expr_start..i];
                    if (i < lex.len and lex[i] == '}') i += 1;
                    literal_start = i;

                    var sub_parser = try Parser.init(self.allocator, expr_str);
                    defer sub_parser.deinit();
                    const parsed_expr = try sub_parser.parseExpr();
                    try parts.append(self.allocator, parsed_expr);
                } else {
                    i += 1;
                }
            }
            if (literal_start < lex.len) {
                const lit_str = lex[literal_start..lex.len];
                const lit_node = try self.allocator.create(Expr);
                const val = try Value.makeString(self.allocator, lit_str);
                lit_node.* = .{ .literal = val };
                try parts.append(self.allocator, lit_node);
            }
            node.* = .{ .f_string = .{ .parts = parts.items } };
            return node;
        }
        if (try self.match(.identifier)) {
            node.* = .{ .identifier = .{ .name = self.previous.lexeme } };
            return node;
        }

        // Parentheses: grouped expression or tuple
        if (try self.match(.lparen)) {
            if (try self.match(.rparen)) {
                // Empty tuple ()
                node.* = .{ .tuple_expr = &[_]*Expr{} };
                return node;
            }

            const expr = try self.parseExpr();
            if (try self.match(.comma)) {
                // Tuple (a, ...)
                var items: std.ArrayList(*Expr) = .empty;
                try items.append(self.allocator, expr);
                while (!self.check(.rparen)) {
                    const item = try self.parseExpr();
                    try items.append(self.allocator, item);
                    if (!try self.match(.comma)) break;
                }
                _ = try self.consume(.rparen, "Expected ')' after tuple");
                node.* = .{ .tuple_expr = items.items };
                return node;
            }

            _ = try self.consume(.rparen, "Expected ')' after grouped expression");
            return expr;
        }

        // List literal [a, b, c] or list comprehension [x for x in r]
        if (try self.match(.lbracket)) {
            if (try self.match(.rbracket)) {
                node.* = .{ .list_expr = &[_]*Expr{} };
                return node;
            }

            const first_item = try self.parseExpr();
            if (try self.match(.kw_for)) {
                const target = try self.parseForTarget();
                _ = try self.consume(.kw_in, "Expected 'in' in list comprehension");
                const iter = try self.parseOr();
                var cond: ?*Expr = null;
                if (try self.match(.kw_if)) {
                    cond = try self.parseExpr();
                }
                _ = try self.consume(.rbracket, "Expected ']' after list comprehension");
                node.* = .{
                    .list_comp = .{
                        .elt = first_item,
                        .target = target,
                        .iter = iter,
                        .condition = cond,
                    },
                };
                return node;
            }

            var items: std.ArrayList(*Expr) = .empty;
            try items.append(self.allocator, first_item);
            if (try self.match(.comma)) {
                while (!self.check(.rbracket)) {
                    const item = try self.parseExpr();
                    try items.append(self.allocator, item);
                    if (!try self.match(.comma)) break;
                }
            }
            _ = try self.consume(.rbracket, "Expected ']' after list literal");
            node.* = .{ .list_expr = items.items };
            return node;
        }

        // Dict or Set literal {k: v, ...} or {a, b, ...}
        if (try self.match(.lbrace)) {
            if (try self.match(.rbrace)) {
                // Empty dict {}
                node.* = .{ .dict_expr = .{ .keys = &[_]*Expr{}, .values = &[_]*Expr{} } };
                return node;
            }

            const first_expr = try self.parseExpr();
            if (try self.match(.colon)) {
                // Dict literal
                const first_val = try self.parseExpr();
                var keys: std.ArrayList(*Expr) = .empty;
                var values: std.ArrayList(*Expr) = .empty;
                try keys.append(self.allocator, first_expr);
                try values.append(self.allocator, first_val);

                while (try self.match(.comma)) {
                    if (self.check(.rbrace)) break;
                    const k = try self.parseExpr();
                    _ = try self.consume(.colon, "Expected ':' after dict key");
                    const v = try self.parseExpr();
                    try keys.append(self.allocator, k);
                    try values.append(self.allocator, v);
                }
                _ = try self.consume(.rbrace, "Expected '}' after dict literal");
                node.* = .{ .dict_expr = .{ .keys = keys.items, .values = values.items } };
                return node;
            } else {
                // Set literal
                var items: std.ArrayList(*Expr) = .empty;
                try items.append(self.allocator, first_expr);
                while (try self.match(.comma)) {
                    if (self.check(.rbrace)) break;
                    const item = try self.parseExpr();
                    try items.append(self.allocator, item);
                }
                _ = try self.consume(.rbrace, "Expected '}' after set literal");
                node.* = .{ .set_expr = items.items };
                return node;
            }
        }

        std.debug.print("Unexpected token in primary expression: {s} ('{s}') at {d}:{d}\n", .{
            @tagName(self.current.tag),
            self.current.lexeme,
            self.current.line,
            self.current.column,
        });
        return error.ParseError;
    }
};
