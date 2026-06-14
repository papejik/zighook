const std = @import("std");

pub const near_jmp_len = 5;
pub const far_jmp_len = 14;

const min_i32: i64 = std.math.minInt(i32);
const max_i32: i64 = std.math.maxInt(i32);

fn rel32(from: usize, to: usize) i64 {
    return @as(i64, @intCast(to)) - @as(i64, @intCast(from)) - near_jmp_len;
}

fn fits(rel: i64) bool {
    return rel >= min_i32 and rel <= max_i32;
}

pub fn jmpLen(from: usize, to: usize) u8 {
    return if (fits(rel32(from, to))) near_jmp_len else far_jmp_len;
}

pub fn writeJmp(buf: []u8, from: usize, to: usize) u8 {
    const rel = rel32(from, to);
    if (fits(rel)) {
        buf[0] = 0xE9;
        std.mem.writeInt(i32, buf[1..][0..4], @intCast(rel), .little);
        return near_jmp_len;
    }
    buf[0] = 0xFF;
    buf[1] = 0x25;
    std.mem.writeInt(u32, buf[2..][0..4], 0, .little);
    std.mem.writeInt(u64, buf[6..][0..8], to, .little);
    return far_jmp_len;
}

test "near jump is rel32" {
    var buf: [16]u8 = undefined;
    try std.testing.expectEqual(@as(u8, 5), writeJmp(&buf, 0x1000, 0x1100));
    try std.testing.expectEqual(@as(u8, 0xE9), buf[0]);
    try std.testing.expectEqual(@as(i32, 0x100 - 5), std.mem.readInt(i32, buf[1..5], .little));
}

test "far jump is abs64" {
    var buf: [16]u8 = undefined;
    const to: usize = 0x7FFF_0000_0000;
    try std.testing.expectEqual(@as(u8, 14), writeJmp(&buf, 0x1000, to));
    try std.testing.expectEqual(@as(u8, 0xFF), buf[0]);
    try std.testing.expectEqual(@as(u8, 0x25), buf[1]);
    try std.testing.expectEqual(to, std.mem.readInt(u64, buf[6..14], .little));
}
