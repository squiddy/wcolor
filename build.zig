const std = @import("std");
const Builder = std.build.Builder;
const Step = std.build.Step;
const RunStep = std.build.RunStep;

const ScanProtocolsStep = @import("deps/zig-wayland/build.zig").ScanProtocolsStep;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const scanner = ScanProtocolsStep.create(b);
    scanner.addSystemProtocol("stable/xdg-shell/xdg-shell.xml");
    scanner.addProtocolPath("deps/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml");
    scanner.addProtocolPath("deps/wlr-protocols/unstable/wlr-screencopy-unstable-v1.xml");

    const exe = b.addExecutable("wcolor", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.step.dependOn(&scanner.step);
    exe.addPackage(scanner.getPkg());
    exe.linkSystemLibrary("cairo");
    exe.linkLibC();
    exe.linkSystemLibrary("wayland-client");

    scanner.addCSource(exe);

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
