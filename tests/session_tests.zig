const std = @import("std");
const Session = @import("discord-zig").session.Session;
const intents = @import("discord-zig").intents;

test "intents default fallback" {
    var s = Session.init(std.testing.allocator, std.testing.io, .{ .token = "x" });
    defer s.deinit();
    try std.testing.expectEqual(intents.defaults(), s.intentsOrDefault());
    var custom = Session.init(std.testing.allocator, std.testing.io, .{ .token = "x", .intents = intents.guilds });
    defer custom.deinit();
    try std.testing.expectEqual(intents.guilds, custom.intentsOrDefault());
}

test "track dispatch seq" {
    var s = Session.init(std.testing.allocator, std.testing.io, .{ .token = "x" });
    defer s.deinit();
    s.trackDispatch(42);
    try std.testing.expectEqual(@as(?i64, 42), s.seq);
    s.trackDispatch(null);
    try std.testing.expectEqual(@as(?i64, 42), s.seq);
}

test "identify payload contains token" {
    var s = Session.init(std.testing.allocator, std.testing.io, .{ .token = "abc", .intents = 513 });
    defer s.deinit();
    const payload = try s.identifyPayload(std.testing.allocator);
    defer std.testing.allocator.free(payload);
    try std.testing.expect(std.mem.indexOf(u8, payload, "abc") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "513") != null);
}

test "clearResume drops session state" {
    var s = Session.init(std.testing.allocator, std.testing.io, .{ .token = "x" });
    defer s.deinit();
    try s.storeReady("s1", "wss://x");
    s.trackDispatch(7);
    try std.testing.expect(s.session_id != null);
    s.clearResume();
    try std.testing.expect(s.session_id == null);
    try std.testing.expect(s.resume_url == null);
    try std.testing.expect(s.seq == null);
    try std.testing.expectError(error.MissingSession, s.resumePayload(std.testing.allocator));
}
