const std = @import("std");
const discord = @import("discord-zig");

test "interaction collector matches custom_id, max, and handles interactions" {
    const allocator = std.testing.allocator;

    var collector = discord.InteractionCollector.init(allocator, .{
        .custom_id = "btn_click",
        .max = 2,
    }, 1000);

    var inter1: discord.schema.Interaction = .{
        .id = "i1",
        .application_id = "app1",
        .data = .{
            .custom_id = "btn_click",
        },
    };

    const inter_other: discord.schema.Interaction = .{
        .id = "i2",
        .application_id = "app1",
        .data = .{
            .custom_id = "btn_different",
        },
    };

    try std.testing.expectEqual(false, collector.handleInteraction(inter_other, 1050));
    try std.testing.expectEqual(@as(u32, 0), collector.collected_count);
    try std.testing.expectEqual(false, collector.ended);

    try std.testing.expectEqual(true, collector.handleInteraction(inter1, 1100));
    try std.testing.expectEqual(@as(u32, 1), collector.collected_count);
    try std.testing.expectEqual(false, collector.ended);

    inter1.id = "i3";
    try std.testing.expectEqual(true, collector.handleInteraction(inter1, 1200));
    try std.testing.expectEqual(@as(u32, 2), collector.collected_count);
    try std.testing.expectEqual(true, collector.ended);
    try std.testing.expectEqualStrings("limit", collector.end_reason);
}

test "interaction collector handles timeout" {
    const allocator = std.testing.allocator;

    var collector = discord.InteractionCollector.init(allocator, .{
        .time_ms = 5000,
    }, 1000);

    try std.testing.expectEqual(false, collector.checkExpired(3000));
    try std.testing.expectEqual(false, collector.ended);

    try std.testing.expectEqual(true, collector.checkExpired(6001));
    try std.testing.expectEqual(true, collector.ended);
    try std.testing.expectEqualStrings("time", collector.end_reason);
}
