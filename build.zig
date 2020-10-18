const std = @import("std");
const Builder = std.build.Builder;
const Step = std.build.Step;

pub fn build(b: *Builder) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.
    const target = b.standardTargetOptions(.{});

    // Standard release options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall.
    const mode = b.standardReleaseOptions();

    const scan_protocols = ScanProtocolsStep.create(b);

    const exe = b.addExecutable("wcolor", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);
    exe.addPackagePath("wayland", "deps/zig-wayland/wayland.zig");
    exe.linkSystemLibrary("wayland-client");
    exe.linkSystemLibrary("cairo");
    exe.step.dependOn(&scan_protocols.step);
    exe.addCSourceFile("generated/wlr_layer_shell.c", &[_][]const u8{"-std=c99"});
    exe.addCSourceFile("generated/wlr_screencopy.c", &[_][]const u8{"-std=c99"});
    exe.addCSourceFile("generated/xdg_shell.c", &[_][]const u8{"-std=c99"});
    exe.linkLibC();

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}

const ScanProtocolsStep = struct {
    builder: *Builder,
    step: Step,

    fn create(builder: *Builder) *ScanProtocolsStep {
        const self = builder.allocator.create(ScanProtocolsStep) catch @panic("out of memory");
        self.* = init(builder);
        return self;
    }

    fn init(builder: *Builder) ScanProtocolsStep {
        return ScanProtocolsStep{
            .builder = builder,
            .step = Step.init(.Custom, "Scan Protocols", builder.allocator, make),
        };
    }

    fn make(step: *Step) !void {
        const self = @fieldParentPtr(ScanProtocolsStep, "step", step);

        const protocol_dir = std.fmt.trim(try self.builder.exec(
            &[_][]const u8{ "pkg-config", "--variable=pkgdatadir", "wayland-protocols" },
        ));
        const xml_path = try std.fs.path.join(self.builder.allocator, &[_][]const u8{ protocol_dir, "stable/xdg-shell/xdg-shell.xml" });
        _ = try self.builder.exec(
            &[_][]const u8{ "wayland-scanner", "private-code", xml_path, "generated/xdg_shell.c" },
        );

        _ = try self.builder.exec(
            &[_][]const u8{ "wayland-scanner", "private-code", "deps/wlr-protocols/unstable/wlr-layer-shell-unstable-v1.xml", "generated/wlr_layer_shell.c" },
        );

        _ = try self.builder.exec(
            &[_][]const u8{ "wayland-scanner", "private-code", "deps/wlr-protocols/unstable/wlr-screencopy-unstable-v1.xml", "generated/wlr_screencopy.c" },
        );
    }
};
