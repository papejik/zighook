# zighook

[![CI](https://github.com/papejik/zighook/actions/workflows/ci.yml/badge.svg)](https://github.com/papejik/zighook/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Zig](https://img.shields.io/badge/zig-nightly-f7a41d.svg)](https://ziglang.org)

Runtime function hooking for Zig - inline detours and vtable swaps with a
type-safe, comptime API. A spiritual port of [MinHook] / [Microsoft Detours] /
[detour-rs], built to be a clean Zig citizen: **zero dependencies, pure `std`.**

```zig
const zighook = @import("zighook");

fn myMessageBoxA(hwnd: ?*anyopaque, text: [*:0]const u8,
                 cap: [*:0]const u8, kind: u32) callconv(.c) c_int {
    return hook.call(.{ hwnd, "hooked!", cap, kind }); // call the original, fully typed
}

var hook = try zighook.Hook(@TypeOf(MessageBoxA)).init(&MessageBoxA, &myMessageBoxA);
defer hook.deinit();
try hook.enable();
```

## Features

- **Typed inline detours** - `Hook(@TypeOf(fn))` gives a type-checked `.call(args)`
  to reach the original through the trampoline. No manual casts.
- **VTable hooks** - `VTableHook(Fn)` for C++ / COM / DirectX interface slots.
- **Batch transactions** - `enableAll` / `disableAll` / `transaction` apply many hooks together and roll back on failure.
- **Raw layer** - `RawHook` works on bare addresses for dynamic / scanned targets.
- **Hybrid jumps** - 5-byte `rel32` when in range, 14-byte `abs64` otherwise.
- **Cross-platform** - Windows, Linux, macOS on **x86_64**.
- No libc requirement on Windows/Linux; just `std`.

## Install

```sh
zig fetch --save git+https://github.com/papejik/zighook
```

```zig
// build.zig
const zighook = b.dependency("zighook", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("zighook", zighook.module("zighook"));
```

## Usage

### Inline hook

```zig
var hook: zighook.Hook(@TypeOf(target)) = undefined;

fn detour(x: c_int) callconv(.c) c_int {
    return hook.call(.{x}) + 1; // original via trampoline
}

hook = try zighook.Hook(@TypeOf(target)).init(&target, &detour);
defer hook.deinit();
try hook.enable();
// ... target() now runs detour; hook.call(...) runs the real target
try hook.disable();
```

### VTable hook

```zig
var vh = try zighook.VTableHook(PresentFn).init(vtable_ptr, 8, &myPresent);
defer vh.deinit();
try vh.enable();
const r = vh.call(.{ swapchain, 1, 0 }); // original slot
```

### Batch transactions

Apply several hooks together; if any step fails the rest are rolled back.

```zig
try zighook.enableAll(.{ &hook_a, &hook_b });

// mixed actions in one transaction:
try zighook.transaction(.{
    .{ .disable, &hook_a },
    .{ .enable, &hook_c },
});
```

### Raw layer

```zig
var raw = try zighook.RawHook.init(target_addr, @intFromPtr(&detour));
defer raw.deinit();
try raw.enable();
const orig: *const fn (c_int) callconv(.c) c_int = @ptrFromInt(@intFromPtr(raw.trampoline));
```

## How it works

`enable()` relocates the first instructions of the target into a trampoline
allocated **within ±2 GB** of the target (so `rel32` jumps and `RIP`-relative
operands stay encodable), appends a jump back, then overwrites the prologue with
a jump to your detour. A focused x86_64 length-decoder copies whole instructions,
rewrites `rel32` branches and `RIP`-relative displacements, and widens short
`Jcc` to near form. `disable()` restores the saved bytes.

## Limitations (v1)

- x86_64 only.
- Best-effort under concurrency: patch the prologue while the target is quiescent
  (e.g. at startup). Thread suspension is a planned extension point.
- A prologue with a self-referential branch (target inside the stolen bytes) or
  `LOOP`/`JrCXZ` in the stolen bytes returns `error.UnsupportedInstruction`
  rather than miscompiling.

## Testing

```sh
zig build test       # unit + integration
zig build examples   # build runnable examples into zig-out/bin
```

[MinHook]: https://github.com/TsudaKageyu/minhook
[Microsoft Detours]: https://github.com/microsoft/Detours
[Detours]: https://github.com/microsoft/Detours
[detour-rs]: https://github.com/darfink/detour-rs
[zigzag]: https://github.com/uniboi/zigzag
