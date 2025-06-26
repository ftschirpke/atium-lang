// SPDX-License-Identifier: MIT
const mlir = @import("mlir");

const std = @import("std");

const lib = @import("compiler_lib");
const TokenKind = lib.lex.TokenKind;

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();

    std.debug.assert(args.skip());

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print("Result of {} + {} = {}.\n", .{ 4, 2, mlir.add(4, 2) });
    try bw.flush();

    const filepath = args.next();
    if (filepath) |path| {
        std.fs.cwd().access(path, .{}) catch |err| {
            std.log.err("Error occured when accessing the specified file '{s}': {}", .{ path, err });
        };
        const absolute_path = try std.fs.cwd().realpathAlloc(gpa, path[0..path.len]);
        try lex(gpa, stdout, absolute_path);
    }

    try bw.flush();
}

fn lex(allocator: std.mem.Allocator, writer: anytype, filepath: []const u8) !void {
    var lexer = try lib.lex.Lexer.init(allocator, filepath);
    defer lexer.deinit();

    var opt_token = try lexer.next_token();
    var line: u64 = 0;
    while (opt_token != null) {
        const token = opt_token.?;
        while (line < token.source.line) {
            try writer.print("\n{d:4} > ", .{line + 1});
            line += 1;
        }
        switch (token.kind) {
            TokenKind.IDENTIFIER, TokenKind.INVALID, TokenKind.NUMBER, TokenKind.STRING_LITERAL => {
                try writer.print("{s}(\"{s}\") ", .{ @tagName(token.kind), token.str.? });
            },
            else => {
                try writer.print("{s} ", .{@tagName(token.kind)});
            },
        }
        opt_token = try lexer.next_token();
    }
    try writer.print("\n", .{});
}
