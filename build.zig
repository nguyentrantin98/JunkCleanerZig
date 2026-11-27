const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_arch = .x86_64, .os_tag = .windows } });
    const optimize = b.standardOptimizeOption(.{ .preferred_optimize_mode = .small });
    const mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = optimize != .debug,
    });
    for ([_][]const u8{ "user32", "gdi32", "comctl32", "shell32", "advapi32", "ole32", "gdiplus", "uxtheme", "dwmapi" }) |lib|
        mod.linkSystemLibrary(lib, .{});
    const exe = b.addExecutable(.{
        .name = "JunkCleaner",
        .root_module = mod,
        .win32_manifest = b.path("app.manifest"),
    });
    exe.subsystem = .windows;
    b.installArtifact(exe);
}
