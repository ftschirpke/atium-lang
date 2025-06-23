// SPDX-License-Identifier: MIT
const std = @import("std");

const READER_BUFFER_SIZE = 4096;
const BufferedReader = std.io.BufferedReader(READER_BUFFER_SIZE, std.io.Reader);

const Scanner = struct {
    file: std.fs.File,
    _buffered_reader: BufferedReader,
    reader: BufferedReader.Reader,
    cur: ?u8,

    const Self = @This();

    fn init(path: *[]const u8) std.fs.File.OpenError!Self {
        const file = try std.fs.openFileAbsolute(path);
        const buffered_reader = std.io.bufferedReader(READER_BUFFER_SIZE, file.reader());
        return Self{
            .file = file,
            ._buffered_reader = buffered_reader,
            .reader = buffered_reader.reader(),
            .cur = null,
        };
    }

    fn deinit(self: Self) void {
        self.file.close();
    }

    fn consume(self: *Self) ?u8 {
        if (self.cur == null) {
            self.cur = self.reader.readByte() orelse return null;
        }
        const out = self.cur.?;
        self.cur = self.reader.readByte() orelse return null;
        return out;
    }

    fn peek(self: *Self) ?u8 {
        if (self.cur == null) {
            self.cur = self.reader.readByte() orelse return null;
        }
        return self.cur;
    }
};

const TokenKind = enum {
    INVALID,

    DOT,
    COLON,

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

    STRUCT,
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
};

const SourceInfo = struct {
    path: *[]const u8,
    line: u64,
    col: u64,
};

const Token = struct {
    kind: TokenKind,
    str: ?[]const u8,
    source: SourceInfo,
};

const WHITESPACE = ' ';
const NEWLINE = '\n';
const TOKEN_BUFFER_LENGTH = 1024;

const TokenCreationError = error{ ConstantTooLong, IdentifierTooLong };

