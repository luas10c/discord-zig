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
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    for (emoji) |c| {
        if (isUnreserved(c)) {
            try out.writer.writeByte(c);
        } else {
            try out.writer.writeAll(&.{ '%', hex[c >> 4], hex[c & 0xF] });
        }
    }
    return out.toOwnedSlice();
}
