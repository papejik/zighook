const std = @import("std");
const zighook = @import("zighook");

fn slowDouble(x: c_int) callconv(.c) c_int {
    return x * 2;
}

var hook: zighook.Hook(@TypeOf(slowDouble)) = undefined;

fn fastDouble(x: c_int) callconv(.c) c_int {
    return hook.call(.{x}) + 1;
}

pub fn main() !void {
    var fp: *const fn (c_int) callconv(.c) c_int = &slowDouble;
    std.mem.doNotOptimizeAway(&fp);

    std.debug.print("before hook: slowDouble(21) = {d}\n", .{fp(21)});

    hook = try zighook.Hook(@TypeOf(slowDouble)).init(&slowDouble, &fastDouble);
    defer hook.deinit();
    try hook.enable();

    std.debug.print("after hook:  slowDouble(21) = {d}\n", .{fp(21)});

    try hook.disable();
    std.debug.print("disabled:    slowDouble(21) = {d}\n", .{fp(21)});
}
