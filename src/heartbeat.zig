const std = @import("std");
const gateway = @import("./gateway.zig");

pub const ack_grace_ms: i64 = 10000;

pub fn firstHeartbeatDelayMs(interval_ms: u64, r: f64) u64 {
    const clamped = @min(@max(r, 0.0), 1.0);
    return @intFromFloat(@as(f64, @floatFromInt(interval_ms)) * clamped);
}

pub const Action = enum { send, wait };

pub const Monitor = struct {
    interval_ms: u64 = 45000,
    next_ms: i64 = 0,
    sent_at_ms: i64 = 0,
    acked: bool = true,
    requested: bool = false,

    pub fn init(interval_ms: u64, now_ms: i64) Monitor {
        return .{
            .interval_ms = interval_ms,
            .next_ms = now_ms + @as(i64, @intCast(firstHeartbeatDelayMs(interval_ms, 0.5))),
        };
    }

    pub fn reset(self: *Monitor, interval_ms: u64, now_ms: i64) void {
        self.* = init(interval_ms, now_ms);
    }

    pub fn setInterval(self: *Monitor, interval_ms: u64) void {
        self.interval_ms = interval_ms;
    }

    pub fn request(self: *Monitor) void {
        self.requested = true;
    }

    pub fn onAck(self: *Monitor) void {
        self.acked = true;
    }

    pub fn poll(self: *Monitor, now_ms: i64) !Action {
        const interval = @as(i64, @intCast(self.interval_ms));
        if (!self.acked and now_ms - self.sent_at_ms > interval + ack_grace_ms) {
            return error.HeartbeatTimeout;
        }
        if (self.requested) {
            self.requested = false;
            self.acked = false;
            self.sent_at_ms = now_ms;
            self.next_ms = now_ms + interval;
            return .send;
        }
        if (!self.acked) {
            return .wait;
        }
        if (now_ms >= self.next_ms) {
            self.acked = false;
            self.sent_at_ms = now_ms;
            self.next_ms = now_ms + interval;
            return .send;
        }
        return .wait;
    }
};
