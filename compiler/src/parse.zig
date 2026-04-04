// SPDX-License-Identifier: MIT
const std = @import("std");

const collections = @import("collections.zig");
const errmsg = @import("error_messages.zig");
const lex = @import("lex.zig");
const id = @import("id.zig");

const SourceFile = @import("world.zig").SourceFile;

const AstItemList = collections.TaggedUnionList(AstItem);

const AstIndex = struct {
    source_index: usize,
    item_index: id.IdType,
};

const LabeledExpr = struct {
    label: []const u8,
    type_expr: AstIndex,
};

const AstItem = union(enum) {
    boolean_literal: bool,
    integer_literal: u64,
    string_literal: []const u8,
    identifier: []const u8,
    binary_expression: struct {
        left_expr: AstIndex,
        right_expr: AstIndex,
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
            BITSHIFT_LEFT,
            BITSHIFT_RIGHT,
            BIT_AND,
            BIT_OR,
            BIT_XOR,
            ARRAY_ADD,
            ARRAY_MULTIPLY,
            AND,
            OR,
            RANGE,
        },
    },
    unary_expression: struct {
        inner_expr: AstIndex,
        operator: enum {
            NOT,
            MINUS,
            BIT_INVERSE,
        },
    },
    array_access: struct {
        outer_expr: AstIndex,
        bracket_expr: AstIndex,
    },
    function_call: struct {
        function_expr: AstIndex,
        args_expr: std.ArrayList(Ast.Index),
    },
    primitive_access: struct {
        outer_expr: AstIndex,
        access_type: enum {
            DEREFERENCE,
            ADDRESS,
            UNWRAP_CHECKED,
            UNWRAP_UNCHECKED,
        },
    },
    field_access: struct {
        outer_expr: AstIndex,
        field_name: AstIndex,
    },
    basic_type: enum {
        Bool,
        I8,
        I16,
        I32,
        I64,
        I128,
        ISIZE,
        U8,
        U16,
        U32,
        U64,
        U128,
        USIZE,
        SELF,
    },
    function_type: struct {
        input_type_expr: AstIndex,
        output_type_expr: AstIndex,
    },
    struct_type: struct {
        members: std.ArrayList(LabeledExpr),
    },
    variant_type: struct {
        members: std.ArrayList(LabeledExpr),
    },
    interface: struct {
        members: std.ArrayList(LabeledExpr),
    },
    func_def: struct {
        arguments: std.ArrayList(LabeledExpr),
        return_type_expr: AstIndex,
        body: AstIndex,
    },
    type_func_def: struct {
        type_name: AstIndex,
        name: AstIndex,
        func_def: AstIndex,
    },
    var_def: struct {
        mut: bool,
        name: AstIndex,
        type_expr: ?AstIndex,
        value: AstIndex,
    },
    assign: struct {
        left_expr: AstIndex,
        right_expr: AstIndex,
        operation: enum {
            NONE,
            ADD,
            SUBTRACT,
            MULTIPLY,
            DIVIDE,
            BITSHIFT_LEFT,
            BITSHIFT_RIGHT,
            BIT_AND,
            BIT_OR,
            BIT_XOR,
            ARRAY_ADD,
            ARRAY_MULTIPLY,
            AND,
            OR,
        },
    },
    block: struct {
        stmts: std.ArrayList(Ast.Index),
    },
    if_statement: struct {
        condition: AstIndex,
        then_body: AstIndex,
        else_body: ?AstIndex,
    },
    for_statement: struct {
        loop_var: []const u8,
        iter_expr: AstIndex,
        body: AstIndex,
    },
    while_statement: struct {
        condition: AstIndex,
        body: AstIndex,
    },
    return_statement: struct {
        value: ?AstIndex,
    },
    loop_control: enum {
        BREAK,
        CONTINUE,
    },
};

