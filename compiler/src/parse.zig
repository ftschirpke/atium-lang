const std = @import("std");

const lex = @import("lex.zig");
const collections = @import("collections.zig");

const AstItem = union(enum) {
    boolean_literal: bool,
    integer_literal: u64,
    string_literal: []const u8,
};

const List = collections.TaggedUnionList(AstItem);

const Parser = struct {
    list: List,
    top_level: std.ArrayList(List.Index),
    lexer: *lex.Lexer,
    next_token: ?lex.Token,

    const Self = @This();
    const Error = error{InvalidToken};

    pub fn init(allocator: std.mem.Allocator, lexer: *lex.Lexer) Self {
        const top_level = std.ArrayList(List.Index).init(allocator);
        const list = List.init(allocator);
        return Self{ .top_level = top_level, .list = list, .lexer = lexer };
    }

    pub fn deinit(self: Self) void {
        self.list.deinit();
        self.top_level.deinit();
    }

    fn grab_next_token(self: *Self) void {
        self.next_token = self.lexer.next_token() catch return false;
    }

    fn has_next(self: *Self) bool {
        return self.next_token != null;
    }

    fn check_next(self: *Self, expected: lex.TokenKind) bool {
        return self.has_next() and self.next_token.?.kind == expected;
    }

    fn parse_expression(self: *Self) !List.Index {
        std.debug.assert(self.has_next());

        var expr: AstItem = undefined;

        const token = self.next_token.?;
        switch (token.kind) {
            lex.TokenKind.TRUE => {
                expr = AstItem{ .boolean_literal = true };
            },
            lex.TokenKind.FALSE => {
                expr = AstItem{ .boolean_literal = false };
            },
            lex.TokenKind.NUMBER => {
                const i: u64 = std.fmt.parseInt(token.str) catch |err| {
                    switch (err) {
                        std.fmt.ParseIntError.Overflow => {
                            self.lexer.print_error(
                                &token.source,
                                token.str.?.len,
                                "Integer {} does not fit into 64 bits",
                                .{token.str.?},
                                "",
                            );
                        },
                    }
                };
                expr = AstItem{ .integer_literal = i };
            },
            lex.TokenKind.STRING_LITERAL => {
                expr = AstItem{ .string_literal = token.str.? };
            },
            else => {
                self.lexer.print_error(&token.source, 1, "Expected expression; unexpected token", .{}, "");
                return Error.InvalidToken;
            },
        }

        return self.list.append(expr);
    }

    pub fn parse(self: *Self) !void {
        self.grab_next_token();

        while (self.has_next()) {
            // HACK: only to test current implementation
            self.parse_expression();
        }
    }
};
