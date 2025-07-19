const std = @import("std");

const lex = @import("lex.zig");
const collections = @import("collections.zig");

const AstItem = union(enum) {
    boolean_literal: bool,
    integer_literal: u64,
    string_literal: []const u8,
};

const List = collections.TaggedUnionList(AstItem);

pub const Parser = struct {
    list: List,
    top_level: std.ArrayList(List.Index),
    lexer: *lex.Lexer,
    next_token: ?lex.Token,

    const Self = @This();
    const Error = error{InvalidToken};

    pub fn init(allocator: std.mem.Allocator, lexer: *lex.Lexer) Self {
        const top_level = std.ArrayList(List.Index).init(allocator);
        const list = List.init(allocator);
        return Self{
            .top_level = top_level,
            .list = list,
            .lexer = lexer,
            .next_token = null,
        };
    }

    pub fn deinit(self: Self) void {
        self.list.deinit();
        self.top_level.deinit();
    }

    fn grab_next_token(self: *Self) void {
        self.next_token = self.lexer.next_token() catch return;
    }

    fn has_next(self: *Self) bool {
        return self.next_token != null;
    }

    fn check_next(self: *Self, expected: lex.TokenKind) bool {
        return self.has_next() and self.next_token.?.kind == expected;
    }

    pub fn print_token_error(
        self: *Self,
        token: *const lex.Token,
        comptime err_fmt: []const u8,
        err_args: anytype,
        comptime hint_fmt: ?[]const u8,
        hint_args: anytype,
    ) void {
        const token_len = len: switch (token.kind) {
            lex.TokenKind.INVALID => {
                std.debug.assert(false);
                return;
            },
            lex.TokenKind.DOT,
            lex.TokenKind.COMMA,
            lex.TokenKind.COLON,
            lex.TokenKind.SEMICOLON,
            lex.TokenKind.PLUS,
            lex.TokenKind.MINUS,
            lex.TokenKind.ASTERISK,
            lex.TokenKind.LPAREN,
            lex.TokenKind.RPAREN,
            lex.TokenKind.LBRACE,
            lex.TokenKind.RBRACE,
            lex.TokenKind.LBRACKET,
            lex.TokenKind.RBRACKET,
            lex.TokenKind.EXCLAMATION,
            lex.TokenKind.QUESTION,
            lex.TokenKind.ASSIGN,
            lex.TokenKind.GREATER,
            lex.TokenKind.LESS,
            lex.TokenKind.SLASH,
            => {
                break :len 1;
            },
            lex.TokenKind.IF,
            lex.TokenKind.IN,
            lex.TokenKind.OR,
            lex.TokenKind.ARROW,
            lex.TokenKind.DOUBLE_PLUS,
            lex.TokenKind.DOUBLE_DOT,
            lex.TokenKind.DOUBLE_ASTERISK,
            lex.TokenKind.EQUAL,
            lex.TokenKind.NOT_EQUAL,
            lex.TokenKind.GREATER_EQUAL,
            lex.TokenKind.FN,
            lex.TokenKind.LESS_EQUAL,
            => {
                break :len 2;
            },
            lex.TokenKind.OWN,
            lex.TokenKind.FOR,
            lex.TokenKind.AND,
            lex.TokenKind.LET,
            lex.TokenKind.MUT,
            => {
                break :len 3;
            },
            lex.TokenKind.TRUE,
            lex.TokenKind.ENUM,
            lex.TokenKind.ELSE,
            => {
                break :len 4;
            },
            lex.TokenKind.WHILE,
            lex.TokenKind.FALSE,
            lex.TokenKind.UNION,
            lex.TokenKind.TRAIT,
            lex.TokenKind.BREAK,
            => {
                break :len 5;
            },
            lex.TokenKind.STRUCT,
            lex.TokenKind.RETURN,
            => {
                break :len 6;
            },
            lex.TokenKind.CONTINUE,
            => {
                break :len 8;
            },
            lex.TokenKind.NUMBER,
            lex.TokenKind.IDENTIFIER,
            lex.TokenKind.STRING_LITERAL,
            => {
                break :len token.str.?.len;
            },
        };
        self.lexer.print_error(&token.source, token_len, err_fmt, err_args, hint_fmt, hint_args);
    }

    fn parse_expression(self: *Self) !List.Index {
        std.debug.assert(self.has_next());

        var expr: AstItem = undefined;

        const token = self.next_token.?;
        switch (token.kind) {
            lex.TokenKind.TRUE => {
                expr = AstItem{ .boolean_literal = true };
                self.grab_next_token();
            },
            lex.TokenKind.FALSE => {
                expr = AstItem{ .boolean_literal = false };
                self.grab_next_token();
            },
            lex.TokenKind.NUMBER => {
                const i: u64 = std.fmt.parseInt(u8, token.str.?, 10) catch |err| {
                    switch (err) {
                        std.fmt.ParseIntError.Overflow => {
                            self.print_token_error(
                                &token,
                                "Integer {s} does not fit into 64 bits",
                                .{token.str.?},
                                null,
                                .{},
                            );
                            return Error.InvalidToken;
                        },
                        std.fmt.ParseIntError.InvalidCharacter => unreachable,
                    }
                };
                expr = AstItem{ .integer_literal = i };
                self.grab_next_token();
            },
            lex.TokenKind.STRING_LITERAL => {
                expr = AstItem{ .string_literal = token.str.? };
                self.grab_next_token();
            },
            lex.TokenKind.LPAREN => {
                self.grab_next_token();
                const inner = try self.parse_expression();
                if (self.check_next(lex.TokenKind.RPAREN)) {
                    std.debug.print("found matching paren", .{});
                    self.grab_next_token();
                    return inner;
                } else if (self.next_token == null) {
                    std.debug.print("no matching paren", .{});
                    self.print_token_error(
                        &token,
                        "Found opening parenthesis without closing parenthesis.",
                        .{},
                        "Ensure there is a closing parenthesis for each opening parenthesis.",
                        .{},
                    );
                } else {
                    std.debug.print("invalid matching paren", .{});
                    self.print_token_error(
                        &token,
                        "Expected closing parenthesis for opening parenthesis.",
                        .{},
                        null,
                        .{},
                    );
                    self.print_token_error(
                        &self.next_token.?,
                        "Instead found:",
                        .{},
                        "Ensure your opening parenthesis is properly closed.",
                        .{},
                    );
                }
                return Error.InvalidToken;
            },
            else => {
                self.print_token_error(
                    &token,
                    "Expected expression; found unexpected token",
                    .{},
                    null,
                    .{},
                );
                return Error.InvalidToken;
            },
        }

        return self.list.append(expr);
    }

    pub fn parse(self: *Self) !void {
        self.grab_next_token();

        while (self.has_next()) {
            // HACK: only to test current implementation
            const index = try self.parse_expression();
            try self.top_level.append(index);
        }
    }
};
