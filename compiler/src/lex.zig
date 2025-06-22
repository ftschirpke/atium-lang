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
const TOKEN_BUFFER_LENGTH = 1024;

const TokenCreationError = error{ ConstantTooLong, IdentifierTooLong };

const Lexer = struct {
    scanner: Scanner,
    path: *[]const u8,
    line: u64,
    col: u64,

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
                return WHITESPACE;
            },
            ' ' | '\t' => return WHITESPACE,
            else => return byte,
        }
    }

    fn peek_byte(self: *Self) ?u8 {
        return self.scanner.peek();
    }

    fn next_token(self: *Self) TokenCreationError!?Token {
        var first_byte = self.consume_byte() orelse return null;
        while (first_byte == WHITESPACE) {
            first_byte = self.consume_byte() orelse return null;
        }

        var token = Token{
            .kind = undefined,
            .str = null,
            .source = .{
                .path = self.path,
                .line = self.line,
                .col = self.col,
            },
        };

        var buffer: [TOKEN_BUFFER_LENGTH]u8 = &.{first_byte} ++ &.{0} ** (TOKEN_BUFFER_LENGTH - 1);

        switch (first_byte) {
            '(' => token.kind = TokenKind.LPAREN,
            ')' => token.kind = TokenKind.RPAREN,
            '{' => token.kind = TokenKind.LBRACE,
            '}' => token.kind = TokenKind.RBRACE,
            '[' => token.kind = TokenKind.LBRACKET,
            ']' => token.kind = TokenKind.RBRACKET,
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
                // TODO: create token for number
            },
        }
    }
};
