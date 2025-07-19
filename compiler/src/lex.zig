// SPDX-License-Identifier: MIT
const std = @import("std");

const errmsg = @import("error_messages.zig");

const SourceFile = @import("sources.zig").SourceFile;

const READER_BUFFER_SIZE = 4096;
const BufferedReader = std.io.BufferedReader(READER_BUFFER_SIZE, std.fs.File.Reader);

const Scanner = struct {
    source: *const SourceFile,
    line_buf: []const u8,
    line_num: u32,
    col: u32,
    unicode_view: std.unicode.Utf8View,
    unicode_iterator: std.unicode.Utf8Iterator,

    const Self = @This();
    const Error = error{ InvalidSourceFile, EndOfFile };

    fn init(source: *const SourceFile) !Self {
        const line_buf = source.get_line(1) orelse return Error.InvalidSourceFile;
        const view = try std.unicode.Utf8View.init(line_buf);
        var new_scanner = Self{
            .source = source,
            .line_buf = line_buf,
            .line_num = 1,
            .col = 0,
            .unicode_view = view,
            .unicode_iterator = view.iterator(),
        };
        try new_scanner.advance_line();
        return new_scanner;
    }

    fn advance_line(self: *Self) !void {
        if (self.line_num >= self.source.get_line_count()) {
            return Error.EndOfFile;
        }
        self.line_num += 1;
        self.line_buf = self.source.get_line(self.line_num).?;
        self.col = 0;
        self.unicode_view = try std.unicode.Utf8View.init(self.line_buf);
        self.unicode_iterator = self.unicode_view.iterator();
    }

    fn consume(self: *Self) ?[]const u8 {
        const codepoint = self.unicode_iterator.nextCodepointSlice();
        if (codepoint != null) {
            self.col += 1;
            return codepoint;
        }
        self.advance_line() catch {
            return null;
        };
        const potential_codepoint = self.unicode_iterator.nextCodepointSlice();
        if (potential_codepoint != null) {
            self.col += 1;
        }
        return potential_codepoint;
    }

    fn peek(self: *Self) ?[]const u8 {
        const codepoint = self.unicode_iterator.peek(1);
        if (codepoint.len > 0) {
            return codepoint;
        }
        self.advance_line() catch {
            return null;
        };
        return self.unicode_iterator.peek(1);
    }
};

pub const TokenKind = enum {
    INVALID,

    DOT,
    COMMA,
    COLON,
    SEMICOLON,

    DOUBLE_DOT,
    ARROW,

    DOUBLE_PLUS,
    DOUBLE_ASTERISK,

    PLUS,
    MINUS,
    ASTERISK,
    SLASH,

    LPAREN,
    RPAREN,
    LBRACE,
    RBRACE,
    LBRACKET,
    RBRACKET,

    EXCLAMATION,
    QUESTION,

    EQUAL,
    NOT_EQUAL,
    GREATER,
    LESS,
    GREATER_EQUAL,
    LESS_EQUAL,

    ASSIGN,

    NUMBER,
    IDENTIFIER,
    STRING_LITERAL,
    TRUE,
    FALSE,

    STRUCT,
    ENUM,
    UNION,
    TRAIT,
    FN,
    OWN,
    FOR,
    WHILE,
    IF,
    IN,
    AND,
    OR,
    ELSE,
    BREAK,
    CONTINUE,
    RETURN,
    LET,
    MUT,
};

const TokenSource = struct {
    file: *const SourceFile,
    line: u32,
    col: u32,
};

pub const Token = struct {
    kind: TokenKind,
    source: TokenSource,
    str: ?[]const u8,
};

