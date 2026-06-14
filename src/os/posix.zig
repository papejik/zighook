const std = @import("std");
const builtin = @import("builtin");
const Error = @import("../errors.zig").Error;
const page = @import("page.zig");

pub const Token = void;

pub fn allocExecNear(near: usize, size: usize) Error![]align(std.heap.page_size_min) u8 {
    const gran = std.heap.pageSize();
    const anchor = std.mem.alignBackward(usize, near, gran);

    var step: usize = 0;
    while (step <= page.near_range) : (step += gran) {
        if (tryMap(anchor -% step, near, size)) |m| return m;
        if (step != 0) {
            if (tryMap(anchor +% step, near, size)) |m| return m;
        }
    }
    return Error.OutOfExecutableMemory;
}

fn tryMap(addr: usize, near: usize, size: usize) ?[]align(std.heap.page_size_min) u8 {
    if (addr == 0 or distance(addr, near) > page.near_range) return null;

    const prot: std.posix.PROT = .{ .READ = true, .WRITE = true, .EXEC = true };
    const flags: std.posix.MAP = .{ .TYPE = .PRIVATE, .ANONYMOUS = true };
    const hint: [*]align(std.heap.page_size_min) u8 = @ptrFromInt(addr);
    const m = std.posix.mmap(hint, size, prot, flags, -1, 0) catch return null;

    if (distance(@intFromPtr(m.ptr), near) <= page.near_range) return m;
    std.posix.munmap(m);
    return null;
}

pub fn makeWritable(addr: usize, len: usize, prot: page.Prot) Error!Token {
    const r = page.cover(addr, len);
    return setProt(r.base, r.len, true, prot == .code);
}

pub fn restoreProtect(addr: usize, len: usize, token: Token, prot: page.Prot) Error!void {
    _ = token;
    const r = page.cover(addr, len);
    return setProt(r.base, r.len, prot == .data, prot == .code);
}

pub fn flushICache(addr: usize, len: usize) void {
    _ = addr;
    _ = len;
}

fn distance(a: usize, b: usize) usize {
    return if (a > b) a - b else b - a;
}

fn setProt(base: usize, len: usize, write: bool, exec: bool) Error!void {
    switch (builtin.os.tag) {
        .linux => {
            const prot: std.os.linux.PROT = .{ .READ = true, .WRITE = write, .EXEC = exec };
            if (std.os.linux.E.init(std.os.linux.mprotect(@ptrFromInt(base), len, prot)) != .SUCCESS) {
                return Error.ProtectFailed;
            }
        },
        else => {
            const prot: std.c.PROT = .{ .READ = true, .WRITE = write, .EXEC = exec };
            const ptr: *anyopaque = @ptrFromInt(base);
            if (std.c.mprotect(@alignCast(ptr), len, prot) != 0) return Error.ProtectFailed;
        },
    }
}
