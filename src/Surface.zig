const Self = @This();

const std = @import("std");
const os = std.os;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const wlr = wayland.client.zwlr;

const c = @cImport({
    @cInclude("cairo/cairo.h");
});

const Context = @import("main.zig").Context;
const Buffer = @import("Buffer.zig");

const indicatorSize = 100;

const Color = struct {
    r: u8,
    g: u8,
    b: u8,

    pub fn floatRed(self: Color) f16 {
        return @as(f16, @floatFromInt(self.r)) / 255.0;
    }

    pub fn floatGreen(self: Color) f16 {
        return @as(f16, @floatFromInt(self.g)) / 255.0;
    }

    pub fn floatBlue(self: Color) f16 {
        return @as(f16, @floatFromInt(self.b)) / 255.0;
    }
};

output: *wl.Output,
context: *Context,
surface: ?*wl.Surface,
subsurface: ?*wl.Subsurface,
preview_surface: ?*wl.Surface,
layer_surface: ?*wlr.LayerSurfaceV1,
buffer: ?Buffer,
preview_buffer: ?Buffer,
width: u32,
height: u32,
color: Color,

pub fn init(context: *Context, output: *wl.Output) Self {
    return Self{
        .context = context,
        .output = output,
        .surface = null,
        .subsurface = null,
        .layer_surface = null,
        .preview_surface = null,
        .preview_buffer = null,
        .buffer = null,
        .width = 0,
        .height = 0,
        .color = Color{ .r = 255, .g = 255, .b = 255 },
    };
}

pub fn setup(self: *Self) anyerror!void {
    self.output.setListener(*Self, outputListener, self);
}

pub fn createSurface(self: *Self, width: i32, height: i32) anyerror!void {
    self.width = @as(u32, @intCast(width));
    self.height = @as(u32, @intCast(height));

    const layer_shell = self.context.layer_shell orelse return error.NoWlrLayerShell;
    const compositor = self.context.compositor orelse return error.NoWlCompositor;
    const subcompositor = self.context.subcompositor orelse return error.NoWlSubcompositor;
    const shm = self.context.shm orelse return error.NoWlShm;

    const surface = try compositor.createSurface();

    const preview_surface = try compositor.createSurface();
    const region = try compositor.createRegion();
    region.add(0, 0, 0, 0);
    preview_surface.setInputRegion(region);

    const subsurface = try subcompositor.getSubsurface(preview_surface, surface);
    subsurface.setPosition(-500, -500);
    subsurface.setDesync();

    const layer_surface = try layer_shell.getLayerSurface(
        surface,
        self.output,
        wlr.LayerShellV1.Layer.overlay,
        "overlay",
    );
    layer_surface.setSize(0, 0);
    layer_surface.setAnchor(.{ .top = true, .bottom = true, .right = true, .left = true });
    layer_surface.setExclusiveZone(-1);
    layer_surface.setListener(*Self, layerSurfaceListener, self);
    surface.commit();

    self.buffer = try Buffer.init(shm, width, height);
    self.preview_buffer = try Buffer.init(shm, indicatorSize, indicatorSize);
    preview_surface.attach(self.preview_buffer.?.buffer, 0, 0);
    preview_surface.commit();

    self.preview_surface = preview_surface;
    self.surface = surface;
    self.subsurface = subsurface;
}

fn show(self: *Self) anyerror!void {
    const frame = try self.context.screencopy.?.captureOutput(0, self.output);
    frame.setListener(*Self, frameListener, self);
}

pub fn handlePointerLeft(self: *Self) void {
    self.subsurface.?.setPosition(-500, -500);
    self.preview_surface.?.commit();
    self.surface.?.commit();
}

