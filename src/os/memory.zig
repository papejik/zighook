const builtin = @import("builtin");
const page = @import("page.zig");

const impl = if (builtin.os.tag == .windows)
    @import("windows.zig")
else
    @import("posix.zig");

pub const Prot = page.Prot;
pub const near_range = page.near_range;
pub const Token = impl.Token;
pub const allocExecNear = impl.allocExecNear;
pub const makeWritable = impl.makeWritable;
pub const restoreProtect = impl.restoreProtect;
pub const flushICache = impl.flushICache;
