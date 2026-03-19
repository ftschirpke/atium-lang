// SPDX-License-Identifier: MIT
const std = @import("std");

const errmsg = @import("error_messages.zig");
const world = @import("world.zig");

const SourceFile = world.SourceFile;
const SourceReader = world.SourceReader;

const Scanner = struct {
    reader: SourceReader,
    line_buf: []const u8,
    line_num: u32,
    col: u32,
    unicode_view: std.unicode.Utf8View,
    unicode_iterator: std.unicode.Utf8Iterator,

    const Self = @This();
    const Error = error{ FileOpenError, InvalidSourceFile, EndOfFile };

    fn init(source: *SourceFile) !Self {
        // TODO: allow one-line source files
        var reader = source.reader() catch {
            return Error.FileOpenError;
        };
        const line_buf = reader.get_next_line() catch {
            return Error.InvalidSourceFile;
        };
        const view = try std.unicode.Utf8View.init(line_buf);
        var new_scanner = Self{
            .reader = reader,
            .line_buf = line_buf,
            .line_num = 1,
            .col = 0,
            .unicode_view = view,
            .unicode_iterator = view.iterator(),
        };
        if (!new_scanner.advance_line()) {
            return Error.InvalidSourceFile;
        }
        return new_scanner;
    }

    fn advance_line(self: *Self) bool {
        self.line_buf = self.reader.get_next_line() catch |err| switch (err) {
            SourceReader.Error.EndOfFile => return false,
            SourceReader.Error.ReadError => {
                std.log.err("Unexpected problem while reading file {s}.", .{self.reader.source.path.items});
                return false;
            },
        };
        self.line_num += 1;
        self.col = 0;
        self.unicode_view = std.unicode.Utf8View.init(self.line_buf) catch |err| {
            std.log.err("Unexpected problem while reading line '{s}' as utf-8 string - {}", .{ self.line_buf, err });
            return false;
        };
        self.unicode_iterator = self.unicode_view.iterator();
        return true;
    }

    fn consume(self: *Self) ?[]const u8 {
        const codepoint = self.unicode_iterator.nextCodepointSlice();
        if (codepoint != null) {
            self.col += 1;
            return codepoint;
        }
        if (!self.advance_line()) {
            return null;
        }
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
        if (!self.advance_line()) {
            return null;
        }
        return self.unicode_iterator.peek(1);
    }
};

pub const TokenKind = enum {
    INVALID,
    EOF,

    DOT,
    COMMA,
    COLON,
    SEMICOLON,

    DOUBLE_DOT,
    ARROW,

    DOUBLE_PLUS,
    DOUBLE_ASTERISK,

    DOUBLE_LESS,
    DOUBLE_GREATER,

    PLUS,
    MINUS,
    ASTERISK,
    SLASH,

    PIPE,
    AMPERSAND,
    CARET,
    TILDE,

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
    SELF,
    SELF_TYPE,
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
    file: *SourceFile,
    line: u32,
    col: u32,
};

