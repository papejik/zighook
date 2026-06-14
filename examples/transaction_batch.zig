const std = @import("std");
const zighook = @import("zighook");

fn login(user: c_int) callconv(.c) c_int {
    return user;
}

fn logout(user: c_int) callconv(.c) c_int {
    return -user;
}

var login_hook: zighook.Hook(@TypeOf(login)) = undefined;
var logout_hook: zighook.Hook(@TypeOf(logout)) = undefined;

fn loginDetour(user: c_int) callconv(.c) c_int {
    return login_hook.call(.{user}) + 1;
}

fn logoutDetour(user: c_int) callconv(.c) c_int {
    return logout_hook.call(.{user}) - 1;
}

pub fn main() !void {
    var fl: *const fn (c_int) callconv(.c) c_int = &login;
    var fo: *const fn (c_int) callconv(.c) c_int = &logout;
    std.mem.doNotOptimizeAway(&fl);
    std.mem.doNotOptimizeAway(&fo);

    login_hook = try zighook.Hook(@TypeOf(login)).init(&login, &loginDetour);
    defer login_hook.deinit();
    logout_hook = try zighook.Hook(@TypeOf(logout)).init(&logout, &logoutDetour);
    defer logout_hook.deinit();

    try zighook.enableAll(.{ &login_hook, &logout_hook });

    std.debug.print("login(5)  = {d}\n", .{fl(5)});
    std.debug.print("logout(5) = {d}\n", .{fo(5)});
}
