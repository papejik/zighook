const std = @import("std");
const arch = @import("arch/x86_64.zig");
const patch = @import("patch.zig");
const pool = @import("trampoline.zig");
const memory = @import("os/memory.zig");
const signature = @import("signature.zig");
const Error = @import("errors.zig").Error;

const max_patch = 32;

pub const RawHook = struct {
    target: usize,
    detour: usize,
    trampoline: [*]u8,
    slot: []u8,
    original: [max_patch]u8,
    patch_len: u8,
    enabled: bool,

    pub fn init(target: usize, detour: usize) Error!RawHook {
        const slot = try pool.acquire(target);
        errdefer pool.release(slot);

        const dst = @intFromPtr(slot.ptr);
        const body = slot[0 .. slot.len - patch.far_jmp_len];
        const reloc = try arch.relocate(target, dst, patch.jmpLen(target, detour), body);
        if (reloc.src_len > max_patch) return Error.PrologueTooShort;

        const back_len = patch.writeJmp(slot[reloc.out_len..], dst + reloc.out_len, target + reloc.src_len);
        memory.flushICache(dst, reloc.out_len + back_len);

        var self = RawHook{
            .target = target,
            .detour = detour,
            .trampoline = slot.ptr,
            .slot = slot,
            .original = undefined,
            .patch_len = @intCast(reloc.src_len),
            .enabled = false,
        };
        @memcpy(self.original[0..reloc.src_len], @as([*]const u8, @ptrFromInt(target))[0..reloc.src_len]);
        return self;
    }

    pub fn enable(self: *RawHook) Error!void {
        if (self.enabled) return Error.AlreadyEnabled;
        var buf: [max_patch]u8 = undefined;
        const jlen = patch.writeJmp(&buf, self.target, self.detour);
        @memset(buf[jlen..self.patch_len], 0x90);
        try self.writeCode(buf[0..self.patch_len]);
        self.enabled = true;
    }

    pub fn disable(self: *RawHook) Error!void {
        if (!self.enabled) return Error.NotEnabled;
        try self.writeCode(self.original[0..self.patch_len]);
        self.enabled = false;
    }

    pub fn deinit(self: *RawHook) void {
        if (self.enabled) self.disable() catch return;
        pool.release(self.slot);
        self.* = undefined;
    }

    fn writeCode(self: *RawHook, bytes: []const u8) Error!void {
        const token = try memory.makeWritable(self.target, bytes.len, .code);
        @memcpy(@as([*]u8, @ptrFromInt(self.target))[0..bytes.len], bytes);
        memory.flushICache(self.target, bytes.len);
        memory.restoreProtect(self.target, bytes.len, token, .code) catch {};
    }
};

pub fn Hook(comptime Fn: type) type {
    return struct {
        raw: RawHook,
        const Self = @This();

        pub fn init(target: *const Fn, detour: *const Fn) Error!Self {
            return .{ .raw = try RawHook.init(@intFromPtr(target), @intFromPtr(detour)) };
        }

        pub fn enable(self: *Self) Error!void {
            return self.raw.enable();
        }

        pub fn disable(self: *Self) Error!void {
            return self.raw.disable();
        }

        pub fn deinit(self: *Self) void {
            self.raw.deinit();
        }

        pub fn original(self: *const Self) *const Fn {
            return @ptrFromInt(@intFromPtr(self.raw.trampoline));
        }

        pub fn call(self: *const Self, args: std.meta.ArgsTuple(Fn)) signature.Returns(Fn) {
            return signature.invoke(Fn, @intFromPtr(self.raw.trampoline), args);
        }
    };
}