const AstItemSource = struct {
    file: *SourceFile,
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
    allocator: std.mem.Allocator,
    item_list: AstItemList,
    sources: std.ArrayList(AstItemSource),
    top_level: std.ArrayList(Index),

    const Self = @This();
    const Index = AstIndex;

    pub fn init(allocator: std.mem.Allocator) !Self {
        const item_list = try AstItemList.init(allocator);
        const sources = try std.ArrayList(AstItemSource).initCapacity(allocator, 10);
        const top_level = try std.ArrayList(Index).initCapacity(allocator, 40);
        return Self{
            .allocator = allocator,
            .item_list = item_list,
            .sources = sources,
            .top_level = top_level,
        };
    }

    pub fn deinit(self: *Self) void {
        self.item_list.deinit();
        self.sources.deinit(self.allocator);
        self.top_level.deinit(self.allocator);
    }

    pub fn append(self: *Self, item: AstItem, source: AstItemSource) !Index {
        const source_index = self.sources.items.len;
        try self.sources.append(self.allocator, source);
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
    allocator: std.mem.Allocator,

    const Self = @This();
    const Error = error{ InvalidToken, MissingToken, OutOfMemory, OutOfIndexSpace };

    pub fn init(allocator: std.mem.Allocator, lexer: *lex.Lexer) !Self {
        const ast = try Ast.init(allocator);
        return Self{
            .ast = ast,
            .lexer = lexer,
            .next_token = null,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Self) void {
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

    fn parse_statement(self: *Self) Error!Ast.Index {
        if (!self.has_next()) {
            return Error.MissingToken;
        }
        switch (self.next_token.?.kind) {
            lex.TokenKind.IDENTIFIER => return self.parse_assign_statement(),
            lex.TokenKind.LET => return self.parse_let_statement(),
            lex.TokenKind.IF => return self.parse_if_statement(),
            lex.TokenKind.FOR => return self.parse_for_statement(),
            lex.TokenKind.WHILE => return self.parse_while_statement(),
            lex.TokenKind.RETURN => return self.parse_return_statement(),
            lex.TokenKind.BREAK, lex.TokenKind.CONTINUE => return self.parse_loop_control_statement(),
            else => return Error.InvalidToken,
        }
    }

    fn parse_assign_statement(self: *Self) Error!Ast.Index {
        var expr = AstItem{
            .assign = .{
                .left_expr = undefined,
                .right_expr = undefined,
                .operation = .NONE,
            },
        };
        expr.assign.left_expr = try self.parse_expression();
        if (!self.has_next()) {
            return Error.MissingToken;
        }
        var source_token: lex.Token = undefined;
        const assign_token = try self.consume_token();
        switch (assign_token.kind) {
            lex.TokenKind.ASSIGN => {
                expr.assign.operation = .NONE;
                source_token = assign_token;
            },
            lex.TokenKind.PLUS => expr.assign.operation = .ADD,
            lex.TokenKind.MINUS => expr.assign.operation = .SUBTRACT,
            lex.TokenKind.ASTERISK => expr.assign.operation = .MULTIPLY,
            lex.TokenKind.SLASH => expr.assign.operation = .DIVIDE,
            lex.TokenKind.DOUBLE_LESS => expr.assign.operation = .BITSHIFT_LEFT,
            lex.TokenKind.DOUBLE_GREATER => expr.assign.operation = .BITSHIFT_RIGHT,
            lex.TokenKind.AMPERSAND => expr.assign.operation = .BIT_AND,
            lex.TokenKind.PIPE => expr.assign.operation = .BIT_OR,
            lex.TokenKind.CARET => expr.assign.operation = .BIT_XOR,
            lex.TokenKind.DOUBLE_PLUS => expr.assign.operation = .ARRAY_ADD,
            lex.TokenKind.DOUBLE_ASTERISK => expr.assign.operation = .ARRAY_MULTIPLY,
            lex.TokenKind.AND => expr.assign.operation = .AND,
            lex.TokenKind.OR => expr.assign.operation = .OR,
            else => {
                print_token_error(
                    .Error,
                    &assign_token,
                    "Expected assign statement but found unexpected token {}.",
                    .{assign_token.kind},
                    "",
                    .{},
                );
                return Error.InvalidToken;
            },
        }
        if (expr.assign.operation != .NONE) {
            const equal_token = try self.consume_token();
            std.debug.assert(equal_token.kind == lex.TokenKind.ASSIGN);
            source_token = equal_token;
        }
        expr.assign.right_expr = try self.parse_expression();
        if (!self.check_next(lex.TokenKind.SEMICOLON)) {
            print_token_error(
                .Error,
                &self.next_token.?,
                "Expected ';' after assignment.",
                .{},
                null,
                .{},
            );
            return Error.InvalidToken;
        }
        _ = try self.consume_token();
        return self.ast.append(expr, AstItemSource.from_token(source_token));
    }

    fn parse_let_statement(self: *Self) Error!Ast.Index {
        var expr = AstItem{
            .var_def = .{
                .mut = false,
                .name = undefined,
                .type_expr = null,
                .value = undefined,
            },
        };
        const let_token = try self.consume_token();

        if (!self.has_next()) {
            return Error.MissingToken;
        }
        if (self.check_next(lex.TokenKind.MUT)) {
            expr.var_def.mut = true;
            _ = try self.consume_token();
        }

        expr.var_def.name = try self.parse_nonoperator_expression();
        const name = self.ast.item_list.get(expr.var_def.name.item_index);
        if (expr.var_def.mut) {
            switch (name) {
                .identifier => {},
                else => {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Found non-identifier token after begin of mutable let statement.",
                        .{},
                        "Only variables can be defined as mutable.",
                        .{},
                    );
                    return Error.InvalidToken;
                },
            }
        }

        if (!self.has_next()) {
            return Error.MissingToken;
        }
        if (self.next_token.?.kind == lex.TokenKind.COLON) {
            _ = try self.consume_token();
            expr.var_def.type_expr = try self.parse_expression();
        }

        if (!self.has_next()) {
            return Error.MissingToken;
        }
        if (self.next_token.?.kind != lex.TokenKind.ASSIGN) {
            print_token_error(
                .Error,
                &self.next_token.?,
                "Found non-equal token after begin of let statement.",
                .{},
                "Ensure your let statement has an equal sign.",
                .{},
            );
            return Error.InvalidToken;
        }
        _ = try self.consume_token();

        expr.var_def.value = try self.parse_expression();

        if (!self.check_next(lex.TokenKind.SEMICOLON)) {
            print_token_error(
                .Error,
                &self.next_token.?,
                "Expected ';' after let statement.",
                .{},
                null,
                .{},
            );
            return Error.InvalidToken;
        }
        _ = try self.consume_token();

        return self.ast.append(expr, AstItemSource.from_token(let_token));
    }

    fn parse_block(self: *Self) Error!Ast.Index {
        if (!self.check_next(lex.TokenKind.LBRACE)) {
            print_token_error(
                .Error,
                &self.next_token.?,
                "Expected '{{' to begin block.",
                .{},
                null,
                .{},
            );
            return Error.InvalidToken;
        }
        const open_token = try self.consume_token();
        var stmts = std.ArrayList(Ast.Index){};
        while (!self.check_next(lex.TokenKind.RBRACE)) {
            if (!self.has_next()) {
                print_token_error(
                    .Error,
                    &open_token,
                    "Unclosed block.",
                    .{},
                    "Ensure the block is closed with '}}'.",
                    .{},
                );
                return Error.MissingToken;
            }
            try stmts.append(self.allocator, try self.parse_statement());
        }
        _ = try self.consume_token();
        return self.ast.append(
            AstItem{ .block = .{ .stmts = stmts } },
            AstItemSource.from_token(open_token),
        );
    }

    fn parse_return_statement(self: *Self) Error!Ast.Index {
        const return_token = try self.consume_token();
        var value: ?Ast.Index = null;
        if (!self.check_next(lex.TokenKind.SEMICOLON)) {
            value = try self.parse_expression();
        }
        if (!self.check_next(lex.TokenKind.SEMICOLON)) {
            print_token_error(
                .Error,
                &self.next_token.?,
                "Expected ';' after return statement.",
                .{},
                null,
                .{},
            );
            return Error.InvalidToken;
        }
        _ = try self.consume_token();
        return self.ast.append(
            AstItem{ .return_statement = .{ .value = value } },
            AstItemSource.from_token(return_token),
        );
    }

    fn parse_loop_control_statement(self: *Self) Error!Ast.Index {
        const control_token = try self.consume_token();
        const item: AstItem = switch (control_token.kind) {
            lex.TokenKind.BREAK => AstItem{ .loop_control = .BREAK },
            lex.TokenKind.CONTINUE => AstItem{ .loop_control = .CONTINUE },
            else => unreachable,
        };
        if (!self.check_next(lex.TokenKind.SEMICOLON)) {
            print_token_error(
                .Error,
                &self.next_token.?,
                "Expected ';' after statement.",
                .{},
                null,
                .{},
            );
            return Error.InvalidToken;
        }
        _ = try self.consume_token();
        return self.ast.append(item, AstItemSource.from_token(control_token));
    }

    fn parse_if_statement(self: *Self) Error!Ast.Index {
        const if_token = try self.consume_token();
        const condition = try self.parse_expression();
        const then_body = try self.parse_block();
        var else_body: ?Ast.Index = null;
        if (self.check_next(lex.TokenKind.ELSE)) {
            _ = try self.consume_token();
            else_body = if (self.check_next(lex.TokenKind.IF))
                try self.parse_if_statement()
            else
                try self.parse_block();
        }
        return self.ast.append(
            AstItem{ .if_statement = .{
                .condition = condition,
                .then_body = then_body,
                .else_body = else_body,
            } },
            AstItemSource.from_token(if_token),
        );
    }

    fn parse_for_statement(self: *Self) Error!Ast.Index {
        const for_token = try self.consume_token();
        if (!self.check_next(lex.TokenKind.IDENTIFIER)) {
            print_token_error(
                .Error,
                &self.next_token.?,
                "Expected loop variable identifier after 'for'.",
                .{},
                null,
                .{},
            );
            return Error.InvalidToken;
        }
        const loop_var_token = try self.consume_token();
        if (!self.check_next(lex.TokenKind.IN)) {
            print_token_error(
                .Error,
                &self.next_token.?,
                "Expected 'in' after loop variable.",
                .{},
                null,
                .{},
            );
            return Error.InvalidToken;
        }
        _ = try self.consume_token();
        const iter_expr = try self.parse_expression();
        const body = try self.parse_block();
        return self.ast.append(
            AstItem{ .for_statement = .{
                .loop_var = loop_var_token.str.?,
                .iter_expr = iter_expr,
                .body = body,
            } },
            AstItemSource.from_token(for_token),
        );
    }

    fn parse_while_statement(self: *Self) Error!Ast.Index {
        const while_token = try self.consume_token();
        const condition = try self.parse_expression();
        const body = try self.parse_block();
        return self.ast.append(
            AstItem{ .while_statement = .{ .condition = condition, .body = body } },
            AstItemSource.from_token(while_token),
        );
    }

    fn parse_expression(self: *Self) Error!Ast.Index {
        return self.parse_or_expression();
    }

    fn parse_or_expression(self: *Self) Error!Ast.Index {
        var left_expr = try self.parse_and_expression();
        while (self.check_next(lex.TokenKind.OR)) {
            const or_token = try self.consume_token();
            const right_expr = try self.parse_and_expression();
            left_expr = try self.ast.append(
                AstItem{ .binary_expression = .{
                    .left_expr = left_expr,
                    .right_expr = right_expr,
                    .operator = .OR,
                } },
                AstItemSource.from_token(or_token),
            );
        }
        return left_expr;
    }

    fn parse_and_expression(self: *Self) Error!Ast.Index {
        var left_expr = try self.parse_not_expression();
        while (self.check_next(lex.TokenKind.AND)) {
            const and_token = try self.consume_token();
            const right_expr = try self.parse_not_expression();
            left_expr = try self.ast.append(
                AstItem{ .binary_expression = .{
                    .left_expr = left_expr,
                    .right_expr = right_expr,
                    .operator = .AND,
                } },
                AstItemSource.from_token(and_token),
            );
        }
        return left_expr;
    }

    fn parse_not_expression(self: *Self) Error!Ast.Index {
        if (!self.check_next(lex.TokenKind.EXCLAMATION)) {
            return self.parse_compare_expression();
        }
        const not_token = try self.consume_token();
        const inner_expr = try self.parse_compare_expression();
        return self.ast.append(
            AstItem{ .unary_expression = .{ .inner_expr = inner_expr, .operator = .NOT } },
            AstItemSource.from_token(not_token),
        );
    }

    fn parse_compare_expression(self: *Self) Error!Ast.Index {
        const left_expr = try self.parse_range_expression();
        if (!self.has_next()) {
            return left_expr;
        }
        var expr = AstItem{
            .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = undefined,
                .operator = undefined,
            },
        };
        expr.binary_expression.operator = op: switch (self.next_token.?.kind) {
            lex.TokenKind.EQUAL => break :op .EQUAL,
            lex.TokenKind.NOT_EQUAL => break :op .NOT_EQUAL,
            lex.TokenKind.GREATER => break :op .GREATER,
            lex.TokenKind.LESS => break :op .LESS,
            lex.TokenKind.GREATER_EQUAL => break :op .GREATER_EQUAL,
            lex.TokenKind.LESS_EQUAL => break :op .LESS_EQUAL,
            else => return left_expr,
        };
        const compare_token = try self.consume_token();
        expr.binary_expression.right_expr = try self.parse_range_expression();
        return self.ast.append(expr, AstItemSource.from_token(compare_token));
    }

    fn parse_range_expression(self: *Self) Error!Ast.Index {
        const left_expr = try self.parse_bitwise_or_expression();
        if (!self.check_next(lex.TokenKind.DOUBLE_DOT)) {
            return left_expr;
        }
        const dot_token = try self.consume_token();
        const right_expr = try self.parse_bitwise_or_expression();
        return self.ast.append(
            AstItem{ .binary_expression = .{
                .left_expr = left_expr,
                .right_expr = right_expr,
                .operator = .RANGE,
            } },
            AstItemSource.from_token(dot_token),
        );
    }

    fn parse_bitwise_or_expression(self: *Self) Error!Ast.Index {
        var left_expr = try self.parse_bitwise_xor_expression();
        while (self.check_next(lex.TokenKind.PIPE)) {
            const pipe_token = try self.consume_token();
            const right_expr = try self.parse_bitwise_xor_expression();
            left_expr = try self.ast.append(
                AstItem{ .binary_expression = .{
                    .left_expr = left_expr,
                    .right_expr = right_expr,
                    .operator = .BIT_OR,
                } },
                AstItemSource.from_token(pipe_token),
            );
        }
        return left_expr;
    }

    fn parse_bitwise_xor_expression(self: *Self) Error!Ast.Index {
        var left_expr = try self.parse_bitwise_and_expression();
        while (self.check_next(lex.TokenKind.CARET)) {
            const caret_token = try self.consume_token();
            const right_expr = try self.parse_bitwise_and_expression();
            left_expr = try self.ast.append(
                AstItem{ .binary_expression = .{
                    .left_expr = left_expr,
                    .right_expr = right_expr,
                    .operator = .BIT_XOR,
                } },
                AstItemSource.from_token(caret_token),
            );
        }
        return left_expr;
    }

    fn parse_bitwise_and_expression(self: *Self) Error!Ast.Index {
        var left_expr = try self.parse_bitshift_expression();
        while (self.check_next(lex.TokenKind.AMPERSAND)) {
            const ampersand_token = try self.consume_token();
            const right_expr = try self.parse_bitshift_expression();
            left_expr = try self.ast.append(
                AstItem{ .binary_expression = .{
                    .left_expr = left_expr,
                    .right_expr = right_expr,
                    .operator = .BIT_AND,
                } },
                AstItemSource.from_token(ampersand_token),
            );
        }
        return left_expr;
    }

    fn parse_bitshift_expression(self: *Self) Error!Ast.Index {
        var left_expr = try self.parse_addition_expression();
        while (self.has_next()) {
            var expr = AstItem{
                .binary_expression = .{
                    .left_expr = left_expr,
                    .right_expr = undefined,
                    .operator = undefined,
                },
            };
            expr.binary_expression.operator = op: switch (self.next_token.?.kind) {
                lex.TokenKind.DOUBLE_GREATER => break :op .BITSHIFT_RIGHT,
                lex.TokenKind.DOUBLE_LESS => break :op .BITSHIFT_LEFT,
                else => break,
            };
            const bitshift_token = try self.consume_token();
            expr.binary_expression.right_expr = try self.parse_addition_expression();
            left_expr = try self.ast.append(expr, AstItemSource.from_token(bitshift_token));
        }
        return left_expr;
    }

    fn parse_addition_expression(self: *Self) Error!Ast.Index {
        var left_expr = try self.parse_multiply_expression();
        while (self.has_next()) {
            var expr = AstItem{
                .binary_expression = .{
                    .left_expr = left_expr,
                    .right_expr = undefined,
                    .operator = undefined,
                },
            };
            expr.binary_expression.operator = op: switch (self.next_token.?.kind) {
                lex.TokenKind.PLUS => break :op .ADD,
                lex.TokenKind.MINUS => break :op .SUBTRACT,
                else => break,
            };
            const op_token = try self.consume_token();
            expr.binary_expression.right_expr = try self.parse_multiply_expression();
            left_expr = try self.ast.append(expr, AstItemSource.from_token(op_token));
        }
        return left_expr;
    }

    fn parse_multiply_expression(self: *Self) Error!Ast.Index {
        var left_expr = try self.parse_arithmetic_unary_expression();
        while (self.has_next()) {
            var expr = AstItem{
                .binary_expression = .{
                    .left_expr = left_expr,
                    .right_expr = undefined,
                    .operator = undefined,
                },
            };
            expr.binary_expression.operator = op: switch (self.next_token.?.kind) {
                lex.TokenKind.ASTERISK => break :op .MULTIPLY,
                lex.TokenKind.SLASH => break :op .DIVIDE,
                else => break,
            };
            const op_token = try self.consume_token();
            expr.binary_expression.right_expr = try self.parse_arithmetic_unary_expression();
            left_expr = try self.ast.append(expr, AstItemSource.from_token(op_token));
        }
        return left_expr;
    }

    fn parse_arithmetic_unary_expression(self: *Self) Error!Ast.Index {
        if (self.check_next(lex.TokenKind.MINUS)) {
            const op_token = try self.consume_token();
            const inner_expr = try self.parse_nonoperator_expression();
            return self.ast.append(
                AstItem{ .unary_expression = .{ .inner_expr = inner_expr, .operator = .MINUS } },
                AstItemSource.from_token(op_token),
            );
        }
        if (self.check_next(lex.TokenKind.TILDE)) {
            const op_token = try self.consume_token();
            const inner_expr = try self.parse_nonoperator_expression();
            return self.ast.append(
                AstItem{ .unary_expression = .{ .inner_expr = inner_expr, .operator = .BIT_INVERSE } },
                AstItemSource.from_token(op_token),
            );
        }
        return self.parse_nonoperator_expression();
    }

    fn parse_nonoperator_expression(self: *Self) Error!Ast.Index {
        var outer_expr = try self.parse_prioritized_expression();
        outer_loop: while (true) {
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
                        outer_expr = try self.ast.append(expr, AstItemSource.from_token(token));
                        continue;
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
                    var args = try std.ArrayList(Ast.Index).initCapacity(self.allocator, 4);
                    while (!self.check_next(lex.TokenKind.RPAREN)) {
                        const expr = try self.parse_expression();
                        try args.append(self.allocator, expr);
                        if (self.check_next(lex.TokenKind.COMMA)) {
                            _ = try self.consume_token();
                        }
                    }
                    if (self.check_next(lex.TokenKind.RPAREN)) {
                        _ = try self.consume_token();
                        const expr = AstItem{
                            .function_call = .{
                                .function_expr = outer_expr,
                                .args_expr = args,
                            },
                        };
                        outer_expr = try self.ast.append(expr, AstItemSource.from_token(token));
                        continue;
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
                    _ = try self.consume_token();
                    if (!self.has_next()) {
                        print_token_error(
                            .Error,
                            &token,
                            "Found start of field access without field or function name.",
                            .{},
                            null,
                            .{},
                        );
                        return Error.InvalidToken;
                    }
                    const access_token = self.next_token.?;
                    switch (access_token.kind) {
                        lex.TokenKind.ASTERISK => {
                            _ = try self.consume_token();
                            const expr = AstItem{
                                .primitive_access = .{
                                    .outer_expr = outer_expr,
                                    .access_type = .DEREFERENCE,
                                },
                            };
                            outer_expr = try self.ast.append(expr, AstItemSource.from_token(access_token));
                        },
                        lex.TokenKind.AMPERSAND => {
                            _ = try self.consume_token();
                            const expr = AstItem{
                                .primitive_access = .{
                                    .outer_expr = outer_expr,
                                    .access_type = .ADDRESS,
                                },
                            };
                            outer_expr = try self.ast.append(expr, AstItemSource.from_token(access_token));
                        },
                        lex.TokenKind.QUESTION => {
                            _ = try self.consume_token();
                            const expr = AstItem{
                                .primitive_access = .{
                                    .outer_expr = outer_expr,
                                    .access_type = .UNWRAP_CHECKED,
                                },
                            };
                            outer_expr = try self.ast.append(expr, AstItemSource.from_token(access_token));
                        },
                        lex.TokenKind.EXCLAMATION => {
                            _ = try self.consume_token();
                            const expr = AstItem{
                                .primitive_access = .{
                                    .outer_expr = outer_expr,
                                    .access_type = .UNWRAP_UNCHECKED,
                                },
                            };
                            outer_expr = try self.ast.append(expr, AstItemSource.from_token(access_token));
                        },
                        lex.TokenKind.IDENTIFIER => {
                            const expr = AstItem{
                                .field_access = .{
                                    .outer_expr = outer_expr,
                                    .field_name = try self.parse_nonoperator_expression(),
                                },
                            };
                            outer_expr = try self.ast.append(expr, AstItemSource.from_token(access_token));
                        },
                        else => {
                            print_token_error(
                                .Error,
                                &access_token,
                                "Expected field access or one of .* .& .? .! but instead found:",
                                .{},
                                null,
                                .{},
                            );
                            return Error.InvalidToken;
                        },
                    }
                },
                else => {
                    break :outer_loop;
                },
            }
        }
        return outer_expr;
    }

    fn parse_labeled_body(self: *Self, close: lex.TokenKind) Error!std.ArrayList(LabeledExpr) {
        var members = std.ArrayList(LabeledExpr){};
        while (!self.check_next(close)) {
            if (!self.has_next()) {
                return Error.MissingToken;
            }
            if (!self.check_next(lex.TokenKind.IDENTIFIER)) {
                print_token_error(
                    .Error,
                    &self.next_token.?,
                    "Expected field name.",
                    .{},
                    null,
                    .{},
                );
                return Error.InvalidToken;
            }
            const label_token = try self.consume_token();
            if (!self.check_next(lex.TokenKind.COLON)) {
                print_token_error(
                    .Error,
                    &self.next_token.?,
                    "Expected ':' after field name.",
                    .{},
                    null,
                    .{},
                );
                return Error.InvalidToken;
            }
            _ = try self.consume_token();
            const type_expr = try self.parse_expression();
            try members.append(self.allocator, .{ .label = label_token.str.?, .type_expr = type_expr });
            if (self.check_next(lex.TokenKind.COMMA)) {
                _ = try self.consume_token();
            }
        }
        return members;
    }

    fn parse_prioritized_expression(self: *Self) Error!Ast.Index {
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
                const i: u64 = std.fmt.parseInt(u64, token.str.?, 10) catch |err| {
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
                expr = AstItem{ .identifier = token.str.? };
                source = AstItemSource.from_token(try self.consume_token());
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
            lex.TokenKind.STRUCT => {
                const struct_token = try self.consume_token();
                if (!self.check_next(lex.TokenKind.LBRACE)) {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected '{{' after 'struct'.",
                        .{},
                        null,
                        .{},
                    );
                    return Error.InvalidToken;
                }
                _ = try self.consume_token();
                const members = try self.parse_labeled_body(lex.TokenKind.RBRACE);
                if (!self.check_next(lex.TokenKind.RBRACE)) {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected '}}' to close struct.",
                        .{},
                        null,
                        .{},
                    );
                    return Error.InvalidToken;
                }
                _ = try self.consume_token();
                return self.ast.append(
                    AstItem{ .struct_type = .{ .members = members } },
                    AstItemSource.from_token(struct_token),
                );
            },
            lex.TokenKind.VARIANT => {
                const variant_token = try self.consume_token();
                if (!self.check_next(lex.TokenKind.LBRACE)) {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected '{{' after 'variant'.",
                        .{},
                        null,
                        .{},
                    );
                    return Error.InvalidToken;
                }
                _ = try self.consume_token();
                const members = try self.parse_labeled_body(lex.TokenKind.RBRACE);
                if (!self.check_next(lex.TokenKind.RBRACE)) {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected '}}' to close variant.",
                        .{},
                        null,
                        .{},
                    );
                    return Error.InvalidToken;
                }
                _ = try self.consume_token();
                return self.ast.append(
                    AstItem{ .variant_type = .{ .members = members } },
                    AstItemSource.from_token(variant_token),
                );
            },
            lex.TokenKind.INTERFACE => {
                const interface_token = try self.consume_token();
                if (!self.check_next(lex.TokenKind.LBRACE)) {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected '{{' after 'interface'.",
                        .{},
                        null,
                        .{},
                    );
                    return Error.InvalidToken;
                }
                _ = try self.consume_token();
                const members = try self.parse_labeled_body(lex.TokenKind.RBRACE);
                if (!self.check_next(lex.TokenKind.RBRACE)) {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected '}}' to close interface.",
                        .{},
                        null,
                        .{},
                    );
                    return Error.InvalidToken;
                }
                _ = try self.consume_token();
                return self.ast.append(
                    AstItem{ .interface = .{ .members = members } },
                    AstItemSource.from_token(interface_token),
                );
            },
            lex.TokenKind.FN => {
                const fn_token = try self.consume_token();
                if (!self.check_next(lex.TokenKind.LPAREN)) {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected '(' after 'fn'.",
                        .{},
                        null,
                        .{},
                    );
                    return Error.InvalidToken;
                }
                _ = try self.consume_token();
                const arguments = try self.parse_labeled_body(lex.TokenKind.RPAREN);
                if (!self.check_next(lex.TokenKind.RPAREN)) {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected ')' after function parameters.",
                        .{},
                        null,
                        .{},
                    );
                    return Error.InvalidToken;
                }
                _ = try self.consume_token();
                if (!self.check_next(lex.TokenKind.ARROW)) {
                    print_token_error(
                        .Error,
                        &self.next_token.?,
                        "Expected '->' after function parameters.",
                        .{},
                        null,
                        .{},
                    );
                    return Error.InvalidToken;
                }
                _ = try self.consume_token();
                const return_type_expr = try self.parse_expression();
                const body = try self.parse_block();
                return self.ast.append(
                    AstItem{
                        .func_def = .{
                            .arguments = arguments,
                            .return_type_expr = return_type_expr,
                            .body = body,
                        },
                    },
                    AstItemSource.from_token(fn_token),
                );
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
            if (self.next_token.?.kind == lex.TokenKind.EOF) {
                _ = self.consume_token() catch unreachable;
                continue;
            }
            const index = try self.parse_statement();
            try self.ast.top_level.append(self.allocator, index);
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
