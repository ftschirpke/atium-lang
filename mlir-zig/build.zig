const std = @import("std");

const third_party = @import("../third-party/build.zig");

const MLIRBuildError = error{OutOfMemory};

pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
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

    lib.step.dependOn(&llvm.build_step.step);

    lib.addSystemIncludePath(try llvm.install_path.join(b.allocator, "include"));
    lib.addLibraryPath(try llvm.install_path.join(b.allocator, "lib"));
    lib.linkSystemLibrary("MLIRSupport");

    b.installArtifact(lib);
}
