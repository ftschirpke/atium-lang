// SPDX-License-Identifier: MIT
const std = @import("std");
const testing = std.testing;

const c = @cImport({
    @cInclude("mlir-c/Support.h");
});

pub export fn add(a: i32, b: i32) i32 {
    const res = c.mlirLogicalResultSuccess(); // just some simple call to test the linkage
    return a + b + res.value;
}

test "basic add functionality" {
    try testing.expect(add(3, 7) == 11);
}
