const std = @import("std");
const builtin = @import("builtin");

comptime {
    if (builtin.cpu.arch != .x86_64) @compileError("zighook supports x86_64 only");
}

pub const Error = @import("errors.zig").Error;
pub const RawHook = @import("hook.zig").RawHook;
pub const Hook = @import("hook.zig").Hook;
pub const VTableHook = @import("vtable.zig").VTableHook;

const txn = @import("transaction.zig");
pub const Action = txn.Action;
pub const transaction = txn.transaction;
pub const enableAll = txn.enableAll;
pub const disableAll = txn.disableAll;

pub const arch = @import("arch/x86_64.zig");

test {
    _ = @import("arch/x86_64.zig");
    _ = @import("patch.zig");
    _ = @import("trampoline.zig");
    _ = @import("hook.zig");
    _ = @import("vtable.zig");
    _ = @import("transaction.zig");
    _ = @import("os/memory.zig");
}
