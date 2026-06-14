const std = @import("std");
const memory = @import("os/memory.zig");
const Error = @import("errors.zig").Error;

pub const slot_size = 128;

const Node = struct { next: ?*Node };

var lock: std.atomic.Mutex = .unlocked;
var free_list: ?*Node = null;

pub fn acquire(near: usize) Error![]u8 {
    while (!lock.tryLock()) std.atomic.spinLoopHint();
    defer lock.unlock();

    if (takeInRange(near)) |slot| return slot;
    try refill(near);
    return takeInRange(near) orelse Error.OutOfExecutableMemory;
}

pub fn release(slot: []u8) void {
    while (!lock.tryLock()) std.atomic.spinLoopHint();
    defer lock.unlock();

    const node: *Node = @ptrCast(@alignCast(slot.ptr));
    node.next = free_list;
    free_list = node;
}

fn takeInRange(near: usize) ?[]u8 {
    var prev: ?*Node = null;
    var node = free_list;
    while (node) |cur| : ({
        prev = cur;
        node = cur.next;
    }) {
        if (!inRange(@intFromPtr(cur), near)) continue;
        if (prev) |p| p.next = cur.next else free_list = cur.next;
        const ptr: [*]u8 = @ptrCast(cur);
        return ptr[0..slot_size];
    }
    return null;
}

fn refill(near: usize) Error!void {
    const block_size = std.mem.alignForward(usize, slot_size * 16, std.heap.pageSize());
    const block = try memory.allocExecNear(near, block_size);
    var off: usize = 0;
    while (off + slot_size <= block.len) : (off += slot_size) {
        const node: *Node = @ptrCast(@alignCast(block.ptr + off));
        node.next = free_list;
        free_list = node;
    }
}

fn inRange(addr: usize, near: usize) bool {
    const diff = if (addr > near) addr - near else near - addr;
    return diff <= memory.near_range;
}

test "acquire returns distinct slots near an anchor" {
    const near = @intFromPtr(&acquire);
    const a = try acquire(near);
    const b = try acquire(near);
    defer release(a);
    defer release(b);
    try std.testing.expect(a.ptr != b.ptr);
    try std.testing.expectEqual(@as(usize, slot_size), a.len);
    try std.testing.expect(inRange(@intFromPtr(a.ptr), near));
}
