const std = @import("std");
const Error = @import("../errors.zig").Error;

pub const Kind = enum { other, rip_rel, rel8, rel32, rel8_loop };

pub const Insn = struct {
    len: u8,
    kind: Kind = .other,
    disp_off: u8 = 0,
    disp_size: u8 = 0,
};

const Imm = enum { none, ib, iw, id, iz, iv, moffs, enter };

fn immBytes(imm: Imm, opsz16: bool, rex_w: bool, addr32: bool) u8 {
    return switch (imm) {
        .none => 0,
        .ib => 1,
        .iw => 2,
        .id => 4,
        .iz => if (opsz16 and !rex_w) 2 else 4,
        .iv => if (rex_w) 8 else (if (opsz16) 2 else 4),
        .moffs => if (addr32) 4 else 8,
        .enter => 3,
    };
}

pub fn decode(p: [*]const u8) Error!Insn {
    var i: usize = 0;
    var opsz16 = false;
    var addr32 = false;
    var rex_w = false;
    var has_f2 = false;

    while (true) {
        switch (p[i]) {
            0x66 => {
                opsz16 = true;
                rex_w = false;
            },
            0x67 => {
                addr32 = true;
                rex_w = false;
            },
            0xF2 => {
                has_f2 = true;
                rex_w = false;
            },
            0xF0, 0xF3, 0x2E, 0x36, 0x3E, 0x26, 0x64, 0x65 => rex_w = false,
            0x40...0x4F => rex_w = (p[i] & 0x08) != 0,
            else => break,
        }
        i += 1;
    }

    switch (p[i]) {
        0xC5 => return decodeVex(p, i, false),
        0xC4 => return decodeVex(p, i, true),
        0x62 => return decodeEvex(p, i),
        0x8F => if ((p[i + 1] & 0x38) != 0) return decodeXop(p, i),
        else => {},
    }

    const op = p[i];
    i += 1;

    if (op == 0x0F) return decodeTwoByte(p, i, opsz16, rex_w, addr32, has_f2);
    return decodeOneByte(p, i, op, opsz16, rex_w, addr32);
}

fn vexMap1Imm8(op: u8) bool {
    return switch (op) {
        0x70, 0x71, 0x72, 0x73, 0xC2, 0xC4, 0xC5, 0xC6 => true,
        else => false,
    };
}

fn vexImm(map: u8, opcode: u8) Imm {
    if (map == 3) return .ib;
    if (map == 1 and vexMap1Imm8(opcode)) return .ib;
    return .none;
}

fn decodeVex(p: [*]const u8, start: usize, three_byte: bool) Error!Insn {
    var i = start;
    var map: u8 = 1;
    if (three_byte) {
        map = p[i + 1] & 0x1F;
        i += 3;
    } else {
        i += 2;
    }
    const opcode = p[i];
    i += 1;
    if (map < 1 or map > 3) return Error.UnsupportedInstruction;

    const has_modrm = !(map == 1 and opcode == 0x77);
    const imm = vexImm(map, opcode);

    var rip_off: usize = 0;
    if (has_modrm) {
        const m = parseModrm(p, i);
        i = m.next;
        rip_off = m.rip_off;
    }
    if (imm == .ib) i += 1;
    return modrmInsn(i, rip_off);
}

fn decodeEvex(p: [*]const u8, start: usize) Error!Insn {
    var i = start;
    const map = p[i + 1] & 0x07;
    i += 4;
    const opcode = p[i];
    i += 1;
    if (map == 0 or map == 4 or map == 7) return Error.UnsupportedInstruction;

    const imm = vexImm(map, opcode);
    const m = parseModrm(p, i);
    i = m.next;
    if (imm == .ib) i += 1;
    return modrmInsn(i, m.rip_off);
}

fn xopImm(map: u8) Imm {
    return switch (map) {
        8 => .ib,
        10 => .id,
        else => .none,
    };
}

