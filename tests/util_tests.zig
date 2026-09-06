const std = @import("std");
const util = @import("discord-zig").util;

test "backoff caps" {
    try std.testing.expectEqual(@as(u64, 1000), util.backoffMs(0));
    try std.testing.expectEqual(@as(u64, 2000), util.backoffMs(1));
    try std.testing.expectEqual(@as(u64, 30000), util.backoffMs(20));
}

test "get header case insensitive" {
    const raw = "HTTP/1.1 429 Too Many Requests\r\nRetry-After: 64.57\r\nX-RateLimit-Global: true\r\n\r\n";
    try std.testing.expectEqualStrings("64.57", util.getHeader(raw, "retry-after").?);
    try std.testing.expectEqualStrings("true", util.getHeader(raw, "x-ratelimit-global").?);
    try std.testing.expect(util.getHeader(raw, "missing") == null);
}

test "encode emoji for reaction paths" {
    const fire = try util.encodeEmoji(std.testing.allocator, "🔥");
    defer std.testing.allocator.free(fire);
    try std.testing.expectEqualStrings("%F0%9F%94%A5", fire);

    const custom = try util.encodeEmoji(std.testing.allocator, "party:123");
    defer std.testing.allocator.free(custom);
    try std.testing.expectEqualStrings("party%3A123", custom);

    const plain = try util.encodeEmoji(std.testing.allocator, "abc-_.~");
    defer std.testing.allocator.free(plain);
    try std.testing.expectEqualStrings("abc-_.~", plain);
}
