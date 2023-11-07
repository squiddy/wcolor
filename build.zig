const std = @import("std");

const Scanner = @import("deps/zig-wayland/build.zig").Scanner;

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const scanner = Scanner.create(b, .{});

    const wayland = b.createModule(.{ .source_file = scanner.result });

    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addCustomProtocol("deps/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml");
    scanner.addCustomProtocol("deps/wlr-protocols/unstable/wlr-screencopy-unstable-v1.xml");

    scanner.generate("wl_shm", 1);
    scanner.generate("wl_compositor", 1);
    scanner.generate("wl_subcompositor", 1);
    scanner.generate("wlr_layer_shell_unstable", 1);

    const exe = b.addExecutable(.{ .name = "wcolor", .root_source_file = .{ .path = "src/main.zig" }, .target = target, .optimize = optimize });

    exe.addModule("wayland", wayland);
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");
    exe.linkSystemLibrary("cairo");

    scanner.addCSource(exe);

    b.installArtifact(exe);
}