fn decodeXop(p: [*]const u8, start: usize) Error!Insn {
    var i = start;
    const map = p[i + 1] & 0x1F;
    i += 3;
    i += 1;
    if (map < 8 or map > 10) return Error.UnsupportedInstruction;

    const imm = xopImm(map);
    const m = parseModrm(p, i);
    i = m.next;
    i += immBytes(imm, false, false, false);
    return modrmInsn(i, m.rip_off);
}

fn relInsn(after_opcode: usize, disp_size: u8, kind: Kind) Insn {
    return .{
        .len = @intCast(after_opcode + disp_size),
        .kind = kind,
        .disp_off = @intCast(after_opcode),
        .disp_size = disp_size,
    };
}

const ModrmResult = struct { next: usize, rip_off: usize };

fn parseModrm(p: [*]const u8, start: usize) ModrmResult {
    var i = start;
    const modrm = p[i];
    i += 1;
    const mod = modrm >> 6;
    const rm = modrm & 0x07;
    var rip_off: usize = 0;
    if (mod != 3) {
        if (rm == 4) {
            const sib = p[i];
            i += 1;
            const base = sib & 0x07;
            if (mod == 0) {
                if (base == 5) i += 4;
            } else if (mod == 1) {
                i += 1;
            } else {
                i += 4;
            }
        } else if (mod == 0 and rm == 5) {
            rip_off = i;
            i += 4;
        } else if (mod == 1) {
            i += 1;
        } else if (mod == 2) {
            i += 4;
        }
    }
    return .{ .next = i, .rip_off = rip_off };
}

fn decodeOneByte(p: [*]const u8, start: usize, op: u8, opsz16: bool, rex_w: bool, addr32: bool) Error!Insn {
    const i = start;

    if (op >= 0x70 and op <= 0x7F) return relInsn(i, 1, .rel8);
    switch (op) {
        0xEB => return relInsn(i, 1, .rel8),
        0xE8, 0xE9 => return relInsn(i, 4, .rel32),
        0xE0, 0xE1, 0xE2, 0xE3 => return relInsn(i, 1, .rel8_loop),
        else => {},
    }

    if (op == 0xC7 and p[i] == 0xF8) {
        return relInsn(i + 1, if (opsz16) 2 else 4, .rel32);
    }

    var has_modrm = false;
    var imm = Imm.none;

    if (op < 0x40) {
        switch (op & 0x07) {
            0, 1, 2, 3 => has_modrm = true,
            4 => imm = .ib,
            5 => imm = .iz,
            else => {},
        }
    } else switch (op) {
        0x50...0x5F, 0x6C...0x6F, 0x90...0x99, 0x9B...0x9F, 0xA4...0xA7, 0xAA...0xAF, 0xC3, 0xC9, 0xCB, 0xCC, 0xCE, 0xCF, 0xD7, 0xEC...0xEF, 0xF1, 0xF4, 0xF5, 0xF8...0xFD => {},
        0x63, 0x84...0x8F, 0xD0...0xD3, 0xD8...0xDF, 0xFE, 0xFF => has_modrm = true,
        0x68 => imm = .iz,
        0x69 => {
            has_modrm = true;
            imm = .iz;
        },
        0x6A => imm = .ib,
        0x6B => {
            has_modrm = true;
            imm = .ib;
        },
        0x80, 0x82, 0x83 => {
            has_modrm = true;
            imm = .ib;
        },
        0x81 => {
            has_modrm = true;
            imm = .iz;
        },
        0xA0...0xA3 => imm = .moffs,
        0xA8 => imm = .ib,
        0xA9 => imm = .iz,
        0xB0...0xB7 => imm = .ib,
        0xB8...0xBF => imm = .iv,
        0xC0, 0xC1 => {
            has_modrm = true;
            imm = .ib;
        },
        0xC2, 0xCA => imm = .iw,
        0xC6 => {
            has_modrm = true;
            imm = .ib;
        },
        0xC7 => {
            has_modrm = true;
            imm = .iz;
        },
        0xC8 => imm = .enter,
        0xCD => imm = .ib,
        0xE4...0xE7 => imm = .ib,
        0xF6, 0xF7 => has_modrm = true,
        else => return Error.UnsupportedInstruction,
    }

    var cur = i;
    var rip_off: usize = 0;
    if (has_modrm) {
        if (op == 0xF6 or op == 0xF7) {
            const reg = (p[cur] >> 3) & 0x07;
            if (reg == 0 or reg == 1) imm = if (op == 0xF6) .ib else .iz;
        }
        const m = parseModrm(p, cur);
        cur = m.next;
        rip_off = m.rip_off;
    }
    cur += immBytes(imm, opsz16, rex_w, addr32);

    return .{
        .len = @intCast(cur),
        .kind = if (rip_off != 0) .rip_rel else .other,
        .disp_off = @intCast(rip_off),
        .disp_size = if (rip_off != 0) 4 else 0,
    };
}

