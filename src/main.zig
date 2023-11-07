const std = @import("std");
const os = std.os;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;
const wlr = wayland.client.zwlr;

const Surface = @import("Surface.zig");

pub const Context = struct {
    running: bool,
    shm: ?*wl.Shm,
    compositor: ?*wl.Compositor,
    subcompositor: ?*wl.Subcompositor,
    layer_shell: ?*wlr.LayerShellV1,
    screencopy: ?*wlr.ScreencopyManagerV1,
    surfaces: std.ArrayList(Surface),
    active_surface: ?*Surface,
};

pub fn main() !void {
    const display = try wl.Display.connect(null);
    const registry = try display.getRegistry();

    var context = Context{
        .running = true,
        .shm = null,
        .compositor = null,
        .layer_shell = null,
        .subcompositor = null,
        .screencopy = null,
        .surfaces = std.ArrayList(Surface).init(std.heap.c_allocator),
        .active_surface = null,
    };

    registry.setListener(*Context, registryListener, &context);
    _ = try display.roundtrip();

    for (context.surfaces.items) |*surface| {
        try surface.setup();
    }

    _ = try display.roundtrip();

    while (context.running) {
        _ = try display.dispatch();
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, context: *Context) void {
    switch (event) {
        .global => |global| {
            if (std.cstr.cmp(global.interface, wl.Compositor.getInterface().name) == 0) {
                context.compositor = registry.bind(global.name, wl.Compositor, 4) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Subcompositor.getInterface().name) == 0) {
                context.subcompositor = registry.bind(global.name, wl.Subcompositor, 1) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Shm.getInterface().name) == 0) {
                context.shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (std.cstr.cmp(global.interface, wlr.LayerShellV1.getInterface().name) == 0) {
                context.layer_shell = registry.bind(global.name, wlr.LayerShellV1, 2) catch return;
            } else if (std.cstr.cmp(global.interface, wlr.ScreencopyManagerV1.getInterface().name) == 0) {
                context.screencopy = registry.bind(global.name, wlr.ScreencopyManagerV1, 1) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Output.getInterface().name) == 0) {
                const output = registry.bind(global.name, wl.Output, 3) catch return;
                context.surfaces.append(Surface.init(context, output)) catch return;
            } else if (std.cstr.cmp(global.interface, wl.Seat.getInterface().name) == 0) {
                const seat = registry.bind(global.name, wl.Seat, 1) catch return;
                seat.setListener(*Context, seatListener, context);
            }
        },
        // TODO Check for removed output / seat
        .global_remove => {},
    }
}

fn seatListener(seat: *wl.Seat, event: wl.Seat.Event, context: *Context) void {
    switch (event) {
        .capabilities => |data| {
            _ = data;
            const pointer = seat.getPointer() catch return;
            pointer.setListener(*Context, pointerListener, context);
        },
        .name => {},
    }
}

fn pointerListener(pointer: *wl.Pointer, event: wl.Pointer.Event, context: *Context) void {
    switch (event) {
        .enter => |data| {
            pointer.setCursor(data.serial, null, 0, 0);
            for (context.surfaces.items) |*surface| {
                if (surface.surface == data.surface) {
                    surface.handlePointerMotion(data.surface_x.toInt(), data.surface_y.toInt());
                    context.active_surface = surface;
                }
            }
        },
        .leave => {
            if (context.active_surface) |surface| {
                surface.handlePointerLeft();
            }
            context.active_surface = null;
        },
        .motion => |data| {
            if (context.active_surface) |surface| {
                surface.handlePointerMotion(data.surface_x.toInt(), data.surface_y.toInt());
            }
        },
        .button => {
            context.running = false;
            if (context.active_surface) |surface| {
                std.debug.print("0x{X:0>2}{X:0>2}{X:0>2}\n", .{ surface.color.r, surface.color.g, surface.color.b });
            }
        },
        .axis => {},
        .frame => {},
        .axis_source => {},
        .axis_stop => {},
        .axis_discrete => {},
    }
}
