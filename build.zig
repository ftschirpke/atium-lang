// SPDX-License-Identifier: MIT
const std = @import("std");

const third_party_build = @import("third-party/build.zig");
const mlir_zig = @import("mlir-zig/build.zig");
const compiler = @import("compiler/build.zig");
const filetest = @import("tool-filetest/build.zig");

const BuildError = error{ MissingLibrary, OutOfMemory, InvalidPath };

pub fn build(b: *std.Build) BuildError!void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const llvm = try third_party_build.build_llvm(b, optimize);

    try mlir_zig.build_subproject(b, target, optimize, &llvm);
    try compiler.build_subproject(b, target, optimize);

    try filetest.build_subproject(b, target, optimize);
}
