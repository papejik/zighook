const std = @import("std");
const zighook = @import("zighook");

const BinFn = fn (c_int, c_int) callconv(.c) c_int;

fn add(a: c_int, b: c_int) callconv(.c) c_int {
    return a + b;
}

fn mul(a: c_int, b: c_int) callconv(.c) c_int {
    return a * b;
}

var add_hook: zighook.Hook(@TypeOf(add)) = undefined;
var mul_hook: zighook.Hook(@TypeOf(mul)) = undefined;

fn addDetour(a: c_int, b: c_int) callconv(.c) c_int {
    return add_hook.call(.{ a, b }) + 100;
}

fn mulDetour(a: c_int, b: c_int) callconv(.c) c_int {
    return mul_hook.call(.{ a, b }) * 2;
}

fn opaquePtr(comptime f: *const BinFn) *const BinFn {
    var p: *const BinFn = f;
    std.mem.doNotOptimizeAway(&p);
    return p;
}

test "inline hook intercepts and trampoline reaches original" {
    const f = opaquePtr(&add);
    try std.testing.expectEqual(@as(c_int, 5), f(2, 3));

    add_hook = try zighook.Hook(@TypeOf(add)).init(&add, &addDetour);
    defer add_hook.deinit();

    try add_hook.enable();
    try std.testing.expectEqual(@as(c_int, 105), f(2, 3));

    try add_hook.disable();
    try std.testing.expectEqual(@as(c_int, 5), f(2, 3));
}

test "transaction enables a batch atomically" {
    const fa = opaquePtr(&add);
    const fm = opaquePtr(&mul);

    add_hook = try zighook.Hook(@TypeOf(add)).init(&add, &addDetour);
    defer add_hook.deinit();
    mul_hook = try zighook.Hook(@TypeOf(mul)).init(&mul, &mulDetour);
    defer mul_hook.deinit();

    try zighook.enableAll(.{ &add_hook, &mul_hook });

    try std.testing.expectEqual(@as(c_int, 105), fa(2, 3));
    try std.testing.expectEqual(@as(c_int, 12), fm(2, 3));

    try zighook.disableAll(.{&mul_hook});
    try std.testing.expectEqual(@as(c_int, 105), fa(2, 3));
    try std.testing.expectEqual(@as(c_int, 6), fm(2, 3));

    try zighook.transaction(.{
        .{ .disable, &add_hook },
        .{ .enable, &mul_hook },
    });
    try std.testing.expectEqual(@as(c_int, 5), fa(2, 3));
    try std.testing.expectEqual(@as(c_int, 12), fm(2, 3));
}

const UnaryFn = fn (c_int) callconv(.c) c_int;

fn vimpl(x: c_int) callconv(.c) c_int {
    return x;
}

fn vhook(x: c_int) callconv(.c) c_int {
    return x + 7;
}

var vtab = [_]usize{0};
var vth: zighook.VTableHook(UnaryFn) = undefined;

test "vtable hook swaps slot and keeps original" {
    vtab[0] = @intFromPtr(&vimpl);
    vth = try zighook.VTableHook(UnaryFn).init(&vtab, 0, &vhook);
    defer vth.deinit();

    try vth.enable();
    const f: *const UnaryFn = @ptrFromInt(vtab[0]);
    try std.testing.expectEqual(@as(c_int, 12), f(5));
    try std.testing.expectEqual(@as(c_int, 5), vth.call(.{5}));

    try vth.disable();
    const g: *const UnaryFn = @ptrFromInt(vtab[0]);
    try std.testing.expectEqual(@as(c_int, 5), g(5));
}
