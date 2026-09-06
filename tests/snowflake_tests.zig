const std = @import("std");
const Snowflake = @import("discord-zig").snowflake.Snowflake;

test "parse and timestamp" {
    const s = try Snowflake.parse("175928847299117063");
    try std.testing.expectEqual(@as(u64, 175928847299117063), s.value);
    try std.testing.expectEqual(@as(u64, 1462015105796), s.timestampMs());
    try std.testing.expectEqual(@as(u12, 7), s.increment());
}

test "from timestamp roundtrip" {
    const s = Snowflake.fromTimestampMs(1462015105796);
    try std.testing.expectEqual(@as(u64, 1462015105796), s.timestampMs());
}

test "format" {
    const s = Snowflake.fromValue(80351110224678912);
    var out: std.Io.Writer.Allocating = .init(std.testing.allocator);
    defer out.deinit();
    try s.format(&out.writer);
    try std.testing.expectEqualStrings("80351110224678912", out.written());
}