fn twoByteNoModrm(op2: u8) bool {
    return switch (op2) {
        0x05, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0E, 0x37, 0x77, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0xA0, 0xA1, 0xA2, 0xA8, 0xA9, 0xAA, 0xC8...0xCF => true,
        else => false,
    };
}

fn twoByteImm8(op2: u8) bool {
    return switch (op2) {
        0x70, 0x71, 0x72, 0x73, 0xA4, 0xAC, 0xBA, 0xC2, 0xC4, 0xC5, 0xC6 => true,
        else => false,
    };
}

fn decodeTwoByte(p: [*]const u8, start: usize, opsz16: bool, rex_w: bool, addr32: bool, has_f2: bool) Error!Insn {
    var i = start;
    const op2 = p[i];
    i += 1;

    if (op2 >= 0x80 and op2 <= 0x8F) return relInsn(i, 4, .rel32);

    if (op2 == 0x0F) {
        const m = parseModrm(p, i);
        i = m.next + 1;
        return modrmInsn(i, m.rip_off);
    }

    if (op2 == 0x20 or op2 == 0x21 or op2 == 0x22 or op2 == 0x23) {
        i += 1;
        return .{ .len = @intCast(i), .kind = .other, .disp_off = 0, .disp_size = 0 };
    }

    var has_modrm = true;
    var imm = Imm.none;
    var extra2 = false;

    if (op2 == 0x38 or op2 == 0x3A) {
        i += 1;
        imm = if (op2 == 0x3A) .ib else .none;
    } else if (op2 == 0x78) {
        extra2 = opsz16 or has_f2;
    } else {
        has_modrm = !twoByteNoModrm(op2);
        if (twoByteImm8(op2)) imm = .ib;
    }

    var rip_off: usize = 0;
    if (has_modrm) {
        const m = parseModrm(p, i);
        i = m.next;
        rip_off = m.rip_off;
    }
    i += immBytes(imm, opsz16, rex_w, addr32);
    if (extra2) i += 2;

    return modrmInsn(i, rip_off);
}

fn modrmInsn(len: usize, rip_off: usize) Insn {
    return .{
        .len = @intCast(len),
        .kind = if (rip_off != 0) .rip_rel else .other,
        .disp_off = @intCast(rip_off),
        .disp_size = if (rip_off != 0) 4 else 0,
    };
}

pub const Reloc = struct { src_len: usize, out_len: usize };

const min_i32: i64 = std.math.minInt(i32);
const max_i32: i64 = std.math.maxInt(i32);

fn fitsI32(v: i64) bool {
    return v >= min_i32 and v <= max_i32;
}

