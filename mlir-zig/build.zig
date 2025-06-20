const std = @import("std");

pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    llvm: *std.Build.Step.Run,
) void {
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

    lib.step.dependOn(&llvm.step);

    lib.addSystemIncludePath(b.path("third-party/install/llvm/include"));
    lib.addLibraryPath(b.path("third-party/install/llvm/lib"));

    lib.linkSystemLibrary("MLIRSupport");

    b.installArtifact(lib);
}
