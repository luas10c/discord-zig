const std = @import("std");
const schema = @import("discord-zig").schema;

test "parse user ignores unknown fields" {
    const body =
        \\{"id":"80351110224678912","username":"Nelly","extra":"drop","bot":true}
    ;
    var parsed = try schema.parse(schema.User, std.testing.allocator, body);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("80351110224678912", parsed.value.id);
    try std.testing.expectEqualStrings("Nelly", parsed.value.username);
    try std.testing.expect(parsed.value.bot);
}

test "parse message with author" {
    const body =
        \\{"id":"1","channel_id":"2","author":{"id":"3","username":"bot"},"content":"hi"}
    ;
    var parsed = try schema.parse(schema.Message, std.testing.allocator, body);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("hi", parsed.value.content);
    try std.testing.expectEqualStrings("bot", parsed.value.author.username);
}

test "parse message flags" {
    const body =
        \\{"id":"1","channel_id":"2","author":{"id":"3","username":"bot"},"content":"hi","flags":64}
    ;
    var parsed = try schema.parse(schema.Message, std.testing.allocator, body);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 64), parsed.value.flags);

    const plain =
        \\{"id":"1","channel_id":"2","author":{"id":"3","username":"bot"},"content":"hi"}
    ;
    var fallback = try schema.parse(schema.Message, std.testing.allocator, plain);
    defer fallback.deinit();
    try std.testing.expectEqual(@as(u32, 0), fallback.value.flags);
}

test "stringify create message body" {
    const body = try schema.stringify(std.testing.allocator, .{ .content = "hi" });
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"content\":\"hi\"}", body);
}

test "parse ready" {
    const body =
        \\{"session_id":"abc","resume_gateway_url":"wss://x","user":{"id":"1","username":"bot"},"extra":1}
    ;
    var parsed = try schema.parse(schema.Ready, std.testing.allocator, body);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("abc", parsed.value.session_id);
    try std.testing.expectEqualStrings("wss://x", parsed.value.resume_gateway_url);
    try std.testing.expectEqualStrings("bot", parsed.value.user.username);
}

test "user tag formats like discord.js" {
    const user = schema.User{ .id = "1", .username = "bot", .discriminator = "1234" };
    const t = try user.tag(std.testing.allocator);
    defer std.testing.allocator.free(t);
    try std.testing.expectEqualStrings("bot#1234", t);
}

test "parse interaction with type field" {
    const body =
        \\{"id":"1","application_id":"2","type":2,"token":"t","version":1}
    ;
    var parsed = try schema.parse(schema.Interaction, std.testing.allocator, body);
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u8, 2), parsed.value.@"type");
    try std.testing.expectEqualStrings("t", parsed.value.token);
}

test "parse custom and unicode reaction" {
    const custom =
        \\{"user_id":"7","channel_id":"9","message_id":"42","guild_id":"100","emoji":{"id":"123","name":"party","animated":true},"burst":false}
    ;
    var a = try schema.parse(schema.MessageReaction, std.testing.allocator, custom);
    defer a.deinit();
    try std.testing.expectEqualStrings("123", a.value.emoji.id.?);
    try std.testing.expectEqualStrings("party", a.value.emoji.name.?);
    try std.testing.expect(a.value.emoji.animated);
    try std.testing.expectEqualStrings("100", a.value.guild_id.?);

    const unicode =
        \\{"user_id":"7","channel_id":"9","message_id":"42","emoji":{"id":null,"name":"🔥"}}
    ;
    var b = try schema.parse(schema.MessageReaction, std.testing.allocator, unicode);
    defer b.deinit();
    try std.testing.expect(b.value.emoji.id == null);
    try std.testing.expectEqualStrings("🔥", b.value.emoji.name.?);
    try std.testing.expect(b.value.guild_id == null);
}

test "parse reaction remove payloads" {
    var all = try schema.parse(
        schema.ReactionRemoveAll,
        std.testing.allocator,
        "{\"channel_id\":\"9\",\"message_id\":\"42\"}",
    );
    defer all.deinit();
    try std.testing.expectEqualStrings("42", all.value.message_id);

    var one = try schema.parse(
        schema.ReactionRemoveEmoji,
        std.testing.allocator,
        "{\"channel_id\":\"9\",\"message_id\":\"42\",\"emoji\":{\"name\":\"🔥\"}}",
    );
    defer one.deinit();
    try std.testing.expectEqualStrings("🔥", one.value.emoji.name.?);
}

test "channel type key maps to channel_type" {
    var text = try schema.parse(schema.Channel, std.testing.allocator, "{\"id\":\"20\",\"type\":0,\"name\":\"general\"}");
    defer text.deinit();
    try std.testing.expectEqual(schema.ChannelType.guild_text, text.value.channel_type);
    try std.testing.expectEqualStrings("general", text.value.name.?);

    var voice = try schema.parse(schema.Channel, std.testing.allocator, "{\"id\":\"21\",\"type\":2}");
    defer voice.deinit();
    try std.testing.expectEqual(schema.ChannelType.guild_voice, voice.value.channel_type);

    var legacy = try schema.parse(schema.Channel, std.testing.allocator, "{\"id\":\"22\",\"channel_type\":1}");
    defer legacy.deinit();
    try std.testing.expectEqual(schema.ChannelType.dm, legacy.value.channel_type);
}

test "channel permission overwrites parse" {
    var parsed = try schema.parse(schema.Channel, std.testing.allocator, "{\"id\":\"20\",\"type\":0,\"permission_overwrites\":[{\"id\":\"10\",\"type\":0,\"allow\":\"1024\",\"deny\":\"0\"},{\"id\":\"5\",\"type\":1,\"allow\":\"0\",\"deny\":\"2048\"}]}");
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.permission_overwrites.len);
    try std.testing.expectEqualStrings("10", parsed.value.permission_overwrites[0].id);
    try std.testing.expectEqual(@as(u8, 0), parsed.value.permission_overwrites[0].@"type");
    try std.testing.expectEqualStrings("1024", parsed.value.permission_overwrites[0].allow);
    try std.testing.expectEqualStrings("2048", parsed.value.permission_overwrites[1].deny);
}

test "parse partial message update without author" {
    const body =
        \\{"id":"123","channel_id":"456","guild_id":"789","embeds":[]}
    ;
    var parsed = try schema.parse(schema.Message, std.testing.allocator, body);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("123", parsed.value.id);
    try std.testing.expectEqualStrings("456", parsed.value.channel_id);
    try std.testing.expectEqualStrings("789", parsed.value.guild_id.?);
    try std.testing.expectEqualStrings("", parsed.value.author.id);
    try std.testing.expectEqualStrings("", parsed.value.author.username);
}

test "parse partial user role attachment" {
    var u = try schema.parse(schema.User, std.testing.allocator, "{}");
    defer u.deinit();
    try std.testing.expectEqualStrings("", u.value.id);

    var r = try schema.parse(schema.Role, std.testing.allocator, "{}");
    defer r.deinit();
    try std.testing.expectEqualStrings("", r.value.id);

    var a = try schema.parse(schema.Attachment, std.testing.allocator, "{}");
    defer a.deinit();
    try std.testing.expectEqualStrings("", a.value.id);
}