pub fn relocate(target: usize, dst: usize, min_len: usize, out: []u8) Error!Reloc {
    const src: [*]const u8 = @ptrFromInt(target);

    var insns: [16]Insn = undefined;
    var offs: [16]usize = undefined;
    var n: usize = 0;
    var covered: usize = 0;
    while (covered < min_len) {
        if (n >= insns.len) return Error.PrologueTooShort;
        const ins = try decode(src + covered);
        insns[n] = ins;
        offs[n] = covered;
        covered += ins.len;
        n += 1;
    }
    const src_len = covered;
    const region_lo: i64 = @intCast(target);
    const region_hi: i64 = @intCast(target + src_len);

    var dst_off: usize = 0;
    for (insns[0..n], 0..) |ins, idx| {
        const s_off = offs[idx];
        const from: [*]const u8 = src + s_off;
        const ilen: usize = ins.len;
        switch (ins.kind) {
            .other => {
                @memcpy(try reserve(out, dst_off, ilen), from[0..ilen]);
                dst_off += ilen;
            },
            .rip_rel => {
                const buf = try reserve(out, dst_off, ilen);
                @memcpy(buf, from[0..ilen]);
                const disp = std.mem.readInt(i32, from[ins.disp_off..][0..4], .little);
                const abs = @as(i64, @intCast(target + s_off + ilen)) + disp;
                const new_disp = abs - @as(i64, @intCast(dst + dst_off + ilen));
                if (!fitsI32(new_disp)) return Error.UnsupportedInstruction;
                std.mem.writeInt(i32, buf[ins.disp_off..][0..4], @intCast(new_disp), .little);
                dst_off += ilen;
            },
            .rel8, .rel32, .rel8_loop => {
                if (ins.kind == .rel8_loop or ins.disp_size == 2) return Error.UnsupportedInstruction;
                const disp: i64 = if (ins.disp_size == 1)
                    std.mem.readInt(i8, from[ins.disp_off..][0..1], .little)
                else
                    std.mem.readInt(i32, from[ins.disp_off..][0..4], .little);
                const abs_t = @as(i64, @intCast(target + s_off + ilen)) + disp;
                if (abs_t >= region_lo and abs_t < region_hi) return Error.UnsupportedInstruction;
                dst_off += try emitNearBranch(out, dst_off, dst, from, ins, abs_t);
            },
        }
    }

    return .{ .src_len = src_len, .out_len = dst_off };
}

fn reserve(out: []u8, off: usize, len: usize) Error![]u8 {
    if (off + len > out.len) return Error.OutOfExecutableMemory;
    return out[off..][0..len];
}

fn emitNearBranch(out: []u8, dst_off: usize, dst: usize, from: [*]const u8, ins: Insn, target_abs: i64) Error!usize {
    if (ins.disp_size == 4) {
        const head = ins.disp_off;
        const new_len = head + 4;
        const buf = try reserve(out, dst_off, new_len);
        @memcpy(buf[0..head], from[0..head]);
        const new_disp = target_abs - @as(i64, @intCast(dst + dst_off + new_len));
        if (!fitsI32(new_disp)) return Error.UnsupportedInstruction;
        std.mem.writeInt(i32, buf[head..][0..4], @intCast(new_disp), .little);
        return new_len;
    }

    const prefix_len = ins.disp_off - 1;
    const opcode = from[prefix_len];
    const new_len = prefix_len + @as(usize, if (opcode == 0xEB) 5 else 6);
    const buf = try reserve(out, dst_off, new_len);
    @memcpy(buf[0..prefix_len], from[0..prefix_len]);
    if (opcode == 0xEB) {
        buf[prefix_len] = 0xE9;
    } else if (opcode >= 0x70 and opcode <= 0x7F) {
        buf[prefix_len] = 0x0F;
        buf[prefix_len + 1] = 0x80 + (opcode - 0x70);
    } else return Error.UnsupportedInstruction;
    const new_disp = target_abs - @as(i64, @intCast(dst + dst_off + new_len));
    if (!fitsI32(new_disp)) return Error.UnsupportedInstruction;
    std.mem.writeInt(i32, buf[new_len - 4 ..][0..4], @intCast(new_disp), .little);
    return new_len;
}

fn expectLen(bytes: []const u8, len: u8, kind: Kind) !void {
    const ins = try decode(bytes.ptr);
    try std.testing.expectEqual(len, ins.len);
    try std.testing.expectEqual(kind, ins.kind);
}

