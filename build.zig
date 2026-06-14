const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("zighook", .{
        .root_source_file = b.path("src/zighook.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/zighook.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const integ_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("test/hook_test.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zighook", .module = mod }},
        }),
    });

    const test_step = b.step("test", "Run all tests");
    test_step.dependOn(&b.addRunArtifact(lib_tests).step);
    test_step.dependOn(&b.addRunArtifact(integ_tests).step);

    const examples = [_][]const u8{ "basic_inline", "vtable_swap", "transaction_batch" };
    const examples_step = b.step("examples", "Build the examples");
    for (examples) |name| {
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "zighook", .module = mod }},
            }),
        });
        examples_step.dependOn(&b.addInstallArtifact(exe, .{}).step);
    }
}