pub fn handlePointerMotion(self: *Self, x: i24, y: i24) void {
    const image = self.buffer.?.data;
    const cx = @as(u32, @intCast(x));
    const cy = @as(u32, @intCast(y));

    const offset = (self.height - cy - 1) * self.width * 4 + cx * 4;
    self.color = Color{ .r = image[offset + 2], .g = image[offset + 1], .b = image[offset] };

    {
        const cairo_surface = c.cairo_image_surface_create_for_data(
            @as([*c]u8, @ptrCast(self.preview_buffer.?.data)),
            c.cairo_format_t.CAIRO_FORMAT_ARGB32,
            indicatorSize,
            indicatorSize,
            indicatorSize * 4,
        );

        const cairo = c.cairo_create(cairo_surface);
        c.cairo_set_antialias(cairo, c.cairo_antialias_t.CAIRO_ANTIALIAS_BEST);
        c.cairo_set_operator(cairo, c.cairo_operator_t.CAIRO_OPERATOR_CLEAR);
        c.cairo_paint(cairo);

        // White outline
        c.cairo_set_operator(cairo, c.cairo_operator_t.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgb(cairo, 1.0, 1.0, 1.0);
        c.cairo_set_line_width(cairo, 25);
        c.cairo_arc(cairo, 50, 50, 30, 0, 2 * std.math.pi);
        c.cairo_stroke_preserve(cairo);

        // Black outline
        c.cairo_set_operator(cairo, c.cairo_operator_t.CAIRO_OPERATOR_SOURCE);
        c.cairo_set_source_rgb(cairo, 0.0, 0.0, 0.0);
        c.cairo_set_line_width(cairo, 22);
        c.cairo_arc(cairo, 50, 50, 30, 0, 2 * std.math.pi);
        c.cairo_stroke_preserve(cairo);

        // Circle filled with current color
        c.cairo_set_source_rgb(
            cairo,
            self.color.floatRed(),
            self.color.floatGreen(),
            self.color.floatBlue(),
        );
        c.cairo_set_line_width(cairo, 20);
        c.cairo_arc(cairo, 50, 50, 30, 0, 2 * std.math.pi);
        c.cairo_stroke_preserve(cairo);

        c.cairo_destroy(cairo);

        self.preview_surface.?.attach(self.preview_buffer.?.buffer, 0, 0);
        self.preview_surface.?.damageBuffer(0, 0, indicatorSize, indicatorSize);
    }

    self.subsurface.?.setPosition(x - indicatorSize / 2, y - indicatorSize / 2);
    self.preview_surface.?.commit();
    self.surface.?.commit();
}

fn frameListener(frame: *wlr.ScreencopyFrameV1, event: wlr.ScreencopyFrameV1.Event, self: *Self) void {
    switch (event) {
        .buffer => |data| {
            _ = data;
            frame.copy(self.buffer.?.buffer);
        },
        .ready => {
            self.surface.?.attach(self.buffer.?.buffer, 0, 0);
            self.surface.?.commit();
            frame.destroy();
        },
        .flags => |flags| {
            if (flags.flags.y_invert) {
                self.surface.?.setBufferTransform(wl.Output.Transform.flipped_180);
            }
        },
        .failed => {},
        .damage => {},
        .linux_dmabuf => {},
        .buffer_done => {},
    }
}

fn layerSurfaceListener(layer_surface: *wlr.LayerSurfaceV1, event: wlr.LayerSurfaceV1.Event, self: *Self) void {
    switch (event) {
        .configure => |configure| {
            layer_surface.ackConfigure(configure.serial);
            self.show() catch @panic("Couldn't show.");
        },
        .closed => {},
    }
}

fn outputListener(output: *wl.Output, event: wl.Output.Event, self: *Self) void {
    _ = output;
    switch (event) {
        .geometry => |geometry| {
            _ = geometry;
        },
        .mode => |mode| {
            self.createSurface(mode.width, mode.height) catch @panic("Couldn't create surface.");
        },
        .scale => |scale| {
            _ = scale;
        },
        .done => |done| {
            _ = done;
        },
    }
}