pub const Token = struct {
    kind: TokenKind,
    source: TokenSource,
    str: ?[]const u8,

    const Self = @This();

    pub fn len(self: *const Self) u32 {
        switch (self.kind) {
            TokenKind.INVALID => {
                std.debug.assert(false);
                return 1;
            },
            TokenKind.EOF => {
                return 0;
            },
            TokenKind.DOT,
            TokenKind.COMMA,
            TokenKind.COLON,
            TokenKind.SEMICOLON,
            TokenKind.PIPE,
            TokenKind.AMPERSAND,
            TokenKind.CARET,
            TokenKind.TILDE,
            TokenKind.PLUS,
            TokenKind.MINUS,
            TokenKind.ASTERISK,
            TokenKind.LPAREN,
            TokenKind.RPAREN,
            TokenKind.LBRACE,
            TokenKind.RBRACE,
            TokenKind.LBRACKET,
            TokenKind.RBRACKET,
            TokenKind.EXCLAMATION,
            TokenKind.QUESTION,
            TokenKind.ASSIGN,
            TokenKind.GREATER,
            TokenKind.LESS,
            TokenKind.SLASH,
            => {
                return 1;
            },
            TokenKind.IF,
            TokenKind.IN,
            TokenKind.OR,
            TokenKind.ARROW,
            TokenKind.DOUBLE_GREATER,
            TokenKind.DOUBLE_LESS,
            TokenKind.DOUBLE_PLUS,
            TokenKind.DOUBLE_DOT,
            TokenKind.DOUBLE_ASTERISK,
            TokenKind.EQUAL,
            TokenKind.NOT_EQUAL,
            TokenKind.GREATER_EQUAL,
            TokenKind.FN,
            TokenKind.LESS_EQUAL,
            => {
                return 2;
            },
            TokenKind.OWN,
            TokenKind.FOR,
            TokenKind.AND,
            TokenKind.LET,
            TokenKind.MUT,
            => {
                return 3;
            },
            TokenKind.TRUE,
            TokenKind.ENUM,
            TokenKind.ELSE,
            TokenKind.SELF,
            TokenKind.SELF_TYPE,
            => {
                return 4;
            },
            TokenKind.WHILE,
            TokenKind.FALSE,
            TokenKind.UNION,
            TokenKind.TRAIT,
            TokenKind.BREAK,
            => {
                return 5;
            },
            TokenKind.STRUCT,
            TokenKind.RETURN,
            => {
                return 6;
            },
            TokenKind.CONTINUE,
            => {
                return 8;
            },
            TokenKind.NUMBER,
            TokenKind.IDENTIFIER,
            TokenKind.STRING_LITERAL,
            => {
                return @truncate(self.str.?.len);
            },
        }
    }
};

pub const Lexer = struct {
    scanner: Scanner,
    allocator: std.mem.Allocator,
    end_of_file: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, source_file: *SourceFile) !Self {
        return Self{
            .scanner = try Scanner.init(source_file),
            .allocator = allocator,
            .end_of_file = false,
        };
    }

    fn consume_until_ascii(self: *Self) void {
        var codepoint = self.scanner.peek() orelse return;
        while (codepoint.len > 1) {
            _ = self.scanner.consume();
            errmsg.print_error(
                .Error,
                self.scanner.reader.source,
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

    fn end_token(self: *Self) ?Token {
        if (self.end_of_file) return null;
        const token = Token{
            .kind = TokenKind.EOF,
            .source = .{
                .file = self.scanner.reader.source,
                .line = self.scanner.line_num,
                .col = self.scanner.col,
            },
            .str = null,
        };
        self.end_of_file = true;
        return token;
    }

    pub fn next_token(self: *Self) !?Token {
        var first_byte = self.consume_ascii() orelse return self.end_token();
        while (std.ascii.isWhitespace(first_byte)) {
            first_byte = self.consume_ascii() orelse return self.end_token();
        }

        var token = Token{
            .kind = TokenKind.INVALID,
            .source = .{
                .file = self.scanner.reader.source,
                .line = self.scanner.line_num,
                .col = self.scanner.col,
            },
            .str = null,
        };

        var buffer = try std.ArrayList(u8).initCapacity(self.allocator, 80);
        defer buffer.deinit(self.allocator);
        try buffer.append(self.allocator, first_byte);

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
            '|' => token.kind = TokenKind.PIPE,
            '&' => token.kind = TokenKind.AMPERSAND,
            '^' => token.kind = TokenKind.CARET,
            '~' => token.kind = TokenKind.TILDE,
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
                } else if (next != null and next.? == '>') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.DOUBLE_GREATER;
                } else {
                    token.kind = TokenKind.GREATER;
                }
            },
            '<' => {
                const next = self.peek_ascii();
                if (next != null and next.? == '=') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.LESS_EQUAL;
                } else if (next != null and next.? == '<') {
                    _ = self.consume_ascii();
                    token.kind = TokenKind.DOUBLE_LESS;
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
                    try buffer.appendSlice(self.allocator, codepoint);
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
                            try buffer.append(self.allocator, self.consume_ascii().?);
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
                            try buffer.append(self.allocator, self.consume_ascii().?);
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
                        } else if (std.mem.eql(u8, buffer.items[1..], "elf")) {
                            token.kind = TokenKind.SELF;
                        }
                    },
                    'S' => {
                        if (std.mem.eql(u8, buffer.items[1..], "elf")) {
                            token.kind = TokenKind.SELF_TYPE;
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
