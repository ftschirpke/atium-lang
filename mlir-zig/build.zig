// SPDX-License-Identifier: MIT
const std = @import("std");

const MLIRBuildError = error{OutOfMemory};

pub fn build_subproject(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    third_party: type,
    llvm: *const third_party.LLVMBuild,
) MLIRBuildError!void {
    const lib_mod = b.addModule("mlir_zig", .{
        .root_source_file = b.path("mlir-zig/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "mlir_zig",
        .root_module = lib_mod,
    });

    const include_path = llvm.install_path.path(b, "include");
    const lib_path = llvm.install_path.path(b, "lib");

    lib.root_module.addIncludePath(include_path);

    lib.root_module.addObjectFile(lib_path.path(b, "libMLIRSupport.a"));

    b.installArtifact(lib);
}
