const std = @import("std");

pub fn nowMs(io: std.Io) i64 {
    const ns = std.Io.Timestamp.now(io, .awake).nanoseconds;
    return @intCast(@divTrunc(ns, std.time.ns_per_ms));
}

pub fn realNowSec(io: std.Io) i64 {
    const ns = std.Io.Timestamp.now(io, .real).nanoseconds;
    return @intCast(@divTrunc(ns, std.time.ns_per_s));
}

pub fn realNowMs(io: std.Io) i64 {
    const ns = std.Io.Timestamp.now(io, .real).nanoseconds;
    return @intCast(@divTrunc(ns, std.time.ns_per_ms));
}

pub fn backoffMs(attempt: u32) u64 {
    const shift: u6 = @min(attempt, 6);
    const base: u64 = @as(u64, 1000) << shift;
    return @min(base, 30000);
}

/// Vida mínima para uma conexão contar como estável: a queda não entra no
/// backoff exponencial (ex.: close 1001 do LB do Discord após horas/dias
/// online reconecta já, não espera 30s).
pub const stable_connection_ms: i64 = 60_000;

/// Delay + próximo contador de backoff após uma queda do gateway. Conexão
/// estável reseta o backoff; flapping curto continua exponencial a partir
/// do contador atual.
pub fn backoffAfterDrop(attempt: u32, lived_ms: i64) struct { delay_ms: u64, attempt: u32 } {
    if (lived_ms >= stable_connection_ms) return .{ .delay_ms = backoffMs(0), .attempt = 1 };
    return .{ .delay_ms = backoffMs(attempt), .attempt = @min(attempt + 1, 16) };
}

pub fn getHeader(head_bytes: []const u8, name: []const u8) ?[]const u8 {
    var lines = std.mem.splitSequence(u8, head_bytes, "\r\n");
    _ = lines.first();
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const key = std.mem.trim(u8, line[0..colon], " \t");
        if (!std.ascii.eqlIgnoreCase(key, name)) continue;
        return std.mem.trim(u8, line[colon + 1 ..], " \t");
    }
    return null;
}

pub fn parseU64OrNull(text: ?[]const u8) ?u64 {
    const s = text orelse return null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}

pub fn parseFloatOrNull(text: ?[]const u8) ?f64 {
    const s = text orelse return null;
    return std.fmt.parseFloat(f64, s) catch null;
}

fn isUnreserved(c: u8) bool {
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '-' or c == '_' or c == '.' or c == '~';
}

pub fn encodeEmoji(allocator: std.mem.Allocator, emoji: []const u8) ![]u8 {
    const hex = "0123456789ABCDEF";
    // Pior caso %XX por byte: aloca o tamanho exato uma única vez em vez de
    // crescer um writer por realloc; encolhe no final (shrink é in-place).
    const out = try allocator.alloc(u8, emoji.len * 3);
    var n: usize = 0;
    for (emoji) |c| {
        if (isUnreserved(c)) {
            out[n] = c;
            n += 1;
        } else {
            out[n] = '%';
            out[n + 1] = hex[c >> 4];
            out[n + 2] = hex[c & 0xF];
            n += 3;
        }
    }
    if (n < out.len) {
        const shrunk = try allocator.realloc(out, n);
        return shrunk;
    }
    return out;
}