pub const Lexer = struct {
    scanner: Scanner,
    allocator: std.mem.Allocator,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source_file: *const SourceFile) !Self {
        return Self{
            .scanner = try Scanner.init(source_file),
            .allocator = allocator,
        };
    }

    fn consume_until_ascii(self: *Self) void {
        var codepoint = self.scanner.peek() orelse return;
        while (codepoint.len > 1) {
            _ = self.scanner.consume();
            errmsg.print_error(
                .Error,
                self.scanner.source,
                self.scanner.line_num,
                self.scanner.col,
                1,
                "Invalid Character Error: Unicode character '{s}'",
                .{codepoint},
                "please remove, unicode character '{s}' may only be used inside a string literal",
                .{codepoint},
            );
            codepoint = self.scanner.peek() orelse return;
        }
    }

    fn consume_ascii(self: *Self) ?u8 {
        self.consume_until_ascii();
        const codepoint = self.scanner.consume() orelse return null;
        std.debug.assert(codepoint.len == 1);
        return codepoint[0];
    }

    fn peek_ascii(self: *Self) ?u8 {
        self.consume_until_ascii();
        const codepoint = self.scanner.peek() orelse return null;
        if (codepoint.len != 1) {
            std.debug.print("Codepoint: '{s}'", .{codepoint});
        }
        std.debug.assert(codepoint.len == 1);
        return codepoint[0];
    }

    pub fn next_token(self: *Self) !?Token {
        var first_byte = self.consume_ascii() orelse return null;
        while (std.ascii.isWhitespace(first_byte)) {
            first_byte = self.consume_ascii() orelse return null;
        }

        var token = Token{
            .kind = TokenKind.INVALID,
            .source = .{
                .file = self.scanner.source,
                .line = self.scanner.line_num,
                .col = self.scanner.col,
            },
            .str = null,
        };

        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();
        try buffer.append(first_byte);

        switch (first_byte) {
            '.' => {
                const next = self.peek_ascii();
                if (next != null and next.? == '.') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.DOUBLE_DOT;
                } else {
                    token.kind = TokenKind.DOT;
                }
            },
            ',' => token.kind = TokenKind.COMMA,
            ':' => token.kind = TokenKind.COLON,
            ';' => token.kind = TokenKind.SEMICOLON,
            '(' => token.kind = TokenKind.LPAREN,
            ')' => token.kind = TokenKind.RPAREN,
            '{' => token.kind = TokenKind.LBRACE,
            '}' => token.kind = TokenKind.RBRACE,
            '[' => token.kind = TokenKind.LBRACKET,
            ']' => token.kind = TokenKind.RBRACKET,
            '+' => {
                const next = self.peek_ascii();
                if (next != null and next.? == '+') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.DOUBLE_PLUS;
                } else {
                    token.kind = TokenKind.PLUS;
                }
            },
            '-' => {
                const next = self.peek_ascii();
                if (next != null and next.? == '>') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.ARROW;
                } else {
                    token.kind = TokenKind.MINUS;
                }
            },
            '*' => {
                const next = self.peek_ascii();
                if (next != null and next.? == '*') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.DOUBLE_ASTERISK;
                } else {
                    token.kind = TokenKind.ASTERISK;
                }
            },
            '/' => {
                var next = self.peek_ascii();
                var is_comment = (next != null and next.? == '/');
                while (is_comment) {
                    _ = self.consume_ascii();

                    while (self.scanner.consume()) |codepoint| {
                        if (codepoint.len == 1 and codepoint[0] == '\n') {
                            break;
                        }
                    }
                    while (self.peek_ascii()) |byte| {
                        if (!std.ascii.isWhitespace(byte)) {
                            break;
                        }
                        _ = self.consume_ascii();
                    }

                    const first_next_line = self.peek_ascii();
                    if (first_next_line == null or first_next_line.? != '/') {
                        return self.next_token();
                    }
                    std.debug.assert(self.consume_ascii().? == '/');
                    next = self.peek_ascii();
                    is_comment = (next != null and next.? == '/');
                }
                token.kind = TokenKind.SLASH;
            },
            '?' => token.kind = TokenKind.QUESTION,
            '!' => {
                const next = self.peek_ascii();
                if (next != null and next.? == '=') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.NOT_EQUAL;
                } else {
                    token.kind = TokenKind.EXCLAMATION;
                }
            },
            '=' => {
                const next = self.peek_ascii();
                if (next != null and next.? == '=') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.EQUAL;
                } else {
                    token.kind = TokenKind.ASSIGN;
                }
            },
            '>' => {
                const next = self.peek_ascii();
                if (next != null and next.? == '=') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.GREATER_EQUAL;
                } else {
                    token.kind = TokenKind.GREATER;
                }
            },
            '<' => {
                const next = self.peek_ascii();
                if (next != null and next.? == '=') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.LESS_EQUAL;
                } else {
                    token.kind = TokenKind.LESS;
                }
            },
            '"' => {
                buffer.clearRetainingCapacity();
                var terminated: bool = false;
                while (self.scanner.consume()) |codepoint| {
                    if (codepoint.len == 1) {
                        if (codepoint[0] == '"') {
                            terminated = true;
                            break;
                        } else if (codepoint[0] == '\n') {
                            break;
                        }
                    }
                    try buffer.appendSlice(codepoint);
                }
                if (terminated) {
                    token.kind = TokenKind.STRING_LITERAL;
                    token.str = try self.allocator.dupe(u8, buffer.items);
                } else {
                    token.kind = TokenKind.INVALID;
                    errmsg.print_error(
                        .Error,
                        token.source.file,
                        token.source.line,
                        token.source.col,
                        buffer.items.len + 1,
                        "Syntax Error: Unterminated string literal",
                        .{},
                        "add terminating '\"'",
                        .{},
                    );
                }
            },
            '0'...'9' => {
                token.kind = TokenKind.NUMBER;
                while (self.peek_ascii()) |byte| {
                    switch (byte) {
                        '0'...'9' => {
                            try buffer.append(self.consume_ascii().?);
                        },
                        else => break,
                    }
                }
                token.str = try self.allocator.dupe(u8, buffer.items);
            },
            'a'...'z', 'A'...'Z', '_' => {
                while (self.peek_ascii()) |byte| {
                    switch (byte) {
                        'a'...'z', 'A'...'Z', '_', '0'...'9' => {
                            try buffer.append(self.consume_ascii().?);
                        },
                        else => break,
                    }
                }

                switch (first_byte) {
                    'a' => {
                        if (std.mem.eql(u8, buffer.items[1..], "nd")) {
                            token.kind = TokenKind.AND;
                        }
                    },
                    'b' => {
                        if (std.mem.eql(u8, buffer.items[1..], "reak")) {
                            token.kind = TokenKind.BREAK;
                        }
                    },
                    'c' => {
                        if (std.mem.eql(u8, buffer.items[1..], "ontinue")) {
                            token.kind = TokenKind.CONTINUE;
                        }
                    },
                    'e' => {
                        if (std.mem.eql(u8, buffer.items[1..], "lse")) {
                            token.kind = TokenKind.ELSE;
                        } else if (std.mem.eql(u8, buffer.items[1..], "num")) {
                            token.kind = TokenKind.ENUM;
                        }
                    },
                    'f' => {
                        if (std.mem.eql(u8, buffer.items[1..], "n")) {
                            token.kind = TokenKind.FN;
                        } else if (std.mem.eql(u8, buffer.items[1..], "or")) {
                            token.kind = TokenKind.FOR;
                        } else if (std.mem.eql(u8, buffer.items[1..], "alse")) {
                            token.kind = TokenKind.FALSE;
                        }
                    },
                    'i' => {
                        if (std.mem.eql(u8, buffer.items[1..], "f")) {
                            token.kind = TokenKind.IF;
                        } else if (std.mem.eql(u8, buffer.items[1..], "n")) {
                            token.kind = TokenKind.IN;
                        }
                    },
                    'l' => {
                        if (std.mem.eql(u8, buffer.items[1..], "et")) {
                            token.kind = TokenKind.LET;
                        }
                    },
                    'm' => {
                        if (std.mem.eql(u8, buffer.items[1..], "ut")) {
                            token.kind = TokenKind.MUT;
                        }
                    },
                    'o' => {
                        if (std.mem.eql(u8, buffer.items[1..], "r")) {
                            token.kind = TokenKind.OR;
                        } else if (std.mem.eql(u8, buffer.items[1..], "wn")) {
                            token.kind = TokenKind.OWN;
                        }
                    },
                    'r' => {
                        if (std.mem.eql(u8, buffer.items[1..], "eturn")) {
                            token.kind = TokenKind.RETURN;
                        }
                    },
                    's' => {
                        if (std.mem.eql(u8, buffer.items[1..], "truct")) {
                            token.kind = TokenKind.STRUCT;
                        }
                    },
                    't' => {
                        if (std.mem.eql(u8, buffer.items[1..], "rait")) {
                            token.kind = TokenKind.TRAIT;
                        } else if (std.mem.eql(u8, buffer.items[1..], "rue")) {
                            token.kind = TokenKind.TRUE;
                        }
                    },
                    'u' => {
                        if (std.mem.eql(u8, buffer.items[1..], "nion")) {
                            token.kind = TokenKind.UNION;
                        }
                    },
                    'w' => {
                        if (std.mem.eql(u8, buffer.items[1..], "hile")) {
                            token.kind = TokenKind.WHILE;
                        }
                    },
                    else => {},
                }

                if (token.kind == TokenKind.INVALID) {
                    token.kind = TokenKind.IDENTIFIER;
                    token.str = try self.allocator.dupe(u8, buffer.items);
                }
            },
            else => {
                errmsg.print_error(
                    .Error,
                    token.source.file,
                    token.source.line,
                    token.source.col,
                    1,
                    "Syntax Error: Invalid token '{s}'",
                    .{buffer.items},
                    "please remove, '{s}' may only be used inside a string literal",
                    .{buffer.items},
                );
                token.kind = TokenKind.INVALID;
                token.str = try self.allocator.dupe(u8, buffer.items);
            },
        }

        return token;
    }
};
