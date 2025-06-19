const std = @import("std");

const third_party_build = @import("third-party/build.zig");
const mlir_zig = @import("mlir-zig/build.zig");

const BuildError = error{OutOfMemory};

pub fn build(b: *std.Build) BuildError!void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const llvm = try third_party_build.build_llvm(b, optimize);

    mlir_zig.build(b, target, optimize, llvm);
}
