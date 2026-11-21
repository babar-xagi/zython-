const std = @import("std");
const Allocator = std.mem.Allocator;
const token_mod = @import("token.zig");
const Token = token_mod.Token;
const TokenType = token_mod.TokenType;
const keywords = token_mod.keywords;

pub const Lexer = struct {
    source: []const u8,
    allocator: Allocator,
    cursor: usize = 0,
    line: usize = 1,
    column: usize = 1,

    indent_stack: std.ArrayList(usize),
    paren_depth: usize = 0,
    at_line_start: bool = true,
    pending_dedents: usize = 0,
    eof_reached: bool = false,

    pub fn init(allocator: Allocator, source: []const u8) Lexer {
        var stack: std.ArrayList(usize) = .empty;
        stack.append(allocator, 0) catch {};
        return .{
            .source = source,
            .allocator = allocator,
            .indent_stack = stack,
        };
    }

    pub fn deinit(self: *Lexer) void {
        self.indent_stack.deinit(self.allocator);
    }

    fn peek(self: *Lexer) ?u8 {
        if (self.cursor >= self.source.len) return null;
        return self.source[self.cursor];
    }

    fn peekNext(self: *Lexer) ?u8 {
        if (self.cursor + 1 >= self.source.len) return null;
        return self.source[self.cursor + 1];
    }

    fn advance(self: *Lexer) ?u8 {
        if (self.cursor >= self.source.len) return null;
        const c = self.source[self.cursor];
        self.cursor += 1;
        if (c == '\n') {
            self.line += 1;
            self.column = 1;
        } else {
            self.column += 1;
        }
        return c;
    }

    pub fn nextToken(self: *Lexer) !Token {
        if (self.pending_dedents > 0) {
            self.pending_dedents -= 1;
            return Token{
                .tag = .dedent,
                .lexeme = "",
                .line = self.line,
                .column = self.column,
            };
        }

        while (true) {
            // Check for explicit line continuation: \ followed by \n
            if (self.cursor < self.source.len and self.source[self.cursor] == '\\') {
                if (self.cursor + 1 < self.source.len and self.source[self.cursor + 1] == '\n') {
                    _ = self.advance(); // '\'
                    _ = self.advance(); // '\n'
                    continue;
                } else if (self.cursor + 2 < self.source.len and self.source[self.cursor + 1] == '\r' and self.source[self.cursor + 2] == '\n') {
                    _ = self.advance();
                    _ = self.advance();
                    _ = self.advance();
                    continue;
                }
            }

            // Line start / indentation check
            if (self.at_line_start and self.paren_depth == 0) {
                var indent: usize = 0;
                var temp_cursor = self.cursor;

                while (temp_cursor < self.source.len) {
                    const c = self.source[temp_cursor];
                    if (c == ' ') {
                        indent += 1;
                        temp_cursor += 1;
                    } else if (c == '\t') {
                        indent += 4;
                        temp_cursor += 1;
                    } else {
                        break;
                    }
                }

                // Check if line is empty or comment
                if (temp_cursor < self.source.len) {
                    const c = self.source[temp_cursor];
                    if (c == '\r' or c == '\n') {
                        self.cursor = temp_cursor;
                        _ = self.advance();
                        continue;
                    }
                    if (c == '#') {
                        // Skip comment line
                        self.cursor = temp_cursor;
                        while (self.cursor < self.source.len and self.source[self.cursor] != '\n') {
                            _ = self.advance();
                        }
                        if (self.cursor < self.source.len) _ = self.advance();
                        continue;
                    }
                } else {
                    // Reached EOF at line start
                    self.cursor = temp_cursor;
                    break;
                }

                // Consume the indentation
                while (self.cursor < temp_cursor) {
                    _ = self.advance();
                }
                self.at_line_start = false;

                const current_indent = if (self.indent_stack.items.len > 0)
                    self.indent_stack.items[self.indent_stack.items.len - 1]
                else
                    0;

                if (indent > current_indent) {
                    try self.indent_stack.append(self.allocator, indent);
                    return Token{
                        .tag = .indent,
                        .lexeme = "",
                        .line = self.line,
                        .column = self.column,
                    };
                } else if (indent < current_indent) {
                    var pops: usize = 0;
                    while (self.indent_stack.items.len > 1 and
                        self.indent_stack.items[self.indent_stack.items.len - 1] > indent)
                    {
                        _ = self.indent_stack.pop();
                        pops += 1;
                    }
                    if (pops > 0) {
                        self.pending_dedents = pops - 1;
                        return Token{
                            .tag = .dedent,
                            .lexeme = "",
                            .line = self.line,
                            .column = self.column,
                        };
                    }
                }
            }

            // Normal whitespace skip (excluding newline)
            while (self.peek()) |c| {
                if (c == ' ' or c == '\t' or c == '\r') {
                    _ = self.advance();
                } else {
                    break;
                }
            }

            // Comment skip
            if (self.peek()) |c| {
                if (c == '#') {
                    while (self.peek()) |cc| {
                        if (cc == '\n') break;
                        _ = self.advance();
                    }
                    continue;
                }
            }

            // Newline handling
            if (self.peek()) |c| {
                if (c == '\n') {
                    const start_line = self.line;
                    const start_col = self.column;
                    _ = self.advance();
                    if (self.paren_depth == 0) {
                        self.at_line_start = true;
                        return Token{
                            .tag = .newline,
                            .lexeme = "\n",
                            .line = start_line,
                            .column = start_col,
                        };
                    } else {
                        continue;
                    }
                }
            }

            break;
        }

        // Check for EOF
        if (self.cursor >= self.source.len) {
            if (self.indent_stack.items.len > 1) {
                _ = self.indent_stack.pop();
                return Token{
                    .tag = .dedent,
                    .lexeme = "",
                    .line = self.line,
                    .column = self.column,
                };
            }
            return Token{
                .tag = .eof,
                .lexeme = "",
                .line = self.line,
                .column = self.column,
            };
        }

        const start_line = self.line;
        const start_col = self.column;
        const start_pos = self.cursor;
        const c = self.advance().?;

        // Identifiers and strings with prefixes (r, f, b)
        if (std.ascii.isAlphabetic(c) or c == '_') {
            // Check if string prefix e.g. r"...", f"...", b"..."
            if ((c == 'r' or c == 'R' or c == 'f' or c == 'F' or c == 'b' or c == 'B') and
                (self.peek() == '"' or self.peek() == '\''))
            {
                return self.scanString(start_pos, start_line, start_col);
            }

            while (self.peek()) |next_c| {
                if (std.ascii.isAlphanumeric(next_c) or next_c == '_') {
                    _ = self.advance();
                } else {
                    break;
                }
            }
            const lexeme = self.source[start_pos..self.cursor];
            const tag = keywords.get(lexeme) orelse .identifier;
            return Token{
                .tag = tag,
                .lexeme = lexeme,
                .line = start_line,
                .column = start_col,
            };
        }

        // Numbers
        if (std.ascii.isDigit(c)) {
            return self.scanNumber(start_pos, start_line, start_col);
        }

        // String literals
        if (c == '"' or c == '\'') {
            self.cursor = start_pos;
            return self.scanString(start_pos, start_line, start_col);
        }

        // Operators & delimiters
        switch (c) {
            '(' => {
                self.paren_depth += 1;
                return Token{ .tag = .lparen, .lexeme = "(", .line = start_line, .column = start_col };
            },
            ')' => {
                if (self.paren_depth > 0) self.paren_depth -= 1;
                return Token{ .tag = .rparen, .lexeme = ")", .line = start_line, .column = start_col };
            },
            '[' => {
                self.paren_depth += 1;
                return Token{ .tag = .lbracket, .lexeme = "[", .line = start_line, .column = start_col };
            },
            ']' => {
                if (self.paren_depth > 0) self.paren_depth -= 1;
                return Token{ .tag = .rbracket, .lexeme = "]", .line = start_line, .column = start_col };
            },
            '{' => {
                self.paren_depth += 1;
                return Token{ .tag = .lbrace, .lexeme = "{", .line = start_line, .column = start_col };
            },
            '}' => {
                if (self.paren_depth > 0) self.paren_depth -= 1;
                return Token{ .tag = .rbrace, .lexeme = "}", .line = start_line, .column = start_col };
            },
            ':' => return Token{ .tag = .colon, .lexeme = ":", .line = start_line, .column = start_col },
            ',' => return Token{ .tag = .comma, .lexeme = ",", .line = start_line, .column = start_col },
            '.' => {
                if (self.peek()) |p| {
                    if (std.ascii.isDigit(p)) {
                        return self.scanNumber(start_pos, start_line, start_col);
                    }
                }
                return Token{ .tag = .dot, .lexeme = ".", .line = start_line, .column = start_col };
            },
            ';' => return Token{ .tag = .semicolon, .lexeme = ";", .line = start_line, .column = start_col },
            '~' => return Token{ .tag = .tilde, .lexeme = "~", .line = start_line, .column = start_col },
            '+' => {
                if (self.match('=')) return Token{ .tag = .plus_equal, .lexeme = "+=", .line = start_line, .column = start_col };
                return Token{ .tag = .plus, .lexeme = "+", .line = start_line, .column = start_col };
            },
            '-' => {
                if (self.match('=')) return Token{ .tag = .minus_equal, .lexeme = "-=", .line = start_line, .column = start_col };
                if (self.match('>')) return Token{ .tag = .arrow, .lexeme = "->", .line = start_line, .column = start_col };
                return Token{ .tag = .minus, .lexeme = "-", .line = start_line, .column = start_col };
            },
            '*' => {
                if (self.match('*')) {
                    if (self.match('=')) return Token{ .tag = .star_star_equal, .lexeme = "**=", .line = start_line, .column = start_col };
                    return Token{ .tag = .star_star, .lexeme = "**", .line = start_line, .column = start_col };
                }
                if (self.match('=')) return Token{ .tag = .star_equal, .lexeme = "*=", .line = start_line, .column = start_col };
                return Token{ .tag = .star, .lexeme = "*", .line = start_line, .column = start_col };
            },
            '/' => {
                if (self.match('/')) {
                    if (self.match('=')) return Token{ .tag = .slash_slash_equal, .lexeme = "//=", .line = start_line, .column = start_col };
                    return Token{ .tag = .slash_slash, .lexeme = "//", .line = start_line, .column = start_col };
                }
                if (self.match('=')) return Token{ .tag = .slash_equal, .lexeme = "/=", .line = start_line, .column = start_col };
                return Token{ .tag = .slash, .lexeme = "/", .line = start_line, .column = start_col };
            },
            '%' => {
                if (self.match('=')) return Token{ .tag = .percent_equal, .lexeme = "%=", .line = start_line, .column = start_col };
                return Token{ .tag = .percent, .lexeme = "%", .line = start_line, .column = start_col };
            },
            '=' => {
                if (self.match('=')) return Token{ .tag = .equal_equal, .lexeme = "==", .line = start_line, .column = start_col };
                return Token{ .tag = .equal, .lexeme = "=", .line = start_line, .column = start_col };
            },
            '!' => {
                if (self.match('=')) return Token{ .tag = .not_equal, .lexeme = "!=", .line = start_line, .column = start_col };
                return error.UnexpectedCharacter;
            },
            '<' => {
                if (self.match('<')) {
                    if (self.match('=')) return Token{ .tag = .lshift_equal, .lexeme = "<<=", .line = start_line, .column = start_col };
                    return Token{ .tag = .lshift, .lexeme = "<<", .line = start_line, .column = start_col };
                }
                if (self.match('=')) return Token{ .tag = .less_equal, .lexeme = "<=", .line = start_line, .column = start_col };
                return Token{ .tag = .less, .lexeme = "<", .line = start_line, .column = start_col };
            },
            '>' => {
                if (self.match('>')) {
                    if (self.match('=')) return Token{ .tag = .rshift_equal, .lexeme = ">>=", .line = start_line, .column = start_col };
                    return Token{ .tag = .rshift, .lexeme = ">>", .line = start_line, .column = start_col };
                }
                if (self.match('=')) return Token{ .tag = .greater_equal, .lexeme = ">=", .line = start_line, .column = start_col };
                return Token{ .tag = .greater, .lexeme = ">", .line = start_line, .column = start_col };
            },
            '&' => {
                if (self.match('=')) return Token{ .tag = .amp_equal, .lexeme = "&=", .line = start_line, .column = start_col };
                return Token{ .tag = .ampersand, .lexeme = "&", .line = start_line, .column = start_col };
            },
            '|' => {
                if (self.match('=')) return Token{ .tag = .pipe_equal, .lexeme = "|=", .line = start_line, .column = start_col };
                return Token{ .tag = .pipe, .lexeme = "|", .line = start_line, .column = start_col };
            },
            '^' => {
                if (self.match('=')) return Token{ .tag = .caret_equal, .lexeme = "^=", .line = start_line, .column = start_col };
                return Token{ .tag = .caret, .lexeme = "^", .line = start_line, .column = start_col };
            },
            else => return error.UnexpectedCharacter,
        }
    }

    fn match(self: *Lexer, expected: u8) bool {
        if (self.peek()) |c| {
            if (c == expected) {
                _ = self.advance();
                return true;
            }
        }
        return false;
    }

    fn scanNumber(self: *Lexer, start_pos: usize, start_line: usize, start_col: usize) !Token {
        var is_float = false;

        // Check for 0x, 0b, 0o
        if (self.source[start_pos] == '0' and self.cursor < self.source.len) {
            const base_prefix = self.source[self.cursor];
            if (base_prefix == 'x' or base_prefix == 'X') {
                _ = self.advance();
                while (self.peek()) |c| {
                    if (std.ascii.isHex(c) or c == '_') {
                        _ = self.advance();
                    } else break;
                }
                return Token{
                    .tag = .int_lit,
                    .lexeme = self.source[start_pos..self.cursor],
                    .line = start_line,
                    .column = start_col,
                };
            } else if (base_prefix == 'b' or base_prefix == 'B') {
                _ = self.advance();
                while (self.peek()) |c| {
                    if (c == '0' or c == '1' or c == '_') {
                        _ = self.advance();
                    } else break;
                }
                return Token{
                    .tag = .int_lit,
                    .lexeme = self.source[start_pos..self.cursor],
                    .line = start_line,
                    .column = start_col,
                };
            } else if (base_prefix == 'o' or base_prefix == 'O') {
                _ = self.advance();
                while (self.peek()) |c| {
                    if ((c >= '0' and c <= '7') or c == '_') {
                        _ = self.advance();
                    } else break;
                }
                return Token{
                    .tag = .int_lit,
                    .lexeme = self.source[start_pos..self.cursor],
                    .line = start_line,
                    .column = start_col,
                };
            }
        }

        while (self.peek()) |c| {
            if (std.ascii.isDigit(c) or c == '_') {
                _ = self.advance();
            } else if (c == '.') {
                if (self.peekNext()) |next| {
                    if (std.ascii.isDigit(next)) {
                        is_float = true;
                        _ = self.advance();
                        while (self.peek()) |dc| {
                            if (std.ascii.isDigit(dc) or dc == '_') {
                                _ = self.advance();
                            } else break;
                        }
                    } else break;
                } else break;
            } else if (c == 'e' or c == 'E') {
                is_float = true;
                _ = self.advance();
                if (self.peek()) |sign| {
                    if (sign == '+' or sign == '-') _ = self.advance();
                }
                while (self.peek()) |dc| {
                    if (std.ascii.isDigit(dc) or dc == '_') {
                        _ = self.advance();
                    } else break;
                }
            } else break;
        }

        return Token{
            .tag = if (is_float) .float_lit else .int_lit,
            .lexeme = self.source[start_pos..self.cursor],
            .line = start_line,
            .column = start_col,
        };
    }

    fn scanString(self: *Lexer, start_pos: usize, start_line: usize, start_col: usize) !Token {
        var is_fstring = false;
        // Skip prefix (e.g. r, f, b)
        var p = start_pos;
        while (p < self.cursor and (self.source[p] != '"' and self.source[p] != '\'')) {
            if (self.source[p] == 'f' or self.source[p] == 'F') is_fstring = true;
            p += 1;
        }
        if (p >= self.cursor) {
            _ = self.advance();
        }

        const quote = self.source[self.cursor - 1];
        var is_triple = false;

        // Check if triple quote
        if (self.peek() == quote and self.peekNext() == quote) {
            is_triple = true;
            _ = self.advance();
            _ = self.advance();
        }

        var escaped = false;
        var unescaped_buf: std.ArrayList(u8) = .empty;

        while (self.peek()) |c| {
            if (escaped) {
                switch (c) {
                    'n' => try unescaped_buf.append(self.allocator, '\n'),
                    't' => try unescaped_buf.append(self.allocator, '\t'),
                    'r' => try unescaped_buf.append(self.allocator, '\r'),
                    '\\' => try unescaped_buf.append(self.allocator, '\\'),
                    '\'' => try unescaped_buf.append(self.allocator, '\''),
                    '"' => try unescaped_buf.append(self.allocator, '"'),
                    else => {
                        try unescaped_buf.append(self.allocator, '\\');
                        try unescaped_buf.append(self.allocator, c);
                    },
                }
                escaped = false;
                _ = self.advance();
                continue;
            }

            if (c == '\\') {
                escaped = true;
                _ = self.advance();
                continue;
            }

            if (is_triple) {
                if (c == quote and self.peekNext() == quote) {
                    if (self.cursor + 2 < self.source.len and self.source[self.cursor + 2] == quote) {
                        _ = self.advance();
                        _ = self.advance();
                        _ = self.advance();
                        break;
                    }
                }
            } else {
                if (c == quote) {
                    _ = self.advance();
                    break;
                }
                if (c == '\n') return error.UnterminatedString;
            }

            try unescaped_buf.append(self.allocator, c);
            _ = self.advance();
        }

        return Token{
            .tag = if (is_fstring) .fstring_lit else .string_lit,
            .lexeme = unescaped_buf.items,
            .line = start_line,
            .column = start_col,
        };
    }
};
