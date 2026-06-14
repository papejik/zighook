const std = @import("std");
const windows = std.os.windows;
const Error = @import("../errors.zig").Error;
const page = @import("page.zig");

pub const Token = windows.DWORD;

const MEM_COMMIT: windows.DWORD = 0x1000;
const MEM_RESERVE: windows.DWORD = 0x2000;
const MEM_FREE: windows.DWORD = 0x10000;
const PAGE_READWRITE: windows.DWORD = 0x04;
const PAGE_EXECUTE_READWRITE: windows.DWORD = 0x40;
const granularity: usize = 0x10000;

pub fn allocExecNear(near: usize, size: usize) Error![]align(std.heap.page_size_min) u8 {
    const lo = near -| page.near_range;
    const hi = near +| page.near_range;

    var addr = lo;
    while (addr < hi) {
        var info: MemoryBasicInformation = undefined;
        if (VirtualQuery(@ptrFromInt(addr), &info, @sizeOf(MemoryBasicInformation)) == 0) break;
        const region_end = info.base +| info.region_size;

        if (info.state == MEM_FREE) {
            const candidate = std.mem.alignForward(usize, @max(info.base, lo), granularity);
            if (candidate >= lo and candidate < hi and candidate + size <= region_end) {
                if (VirtualAlloc(@ptrFromInt(candidate), size, MEM_COMMIT | MEM_RESERVE, PAGE_EXECUTE_READWRITE)) |p| {
                    const ptr: [*]align(std.heap.page_size_min) u8 = @alignCast(@ptrCast(p));
                    return ptr[0..size];
                }
            }
        }

        if (region_end <= addr) break;
        addr = region_end;
    }
    return Error.OutOfExecutableMemory;
}

pub fn makeWritable(addr: usize, len: usize, prot: page.Prot) Error!Token {
    const flags: windows.DWORD = switch (prot) {
        .code => PAGE_EXECUTE_READWRITE,
        .data => PAGE_READWRITE,
    };
    const r = page.cover(addr, len);
    var old: windows.DWORD = 0;
    if (VirtualProtect(@ptrFromInt(r.base), r.len, flags, &old) == 0) return Error.ProtectFailed;
    return old;
}

pub fn restoreProtect(addr: usize, len: usize, token: Token, prot: page.Prot) Error!void {
    _ = prot;
    const r = page.cover(addr, len);
    var old: windows.DWORD = 0;
    if (VirtualProtect(@ptrFromInt(r.base), r.len, token, &old) == 0) return Error.ProtectFailed;
}

pub fn flushICache(addr: usize, len: usize) void {
    _ = FlushInstructionCache(windows.GetCurrentProcess(), @ptrFromInt(addr), len);
}

const MemoryBasicInformation = extern struct {
    base: usize,
    allocation_base: usize,
    allocation_protect: windows.DWORD,
    partition_id: windows.DWORD,
    region_size: usize,
    state: windows.DWORD,
    protect: windows.DWORD,
    type: windows.DWORD,
    _pad: windows.DWORD,
};

extern "kernel32" fn VirtualAlloc(?windows.LPVOID, windows.SIZE_T, windows.DWORD, windows.DWORD) callconv(.winapi) ?windows.LPVOID;
extern "kernel32" fn VirtualProtect(windows.LPVOID, windows.SIZE_T, windows.DWORD, *windows.DWORD) callconv(.winapi) c_int;
extern "kernel32" fn VirtualQuery(?windows.LPCVOID, *MemoryBasicInformation, windows.SIZE_T) callconv(.winapi) windows.SIZE_T;
extern "kernel32" fn FlushInstructionCache(windows.HANDLE, ?windows.LPCVOID, windows.SIZE_T) callconv(.winapi) c_int;
