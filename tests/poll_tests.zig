const std = @import("std");
const poll = @import("discord-zig").poll;

test "poll builder json" {
    var b = poll.Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.setQuestion("Best?");
    try b.addAnswer(.{ .text = "A" });
    try b.addAnswer(.{ .text = "B", .emoji_name = "🔥" });
    b.setDurationHours(24);
    const built = try b.build();
    const body = try poll.createBody(std.testing.allocator, built);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"poll\":{\"question\":{\"text\":\"Best?\"},\"answers\":[{\"poll_media\":{\"text\":\"A\"}},{\"poll_media\":{\"text\":\"B\",\"emoji\":{\"name\":\"🔥\"}}}],\"duration\":24,\"allow_multiselect\":false,\"layout_type\":1}}", body);
}

test "poll builder validation" {
    var empty = poll.Builder.init(std.testing.allocator);
    defer empty.deinit();
    try std.testing.expectError(error.MissingQuestion, empty.build());

    try empty.setQuestion("Q");
    try std.testing.expectError(error.NoAnswers, empty.build());

    var many = poll.Builder.init(std.testing.allocator);
    defer many.deinit();
    try many.setQuestion("Q");
    var i: usize = 0;
    while (i < 11) : (i += 1) {
        try many.addAnswer(.{ .text = "x" });
    }
    try std.testing.expectError(error.TooManyAnswers, many.build());

    var bad_duration = poll.Builder.init(std.testing.allocator);
    defer bad_duration.deinit();
    try bad_duration.setQuestion("Q");
    try bad_duration.addAnswer(.{ .text = "x" });
    bad_duration.setDurationHours(0);
    try std.testing.expectError(error.BadDuration, bad_duration.build());
}

test "poll builder with custom emoji" {
    const allocator = std.testing.allocator;
    var b = poll.Builder.init(allocator);
    defer b.deinit();
    try b.setQuestion("Emoji test?");
    try b.addAnswer(.{ .text = "Custom", .emoji_name = "pepe", .emoji_id = "123456789" });
    const built = try b.build();
    const body = try poll.createBody(allocator, built);
    defer allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"emoji\":{\"id\":\"123456789\",\"name\":\"pepe\"}") != null);
}

test "message with poll schema parsing and helpers" {
    const allocator = std.testing.allocator;
    const discord = @import("discord-zig");
    const json_msg =
        \\{
        \\  "id": "100",
        \\  "channel_id": "200",
        \\  "author": {"id": "1", "username": "bot"},
        \\  "content": "Check this poll",
        \\  "poll": {
        \\    "question": {"text": "Best editor?"},
        \\    "answers": [
        \\      {"answer_id": 1, "poll_media": {"text": "Neovim"}},
        \\      {"answer_id": 2, "poll_media": {"text": "VSCode", "emoji": {"name": "💻"}}}
        \\    ],
        \\    "expiry": "2026-12-31T23:59:59.000Z",
        \\    "allow_multiselect": true,
        \\    "layout_type": 1,
        \\    "results": {
        \\      "is_finalized": false,
        \\      "answer_counts": [
        \\        {"id": 1, "count": 10, "me_voted": true},
        \\        {"id": 2, "count": 5, "me_voted": false}
        \\      ]
        \\    }
        \\  }
        \\}
    ;
    var parsed = try discord.schema.parse(discord.schema.Message, allocator, json_msg);
    defer parsed.deinit();
    const msg = parsed.value;
    try std.testing.expectEqualStrings("100", msg.id);
    try std.testing.expect(msg.poll != null);

    const p = msg.poll.?;
    try std.testing.expectEqualStrings("Best editor?", p.question.text.?);
    try std.testing.expectEqual(@as(usize, 2), p.answers.len);
    try std.testing.expectEqual(true, p.allow_multiselect);
    try std.testing.expectEqualStrings("2026-12-31T23:59:59.000Z", p.expiry.?);

    // Test totalVotes helper
    try std.testing.expectEqual(@as(u64, 15), p.totalVotes());

    // Test getAnswer helper
    const a1 = p.getAnswer(1).?;
    try std.testing.expectEqualStrings("Neovim", a1.poll_media.text.?);
    const a2 = p.getAnswer(2).?;
    try std.testing.expectEqualStrings("VSCode", a2.poll_media.text.?);
    try std.testing.expectEqualStrings("💻", a2.poll_media.emoji.?.name.?);
    try std.testing.expect(p.getAnswer(99) == null);
}