test "decode common prologue instructions" {
    try expectLen(&.{0x55}, 1, .other);
    try expectLen(&.{ 0x48, 0x89, 0xE5 }, 3, .other);
    try expectLen(&.{ 0x48, 0x83, 0xEC, 0x20 }, 4, .other);
    try expectLen(&.{ 0xB8, 0x78, 0x56, 0x34, 0x12 }, 5, .other);
    try expectLen(&.{ 0x48, 0xB8, 1, 2, 3, 4, 5, 6, 7, 8 }, 10, .other);
    try expectLen(&.{0xC3}, 1, .other);
    try expectLen(&.{ 0x85, 0xC0 }, 2, .other);
    try expectLen(&.{ 0x0F, 0xB6, 0x01 }, 3, .other);
    try expectLen(&.{ 0xF3, 0x0F, 0x1E, 0xFA }, 4, .other);
    try expectLen(&.{ 0x0F, 0x1F, 0x44, 0x00, 0x00 }, 5, .other);
    try expectLen(&.{ 0x80, 0x00, 0x12 }, 3, .other);
}

test "decode relative and rip-relative" {
    try expectLen(&.{ 0x74, 0x05 }, 2, .rel8);
    try expectLen(&.{ 0xEB, 0xFE }, 2, .rel8);
    try expectLen(&.{ 0xE9, 0, 0, 0, 0 }, 5, .rel32);
    try expectLen(&.{ 0xE8, 0, 0, 0, 0 }, 5, .rel32);
    try expectLen(&.{ 0x0F, 0x84, 0, 0, 0, 0 }, 6, .rel32);
    try expectLen(&.{ 0xE2, 0xFE }, 2, .rel8_loop);

    const lea = [_]u8{ 0x48, 0x8D, 0x05, 0x10, 0x00, 0x00, 0x00 };
    const ins = try decode(&lea);
    try std.testing.expectEqual(@as(u8, 7), ins.len);
    try std.testing.expectEqual(Kind.rip_rel, ins.kind);
    try std.testing.expectEqual(@as(u8, 3), ins.disp_off);
}

test "relocate rewrites rip-relative displacement" {
    var mem: [96]u8 = undefined;
    const code = [_]u8{ 0x48, 0x8D, 0x05, 0x10, 0x00, 0x00, 0x00, 0xC3 };
    @memcpy(mem[0..code.len], &code);
    const out = mem[32..];
    const target = @intFromPtr(&mem);
    const dst = @intFromPtr(out.ptr);
    const r = try relocate(target, dst, 5, out);
    try std.testing.expectEqual(@as(usize, 7), r.src_len);
    try std.testing.expectEqual(@as(usize, 7), r.out_len);
    const abs: i64 = @as(i64, @intCast(target + 7)) + 0x10;
    const got = std.mem.readInt(i32, out[3..7], .little);
    const expected: i64 = abs - @as(i64, @intCast(dst + 7));
    try std.testing.expectEqual(@as(i32, @intCast(expected)), got);
}

test "relocate widens out-of-region short jcc" {
    var mem: [96]u8 = undefined;
    const code = [_]u8{ 0x74, 0x10, 0x90, 0x90, 0x90 };
    @memcpy(mem[0..code.len], &code);
    const out = mem[32..];
    const target = @intFromPtr(&mem);
    const dst = @intFromPtr(out.ptr);
    const r = try relocate(target, dst, 2, out);
    try std.testing.expectEqual(@as(usize, 2), r.src_len);
    try std.testing.expectEqual(@as(usize, 6), r.out_len);
    try std.testing.expectEqual(@as(u8, 0x0F), out[0]);
    try std.testing.expectEqual(@as(u8, 0x84), out[1]);

    const abs_t: i64 = @as(i64, @intCast(target + 2)) + 0x10;
    const got = std.mem.readInt(i32, out[2..6], .little);
    const expected: i64 = abs_t - @as(i64, @intCast(dst + 6));
    try std.testing.expectEqual(@as(i32, @intCast(expected)), got);
}
