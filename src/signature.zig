const std = @import("std");

pub fn Returns(comptime Fn: type) type {
    return info(Fn).return_type.?;
}

pub fn invoke(comptime Fn: type, address: usize, args: std.meta.ArgsTuple(Fn)) Returns(Fn) {
    const f: *const Fn = @ptrFromInt(address);
    return @call(.auto, f, args);
}

fn info(comptime Fn: type) std.builtin.Type.Fn {
    return switch (@typeInfo(Fn)) {
        .@"fn" => |f| f,
        else => @compileError("zighook: expected a function type, e.g. @TypeOf(MessageBoxA)"),
    };
}
