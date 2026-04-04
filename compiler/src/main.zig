// SPDX-License-Identifier: MIT
const mlir = @import("mlir");

const std = @import("std");

const lib = @import("compiler_lib");
const TokenKind = lib.lex.TokenKind;

const Command = enum {
    LEX,
    PARSE,
};

pub fn main() void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();
    var args = std.process.argsWithAllocator(gpa) catch |err| {
        std.log.err("Unexpected problem while allocating memory for process arguments - {}", .{err});
        return;
    };
    defer args.deinit();

    std.debug.assert(args.skip());

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    stdout.print("Result of {} + {} = {}.\n", .{ 4, 2, mlir.add(4, 2) }) catch |err| {
        lib.errmsg.error_writer(err);
        return;
    };
    stdout.flush() catch |err| {
        lib.errmsg.error_writer(err);
        return;
    };

    var command: Command = undefined;
    const command_str = args.next();
    if (command_str) |cmd| {
        if (std.mem.eql(u8, cmd, "lex")) {
            command = Command.LEX;
        } else if (std.mem.eql(u8, cmd, "parse")) {
            command = Command.PARSE;
        } else {
            std.log.err("Unsupported command provided: {s}; Expected lex/parse", .{cmd});
        }
    } else {
        std.log.err("No command provided (lex/ast)", .{});
    }

    const filepath = args.next();
    if (filepath) |path| {
        std.fs.cwd().access(path, .{}) catch |err| {
            std.log.err("Error occured when accessing the specified file '{s}': {}", .{ path, err });
        };
        const absolute_path = std.fs.cwd().realpathAlloc(gpa, path[0..path.len]) catch |err| {
            std.log.err("Could not determine absolute path of provided file - {}", .{err});
            return;
        };
        switch (command) {
            Command.LEX => lex(gpa, stdout, absolute_path),
            Command.PARSE => parse(gpa, stdout, absolute_path),
        }
    }

    stdout.flush() catch |err| {
        lib.errmsg.error_writer(err);
        return;
    };
}

fn lex(allocator: std.mem.Allocator, writer: *std.Io.Writer, filepath: []const u8) void {
    var world = lib.world.World.init(allocator);
    defer world.deinit();
    const source_file = world.source_file(filepath) catch |err| {
        lib.errmsg.error_oom(err);
        return;
    };

    var lexer = lib.lex.Lexer.init(allocator, source_file) catch |err| {
        lib.errmsg.error_file_open(filepath, err);
        return;
    };

    var opt_token = lexer.next_token() catch |err| {
        std.log.err("Unexpected problem while lexing next token - {}", .{err});
        return;
    };
    var line: u32 = 0;
    while (opt_token != null) {
        const token = opt_token.?;
        while (line < token.source.line) {
            writer.print("\n{d:4} > ", .{line + 1}) catch |err| {
                lib.errmsg.error_writer(err);
                return;
            };
            line += 1;
        }
        switch (token.kind) {
            TokenKind.BASIC_TYPE,
            TokenKind.IDENTIFIER,
            TokenKind.INVALID,
            TokenKind.NUMBER,
            TokenKind.STRING_LITERAL,
            => {
                writer.print("{s}(\"{s}\") ", .{ @tagName(token.kind), token.str orelse return }) catch |err| {
                    lib.errmsg.error_writer(err);
                    return;
                };
            },
            else => {
                writer.print("{s} ", .{@tagName(token.kind)}) catch |err| {
                    lib.errmsg.error_writer(err);
                    return;
                };
            },
        }
        opt_token = lexer.next_token() catch |err| {
            std.log.err("Unexpected problem while lexing next token - {}", .{err});
            return;
        };
    }
    writer.print("\n", .{}) catch |err| {
        lib.errmsg.error_writer(err);
        return;
    };
}

fn parse(allocator: std.mem.Allocator, writer: *std.Io.Writer, filepath: []const u8) void {
    var world = lib.world.World.init(allocator);
    defer world.deinit();
    const source_file = world.source_file(filepath) catch |err| {
        lib.errmsg.error_oom(err);
        return;
    };

    var lexer = lib.lex.Lexer.init(allocator, source_file) catch |err| {
        lib.errmsg.error_file_open(filepath, err);
        return;
    };
    var parser = lib.parse.Parser.init(allocator, &lexer) catch |err| {
        lib.errmsg.error_file_open(filepath, err);
        return;
    };
    defer parser.deinit();

    parser.parse() catch |err| {
        std.log.err("Error occured while parsing: {}", .{err});
    };

    const footprint = parser.ast.item_list.memory_footprint();
    writer.print("Finished parsing and got AST with size {} vs {} naive\n", .{
        footprint.this,
        footprint.naive,
    }) catch |err| {
        lib.errmsg.error_writer(err);
        return;
    };
}
