// SPDX-License-Identifier: MIT
// const mlir = @import("mlir");
const std = @import("std");

const lib = @import("compiler_lib");

pub fn main() !void {
    var general_purpose_allocator: std.heap.GeneralPurposeAllocator(.{}) = .init;
    const gpa = general_purpose_allocator.allocator();
    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();

    std.debug.assert(args.skip());

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    const filepath = args.next();
    if (filepath) |path| {
        std.fs.cwd().access(path, .{}) catch |err| {
            std.log.err("Error occured when accessing the specified file '{s}': {}", .{ path, err });
        };
    }

    // try stdout.print("Result of {} + {} = {}.\n", .{ 4, 2, mlir.add(4, 2) });

    try bw.flush();
}

fn lex(filepath: *[:0]const u8) !void {
    // TODO: implement
}
