const std = @import("std");
const memory = @import("os/memory.zig");
const signature = @import("signature.zig");
const Error = @import("errors.zig").Error;

pub fn VTableHook(comptime Fn: type) type {
    return struct {
        slot: *usize,
        saved: usize,
        detour: usize,
        enabled: bool,
        const Self = @This();

        pub fn init(vtable: [*]usize, index: usize, detour: *const Fn) Error!Self {
            return .{
                .slot = &vtable[index],
                .saved = vtable[index],
                .detour = @intFromPtr(detour),
                .enabled = false,
            };
        }

        pub fn enable(self: *Self) Error!void {
            if (self.enabled) return Error.AlreadyEnabled;
            try self.write(self.detour);
            self.enabled = true;
        }

        pub fn disable(self: *Self) Error!void {
            if (!self.enabled) return Error.NotEnabled;
            try self.write(self.saved);
            self.enabled = false;
        }

        pub fn deinit(self: *Self) void {
            if (self.enabled) self.disable() catch return;
            self.* = undefined;
        }

        pub fn original(self: *const Self) *const Fn {
            return @ptrFromInt(self.saved);
        }

        pub fn call(self: *const Self, args: std.meta.ArgsTuple(Fn)) signature.Returns(Fn) {
            return signature.invoke(Fn, self.saved, args);
        }

        fn write(self: *Self, value: usize) Error!void {
            const addr = @intFromPtr(self.slot);
            const token = try memory.makeWritable(addr, @sizeOf(usize), .data);
            self.slot.* = value;
            memory.restoreProtect(addr, @sizeOf(usize), token, .data) catch {};
        }
    };
}
