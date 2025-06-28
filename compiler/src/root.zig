// SPDX-License-Identifier: MIT
const std = @import("std");
const testing = std.testing;

pub const lex = @import("lex.zig");

pub export fn sub(a: i32, b: i32) i32 {
    return a - b;
}

test "basic add functionality" {
    try testing.expect(sub(3, 7) == -4);
}
