const Self = @This();

const std = @import("std");
const os = std.os;

const wayland = @import("wayland");
const wl = wayland.client.wl;

buffer: *wl.Buffer,
width: i32,
height: i32,
data: []u8,

pub fn init(shm: *wl.Shm, width: i32, height: i32) anyerror!Self {
    const stride = width * 4;
    const size = stride * height;

    const fd = try os.memfd_create("foo", 0);
    try os.ftruncate(fd, @as(u64, @intCast(size)));
    const data = try os.mmap(
        null,
        @as(usize, @intCast(size)),
        os.PROT_READ | os.PROT_WRITE,
        os.MAP_SHARED,
        fd,
        0,
    );

    const pool = try shm.createPool(fd, @as(i32, @intCast(size)));
    const buffer = try pool.createBuffer(
        0,
        width,
        height,
        stride,
        wl.Shm.Format.argb8888,
    );

    return Self{
        .data = data,
        .buffer = buffer,
        .width = width,
        .height = height,
    };
}
