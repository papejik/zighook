const Error = @import("errors.zig").Error;

pub const Action = enum { enable, disable };

pub fn transaction(ops: anytype) Error!void {
    var applied: usize = 0;
    errdefer {
        inline for (ops, 0..) |op, i| {
            if (i < applied) revert(op);
        }
    }
    inline for (ops) |op| {
        try apply(op);
        applied += 1;
    }
}

pub fn enableAll(hooks: anytype) Error!void {
    var applied: usize = 0;
    errdefer {
        inline for (hooks, 0..) |hook, i| {
            if (i < applied) hook.disable() catch {};
        }
    }
    inline for (hooks) |hook| {
        try hook.enable();
        applied += 1;
    }
}

pub fn disableAll(hooks: anytype) Error!void {
    var applied: usize = 0;
    errdefer {
        inline for (hooks, 0..) |hook, i| {
            if (i < applied) hook.enable() catch {};
        }
    }
    inline for (hooks) |hook| {
        try hook.disable();
        applied += 1;
    }
}

fn apply(op: anytype) Error!void {
    const action: Action = op[0];
    return switch (action) {
        .enable => op[1].enable(),
        .disable => op[1].disable(),
    };
}

fn revert(op: anytype) void {
    const action: Action = op[0];
    switch (action) {
        .enable => op[1].disable() catch {},
        .disable => op[1].enable() catch {},
    }
}
