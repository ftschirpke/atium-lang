const std = @import("std");

const collections = @import("collections.zig");
const errmsg = @import("error_messages.zig");
const lex = @import("lex.zig");

const SourceFile = @import("sources.zig").SourceFile;

const AstItemList = collections.TaggedUnionList(AstItem);
const AstItemIndex = u128;

const AstItem = union(enum) {
    boolean_literal: bool,
    integer_literal: u64,
    string_literal: []const u8,
    binary_expression: struct {
        left_expr: AstItemIndex,
        right_expr: AstItemIndex,
        operator: enum {
            EQUAL,
            NOT_EQUAL,
            GREATER,
            LESS,
            GREATER_EQUAL,
            LESS_EQUAL,
            ADD,
            SUBTRACT,
            MULTIPLY,
            DIVIDE,
            BIT_AND,
            BIT_OR,
            BIT_XOR,
            BITSHIFT_LEFT,
            BITSHIFT_RIGHT,
            AND,
            OR,
        },
    },
    unary_expression: struct {
        inner_expr: AstItemIndex,
        operator: enum {
            NOT,
            MINUS,
            BIT_INVERSE,
        },
    },
    array_access: struct {
        outer_expr: AstItemIndex,
        bracket_expr: AstItemIndex,
    },
};

const AstItemSource = struct {
    file: *const SourceFile,
    line: u32,
    col: u32,
    highlight_len: u32,

    const Self = @This();

    pub fn from_token(token: lex.Token) Self {
        return Self{
            .file = token.source.file,
            .line = token.source.line,
            .col = token.source.col,
            .highlight_len = token.len(),
        };
    }
};

const Ast = struct {
    item_list: AstItemList,
    sources: std.ArrayList(AstItemSource),
    top_level: std.ArrayList(Index),

    const Self = @This();
    const Index = struct {
        source_index: usize,
        item_index: AstItemList.Index,
    };

    pub fn init(allocator: std.mem.Allocator) Self {
        const item_list = AstItemList.init(allocator);
        const sources = std.ArrayList(AstItemSource).init(allocator);
        const top_level = std.ArrayList(Index).init(allocator);
        return Self{
            .item_list = item_list,
            .sources = sources,
            .top_level = top_level,
        };
    }

    pub fn deinit(self: Self) void {
        self.item_list.deinit();
        self.sources.deinit();
        self.top_level.deinit();
    }

    pub fn append(self: *Self, item: AstItem, source: AstItemSource) !Index {
        const source_index = self.sources.items.len;
        try self.sources.append(source);
        const item_index = self.item_list.append(item) catch |err| {
            _ = self.sources.pop();
            return err;
        };
        return Index{
            .source_index = source_index,
            .item_index = item_index,
        };
    }
};

