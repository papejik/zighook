const std = @import("std");

pub const near_range: usize = 0x7FFF_0000;

pub const Prot = enum { code, data };

pub const Span = struct { base: usize, len: usize };

pub fn cover(addr: usize, len: usize) Span {
    const ps = std.heap.pageSize();
    const base = std.mem.alignBackward(usize, addr, ps);
    const end = std.mem.alignForward(usize, addr + len, ps);
    return .{ .base = base, .len = end - base };
}