const Lexer = struct {
    scanner: Scanner,
    path: *[]const u8,
    line: u64,
    col: u64,
    allocator: std.mem.Allocator,

    const Self = @This();

    fn init(path: *[]const u8) std.fs.File.OpenError!Self {
        return Self{
            .scanner = try Scanner.init(path),
            .path = path,
            .line = 1,
            .col = 0,
        };
    }

    fn deinit(self: Self) void {
        self.scanner.deinit();
    }

    fn consume_byte(self: *Self) ?u8 {
        const byte = self.scanner.consume() orelse return null;
        self.col += 1;
        switch (byte) {
            '\n' => {
                self.line += 1;
                self.col = 0;
                return NEWLINE;
            },
            ' ', '\t' => return WHITESPACE,
            else => return byte,
        }
    }

    fn peek_byte(self: *Self) ?u8 {
        return self.scanner.peek();
    }

    fn next_token(self: *Self) TokenCreationError!?Token {
        var first_byte = self.consume_byte() orelse return null;
        while (first_byte == WHITESPACE or first_byte == NEWLINE) {
            first_byte = self.consume_byte() orelse return null;
        }

        var token = Token{
            .kind = TokenKind.INVALID,
            .str = null,
            .source = .{
                .path = self.path,
                .line = self.line,
                .col = self.col,
            },
        };

        var buffer: [TOKEN_BUFFER_LENGTH]u8 = &.{first_byte} ++ &.{0} ** (TOKEN_BUFFER_LENGTH - 1);

        switch (first_byte) {
            '.' => token.kind = TokenKind.DOT,
            ':' => token.kind = TokenKind.COLON,
            '(' => token.kind = TokenKind.LPAREN,
            ')' => token.kind = TokenKind.RPAREN,
            '{' => token.kind = TokenKind.LBRACE,
            '}' => token.kind = TokenKind.RBRACE,
            '[' => token.kind = TokenKind.LBRACKET,
            ']' => token.kind = TokenKind.RBRACKET,
            '+' => token.kind = TokenKind.PLUS,
            '-' => token.kind = TokenKind.MINUS,
            '*' => token.kind = TokenKind.ASTERISK,
            '/' => token.kind = TokenKind.SLASH,
            '?' => token.kind = TokenKind.QUESTION,
            '!' => {
                if (self.peek_byte() != null and self.peek_byte().? == '=') {
                    self.consume_byte();
                    token.kind = TokenKind.NOT_EQUAL;
                } else {
                    token.kind = TokenKind.EXCLAMATION;
                }
            },
            '=' => {
                if (self.peek_byte() != null and self.peek_byte().? == '=') {
                    self.consume_byte();
                    token.kind = TokenKind.EQUAL;
                } else {
                    token.kind = TokenKind.ASSIGN;
                }
            },
            '>' => {
                if (self.peek_byte() != null and self.peek_byte().? == '=') {
                    self.consume_byte();
                    token.kind = TokenKind.GREATER_EQUAL;
                } else {
                    token.kind = TokenKind.GREATER;
                }
            },
            '<' => {
                if (self.peek_byte() != null and self.peek_byte().? == '=') {
                    self.consume_byte();
                    token.kind = TokenKind.LESS_EQUAL;
                } else {
                    token.kind = TokenKind.LESS;
                }
            },
            '0'...'9' => {
                token.kind = TokenKind.NUMBER;
                var len = 1;
                while (self.peek_byte()) |byte| {
                    switch (byte) {
                        '0'...'9' => {
                            if (len >= TOKEN_BUFFER_LENGTH) {
                                // TODO: standardize errors and error messages
                                std.log.err(
                                    "Number '{s}' is too long and continues after {} digits",
                                    buffer,
                                    TOKEN_BUFFER_LENGTH,
                                );
                                return TokenCreationError.ConstantTooLong;
                            }
                            buffer[len] = byte;
                            len += 1;
                        },
                        else => break,
                    }
                }
                token.str = try self.allocator.dupe(u8, buffer[0..len]);
            },
            'a'...'z', 'A'...'Z', '_' => {
                var len = 1;
                while (self.peek_byte()) |byte| {
                    switch (byte) {
                        'a'...'z', 'A'...'Z', '_', '0'...'9' => {
                            if (len >= TOKEN_BUFFER_LENGTH) {
                                // TODO: standardize errors and error messages
                                std.log.err(
                                    "Identifier '{s}' is too long and continues after {} characters",
                                    buffer,
                                    TOKEN_BUFFER_LENGTH,
                                );
                                return TokenCreationError.ConstantTooLong;
                            }
                            buffer[len] = self.consume_byte.?;
                            len += 1;
                        },
                        else => break,
                    }
                }

                switch (first_byte) {
                    'a' => {
                        if (std.mem.eql(u8, buffer[1..len], "nd")) {
                            token.kind = TokenKind.AND;
                        }
                    },
                    'b' => {
                        if (std.mem.eql(u8, buffer[1..len], "reak")) {
                            token.kind = TokenKind.BREAK;
                        }
                    },
                    'c' => {
                        if (std.mem.eql(u8, buffer[1..len], "ontinue")) {
                            token.kind = TokenKind.CONTINUE;
                        }
                    },
                    'e' => {
                        if (std.mem.eql(u8, buffer[1..len], "lse")) {
                            token.kind = TokenKind.ELSE;
                        }
                    },
                    'f' => {
                        if (std.mem.eql(u8, buffer[1..len], "n")) {
                            token.kind = TokenKind.FN;
                        } else if (std.mem.eql(u8, buffer[1..len], "or")) {
                            token.kind = TokenKind.FOR;
                        }
                    },
                    'i' => {
                        if (std.mem.eql(u8, buffer[1..len], "f")) {
                            token.kind = TokenKind.IF;
                        } else if (std.mem.eql(u8, buffer[1..len], "n")) {
                            token.kind = TokenKind.IN;
                        }
                    },
                    'o' => {
                        if (std.mem.eql(u8, buffer[1..len], "r")) {
                            token.kind = TokenKind.OR;
                        } else if (std.mem.eql(u8, buffer[1..len], "wn")) {
                            token.kind = TokenKind.OWN;
                        }
                    },
                    'r' => {
                        if (std.mem.eql(u8, buffer[1..len], "eturn")) {
                            token.kind = TokenKind.RETURN;
                        }
                    },
                    's' => {
                        if (std.mem.eql(u8, buffer[1..len], "truct")) {
                            token.kind = TokenKind.STRUCT;
                        }
                    },
                    'w' => {
                        if (std.mem.eql(u8, buffer[1..len], "hile")) {
                            token.kind = TokenKind.WHILE;
                        }
                    },
                }

                if (token.kind == TokenKind.INVALID) {
                    token.kind = TokenKind.IDENTIFIER;
                    token.str = self.allocator.dupe(u8, buffer[0..len]);
                }
            },
        }
    }
};