pub const Parser = struct {
    ast: Ast,
    lexer: *lex.Lexer,
    next_token: ?lex.Token,

    const Self = @This();
    const Error = error{ InvalidToken, MissingToken };

    pub fn init(allocator: std.mem.Allocator, lexer: *lex.Lexer) Self {
        comptime std.debug.assert(AstItemIndex == AstItemList.Index);
        const ast = Ast.init(allocator);
        return Self{
            .ast = ast,
            .lexer = lexer,
            .next_token = null,
        };
    }

    pub fn deinit(self: Self) void {
        self.ast.deinit();
    }

    fn consume_token(self: *Self) !lex.Token {
        const rv = self.next_token orelse return Error.MissingToken;
        self.next_token = self.lexer.next_token() catch null;
        return rv;
    }

    fn has_next(self: *Self) bool {
        return self.next_token != null;
    }

    fn check_next(self: *Self, expected: lex.TokenKind) bool {
        return self.has_next() and self.next_token.?.kind == expected;
    }

    fn parse_expression(self: *Self) !Ast.Index {
        return self.parse_or_expression();
    }

    fn parse_or_expression(self: *Self) !Ast.Index {
        const left_expr = try self.parse_and_expression();
        if (!self.check_next(lex.TokenKind.OR)) {
            return left_expr;
        }
        const or_token = try self.consume_token();
        const right_expr = try self.parse_and_expression();
        const expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = .OR,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(or_token));
    }

    fn parse_and_expression(self: *Self) !Ast.Index {
        const left_expr = try self.parse_not_expression();
        if (!self.check_next(lex.TokenKind.AND)) {
            return left_expr;
        }
        const and_token = try self.consume_token();
        const right_expr = try self.parse_not_expression();
        const expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = .AND,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(and_token));
    }

    fn parse_not_expression(self: *Self) !Ast.Index {
        if (!self.check_next(lex.TokenKind.EXCLAMATION)) {
            return self.parse_compare_expression();
        }
        const inner_expr = try self.parse_compare_expression();
        const not_token = try self.consume_token();
        const expr = AstItem{
            .unary_expression = .{
                .inner_expr = inner_expr,
                .operator = .NOT,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(not_token));
    }

    fn parse_compare_expression(self: *Self) !Ast.Index {
        const left_expr = try self.parse_bitwise_or_expression();
        if (!self.has_next()) {
            return left_expr;
        }
        const operator = op: switch (self.next_token.?.kind) {
            lex.TokenKind.EQUAL => break :op .EQUAL,
            lex.TokenKind.NOT_EQUAL => break :op .NOT_EQUAL,
            lex.TokenKind.GREATER => break :op .GREATER,
            lex.TokenKind.LESS => break :op .LESS,
            lex.TokenKind.GREATER_EQUAL => break :op .GREATER_EQUAL,
            lex.TokenKind.LESS_EQUAL => break :op .LESS_EQUAL,
            else => return left_expr,
        };
        const compare_token = try self.consume_token();
        const right_expr = try self.parse_bitwise_or_expression();
        const expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = operator,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(compare_token));
    }

    fn parse_bitwise_or_expression(self: *Self) !Ast.Index {
        const left_expr = try self.parse_bitwise_xor_expression();
        if (!self.check_next(lex.TokenKind.PIPE)) {
            return left_expr;
        }
        const pipe_token = try self.consume_token();
        const right_expr = try self.parse_bitwise_xor_expression();
        const expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = .BIT_OR,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(pipe_token));
    }

    fn parse_bitwise_xor_expression(self: *Self) !Ast.Index {
        const left_expr = try self.parse_bitwise_and_expression();
        if (!self.check_next(lex.TokenKind.CARET)) {
            return left_expr;
        }
        const caret_token = try self.consume_token();
        const right_expr = try self.parse_bitwise_and_expression();
        const expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = .BIT_XOR,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(caret_token));
    }

    fn parse_bitwise_and_expression(self: *Self) !Ast.Index {
        const left_expr = try self.parse_bitshift_expression();
        if (!self.check_next(lex.TokenKind.AMPERSAND)) {
            return left_expr;
        }
        const ampersand_token = try self.consume_token();
        const right_expr = try self.parse_bitshift_expression();
        const expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = .BIT_AND,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(ampersand_token));
    }

    fn parse_bitshift_expression(self: *Self) !Ast.Index {
        const left_expr = try self.parse_addition_expression();
        if (!self.has_next()) {
            return left_expr;
        }
        const operator = op: switch (self.next_token.?.kind) {
            lex.TokenKind.DOUBLE_GREATER => break :op .BITSHIFT_RIGHT,
            lex.TokenKind.DOUBLE_LESS => break :op .BITSHIFT_LEFT,
            else => return left_expr,
        };
        const bitshift_token = try self.consume_token();
        const right_expr = try self.parse_addition_expression();
        const expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = operator,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(bitshift_token));
    }

    fn parse_addition_expression(self: *Self) !Ast.Index {
        const left_expr = try self.parse_compare_expression();
        if (!self.has_next()) {
            return left_expr;
        }
        const operator = op: switch (self.next_token.?.kind) {
            lex.TokenKind.PLUS => break :op .ADD,
            lex.TokenKind.MINUS => break :op .SUBTRACT,
            else => return left_expr,
        };
        const op_token = try self.consume_token();
        const right_expr = try self.parse_compare_expression();
        const expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = operator,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(op_token));
    }

    fn parse_multiply_expression(self: *Self) !Ast.Index {
        const left_expr = try self.parse_addition_expression();
        if (!self.has_next()) {
            return left_expr;
        }
        const operator = op: switch (self.next_token.?.kind) {
            lex.TokenKind.ASTERISK => break :op .MULTIPLY,
            lex.TokenKind.SLASH => break :op .DIVIDE,
            else => return left_expr,
        };
        const op_token = try self.consume_token();
        const right_expr = try self.parse_addition_expression();
        const expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = operator,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(op_token));
    }

    fn parse_arithmetic_unary_expression(self: *Self) !Ast.Index {
        const inner_expr = try self.parse_compare_expression();
        if (!self.has_next()) {
            return inner_expr;
        }
        const operator = op: switch (self.next_token.?.kind) {
            lex.TokenKind.TILDE => break :op .BIT_NOT,
            lex.TokenKind.MINUS => break :op .MINUS,
            else => return inner_expr,
        };
        const op_token = try self.consume_token();
        const expr = AstItem{
            .unary_expression = .{
                .inner_expr = inner_expr,
                .operator = operator,
            },
        };
        return self.ast.append(expr, AstItemSource.from_token(op_token));
    }

    fn parse_access_expression(self: *Self) !Ast.Index {
        const outer_expr = try self.parse_prioritized_expression();
        if (!self.has_next()) {
            return outer_expr;
        }
        const token = self.next_token.?;
        switch (token.kind) {
            lex.TokenKind.LBRACKET => {
                _ = try self.consume_token();
                const bracket_expr = try self.parse_expression();
                if (self.check_next(lex.TokenKind.RBRACKET)) {
                    _ = try self.consume_token();
                    const expr = AstItem{
                        .array_access = .{
                            .outer_expr = outer_expr,
                            .bracket_expr = bracket_expr,
                        },
                    };
                    return self.ast.append(expr, AstItemSource.from_token(token)); // TODO: improve source
                } else if (self.next_token == null) {
                    print_token_error(
                        .Error,
                        &token,
                        "Found opening bracket without closing bracket.",
                        .{},
                        "Ensure your brackets are properly closed.",
                        .{},
                    );
                } else {
                    print_token_error(
                        .Info,
                        &token,
                        "Opening bracket",
                        .{},
                        null,
                        .{},
                    );
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected closing bracket but instead found:",
                        .{},
                        "Ensure your brackets are properly closed.",
                        .{},
                    );
                }
                return Error.InvalidToken;
            },
            lex.TokenKind.LPAREN => {
                _ = try self.consume_token();
                // TODO: parse function arguments
                if (self.check_next(lex.TokenKind.RPAREN)) {
                    // TODO: create function call AST item
                } else if (self.next_token == null) {
                    print_token_error(
                        .Error,
                        &token,
                        "Found opening parenthesis without closing parenthesis.",
                        .{},
                        "Ensure your opening parenthesis is properly closed.",
                        .{},
                    );
                } else {
                    print_token_error(
                        .Info,
                        &token,
                        "Opening parenthesis",
                        .{},
                        null,
                        .{},
                    );
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected closing partenthesis but instead found:",
                        .{},
                        "Ensure your opening parenthesis is properly closed.",
                        .{},
                    );
                }
                return Error.InvalidToken;
            },
            lex.TokenKind.DOT => {
                var accessed_expression = outer_expr;
                var access_token = undefined;
                while (self.check_next(lex.TokenKind.DOT)) {
                    access_token = try self.consume_token();
                    if (self.check_next(lex.TokenKind.IDENTIFIER)) {
                        // TODO: this is not quite right, we actually need to allow self.arr[..] and self.f().abc ...
                    } else if (self.next_token == null) {
                        print_token_error(
                            .Error,
                            &access_token,
                            "Found start of field access without field or function name.",
                            .{},
                            null,
                            .{},
                        );
                    } else {
                        print_token_error(
                            .Error,
                            &self.next_token.?,
                            "Expected field access but instead found:",
                            .{},
                            null,
                            .{},
                        );
                    }
                }
            },
        }
    }

    fn parse_prioritized_expression(self: *Self) !Ast.Index {
        std.debug.assert(self.has_next());

        var expr: AstItem = undefined;
        var source: AstItemSource = undefined;

        const token = self.next_token.?;
        switch (token.kind) {
            lex.TokenKind.TRUE => {
                expr = AstItem{ .boolean_literal = true };
                source = AstItemSource.from_token(try self.consume_token());
            },
            lex.TokenKind.FALSE => {
                expr = AstItem{ .boolean_literal = false };
                source = AstItemSource.from_token(try self.consume_token());
            },
            lex.TokenKind.NUMBER => {
                const i: u64 = std.fmt.parseInt(u8, token.str.?, 10) catch |err| {
                    switch (err) {
                        std.fmt.ParseIntError.Overflow => {
                            print_token_error(
                                .Error,
                                &token,
                                "Integer literal does not fit into 64 bits",
                                .{},
                                null,
                                .{},
                            );
                            return Error.InvalidToken;
                        },
                        std.fmt.ParseIntError.InvalidCharacter => unreachable,
                    }
                };
                expr = AstItem{ .integer_literal = i };
                source = AstItemSource.from_token(try self.consume_token());
            },
            lex.TokenKind.STRING_LITERAL => {
                expr = AstItem{ .string_literal = token.str.? };
                source = AstItemSource.from_token(try self.consume_token());
            },
            lex.TokenKind.IDENTIFIER => {
                // TODO: implement identifier
            },
            lex.TokenKind.LPAREN => {
                _ = try self.consume_token();
                const inner = try self.parse_expression();
                if (self.check_next(lex.TokenKind.RPAREN)) {
                    _ = try self.consume_token();
                    return inner;
                } else if (self.next_token == null) {
                    print_token_error(
                        .Error,
                        &token,
                        "Found opening parenthesis without closing parenthesis.",
                        .{},
                        "Ensure your opening parenthesis is properly closed.",
                        .{},
                    );
                } else {
                    print_token_error(
                        .Info,
                        &token,
                        "Opening parenthesis",
                        .{},
                        null,
                        .{},
                    );
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected closing partenthesis but instead found:",
                        .{},
                        "Ensure your opening parenthesis is properly closed.",
                        .{},
                    );
                }
                return Error.InvalidToken;
            },
            else => {
                print_token_error(
                    .Error,
                    &token,
                    "Expected expression; found unexpected token",
                    .{},
                    null,
                    .{},
                );
                return Error.InvalidToken;
            },
        }

        return self.ast.append(expr, source);
    }

    pub fn parse(self: *Self) !void {
        self.next_token = try self.lexer.next_token();

        while (self.has_next()) {
            // HACK: only to test current implementation
            const index = try self.parse_expression();
            try self.ast.top_level.append(index);
        }
    }
};

pub fn print_token_error(
    error_level: errmsg.ErrorLevel,
    token: *const lex.Token,
    comptime err_fmt: []const u8,
    err_args: anytype,
    comptime hint_fmt: ?[]const u8,
    hint_args: anytype,
) void {
    const token_len = token.len();
    errmsg.print_error(
        error_level,
        token.source.file,
        token.source.line,
        token.source.col,
        token_len,
        err_fmt,
        err_args,
        hint_fmt,
        hint_args,
    );
}
