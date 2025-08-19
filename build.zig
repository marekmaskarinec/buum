const std = @import("std");

const umka_c_sources = [_][]const u8{
    "umka-lang/src/umka_api.c",
    "umka-lang/src/umka_common.c",
    "umka-lang/src/umka_compiler.c",
    "umka-lang/src/umka_const.c",
    "umka-lang/src/umka_decl.c",
    "umka-lang/src/umka_expr.c",
    "umka-lang/src/umka_gen.c",
    "umka-lang/src/umka_ident.c",
    "umka-lang/src/umka_lexer.c",
    "umka-lang/src/umka_runtime.c",
    "umka-lang/src/umka_stmt.c",
    "umka-lang/src/umka_types.c",
    "umka-lang/src/umka_vm.c",
};

const umka_c_flags = [_][]const u8{
    "-Wall",
    "-fPIC",
    "-Wno-format-security",
    "-malign-double",
    "-fno-strict-aliasing",
    "-DUMKA_EXT_LIBS",
    "-fno-sanitize=all",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const umka_lib = b.addStaticLibrary(.{
        .name = "umka",
        .target = target,
        .optimize = optimize,
    });
    umka_lib.linkLibC();
    umka_lib.addCSourceFiles(.{
        .files = &umka_c_sources,
        .flags = &umka_c_flags,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const umka_dependency = b.dependency("umka", .{});
    exe_mod.addImport("umka", umka_dependency.module("wrapper"));

    const exe = b.addExecutable(.{
        .name = "bu_gen",
        .root_module = exe_mod,
    });
    exe.linkLibrary(umka_lib);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
