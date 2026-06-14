const std = @import("std");
const zighook = @import("zighook");

const Render = fn (c_int) callconv(.c) c_int;

fn realRender(frame: c_int) callconv(.c) c_int {
    return frame;
}

fn watermark(frame: c_int) callconv(.c) c_int {
    return frame + 1000;
}

var vtable: [1]usize = undefined;
var hook: zighook.VTableHook(Render) = undefined;

pub fn main() !void {
    vtable[0] = @intFromPtr(&realRender);

    const before: *const Render = @ptrFromInt(vtable[0]);
    std.debug.print("before: render(7) = {d}\n", .{before(7)});

    hook = try zighook.VTableHook(Render).init(&vtable, 0, &watermark);
    defer hook.deinit();
    try hook.enable();

    const after: *const Render = @ptrFromInt(vtable[0]);
    std.debug.print("after:  render(7) = {d}\n", .{after(7)});
    std.debug.print("original via hook: {d}\n", .{hook.call(.{7})});
}
