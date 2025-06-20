const std = @import("std");

const CompilerBuildError = error{MissingLibrary};

pub fn build(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) CompilerBuildError!void {
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("compiler/src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("compiler/src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_mod.addImport("compiler_lib", lib_mod);

    if (b.modules.get("mlir_zig")) |mlir_zig| {
        exe_mod.addImport("mlir", mlir_zig);
    } else {
        std.log.err("Could not find mlir_zig library", .{});
        return CompilerBuildError.MissingLibrary;
    }

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "compiler",
        .root_module = lib_mod,
    });
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "compiler",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);
}
