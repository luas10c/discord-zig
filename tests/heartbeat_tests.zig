const std = @import("std");
const heartbeat = @import("discord-zig").heartbeat;

test "jitter bounds" {
    try std.testing.expectEqual(@as(u64, 0), heartbeat.firstHeartbeatDelayMs(45000, 0.0));
    try std.testing.expectEqual(@as(u64, 45000), heartbeat.firstHeartbeatDelayMs(45000, 1.0));
    try std.testing.expectEqual(@as(u64, 22500), heartbeat.firstHeartbeatDelayMs(45000, 0.5));
}

test "init schedules first beat with jitter" {
    const hb = heartbeat.Monitor.init(45000, 1000);
    try std.testing.expectEqual(@as(u64, 45000), hb.interval_ms);
    try std.testing.expectEqual(@as(i64, 1000 + 22500), hb.next_ms);
    try std.testing.expect(hb.acked);
}

test "waits before due then sends" {
    var hb = heartbeat.Monitor.init(1000, 0);
    try std.testing.expectEqual(heartbeat.Action.wait, try hb.poll(0));
    try std.testing.expectEqual(heartbeat.Action.wait, try hb.poll(499));
    try std.testing.expectEqual(heartbeat.Action.send, try hb.poll(500));
    try std.testing.expect(!hb.acked);
    try std.testing.expectEqual(@as(i64, 1500), hb.next_ms);
}

test "ack suppresses resend until next due" {
    var hb = heartbeat.Monitor.init(1000, 0);
    _ = try hb.poll(500);
    hb.onAck();
    try std.testing.expectEqual(heartbeat.Action.wait, try hb.poll(600));
    try std.testing.expectEqual(heartbeat.Action.send, try hb.poll(1500));
}

test "missing ack past grace period times out" {
    var hb = heartbeat.Monitor.init(1000, 0);
    _ = try hb.poll(500);
    try std.testing.expectEqual(heartbeat.Action.wait, try hb.poll(1500));
    try std.testing.expectEqual(heartbeat.Action.wait, try hb.poll(500 + 11000));
    try std.testing.expectError(error.HeartbeatTimeout, hb.poll(500 + 11001));
}

test "requested beat sends immediately" {
    var hb = heartbeat.Monitor.init(45000, 0);
    try std.testing.expectEqual(heartbeat.Action.wait, try hb.poll(100));
    hb.request();
    try std.testing.expectEqual(heartbeat.Action.send, try hb.poll(100));
    try std.testing.expect(!hb.requested);
    try std.testing.expectEqual(heartbeat.Action.wait, try hb.poll(101));
}

test "reset reschedules" {
    var hb = heartbeat.Monitor.init(1000, 0);
    _ = try hb.poll(500);
    hb.reset(2000, 10000);
    try std.testing.expectEqual(@as(u64, 2000), hb.interval_ms);
    try std.testing.expectEqual(heartbeat.Action.wait, try hb.poll(10000));
    try std.testing.expectEqual(heartbeat.Action.send, try hb.poll(11000));
}

test "setInterval only changes interval" {
    var hb = heartbeat.Monitor.init(1000, 0);
    hb.setInterval(45000);
    try std.testing.expectEqual(@as(u64, 45000), hb.interval_ms);
    try std.testing.expectEqual(@as(i64, 500), hb.next_ms);
}
