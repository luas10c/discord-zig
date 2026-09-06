const std = @import("std");
const embed_mod = @import("discord-zig").embed;
const schema = @import("discord-zig").schema;

test "full chain build" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.setTitle("Novidades");
    try b.setDescription("corpo");
    try b.setUrl("https://x.test");
    b.setColor(0x5865F2);
    try b.setAuthor("autor", null, null);
    try b.setFooter("rodapé", null);
    try b.setImage("https://x.test/i.png");
    try b.setThumbnail("https://x.test/t.png");
    try b.setTimestamp("2026-01-01T00:00:00.000Z");
    try b.addField("Regra 1", "Seja legal", true);
    const e = try b.build();
    try std.testing.expectEqualStrings("Novidades", e.title.?);
    try std.testing.expectEqual(@as(u32, 0x5865F2), e.color.?);
    try std.testing.expectEqualStrings("autor", e.author.?.name);
    try std.testing.expectEqualStrings("rodapé", e.footer.?.text);
    try std.testing.expectEqual(@as(usize, 1), e.fields.len);
    try std.testing.expect(e.fields[0].@"inline");
}

test "title too long" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.setTitle("a" ** 257);
    try std.testing.expectError(error.TitleTooLong, b.build());
}

test "description too long" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.setDescription("a" ** 4097);
    try std.testing.expectError(error.DescriptionTooLong, b.build());
}

test "too many fields" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    var i: usize = 0;
    while (i < 26) : (i += 1) try b.addField("n", "v", false);
    try std.testing.expectError(error.TooManyFields, b.build());
}

test "field limits" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.addField("a" ** 257, "v", false);
    try std.testing.expectError(error.FieldNameTooLong, b.build());

    var c = embed_mod.Builder.init(std.testing.allocator);
    defer c.deinit();
    try c.addField("n", "a" ** 1025, false);
    try std.testing.expectError(error.FieldValueTooLong, c.build());
}

test "footer and author limits" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.setFooter("a" ** 2049, null);
    try std.testing.expectError(error.FooterTooLong, b.build());

    var c = embed_mod.Builder.init(std.testing.allocator);
    defer c.deinit();
    try c.setAuthor("a" ** 257, null, null);
    try std.testing.expectError(error.AuthorNameTooLong, c.build());
}

test "total over 6000" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    var i: usize = 0;
    while (i < 6) : (i += 1) try b.addField("n", "a" ** 1024, false);
    try std.testing.expectError(error.EmbedTooLarge, b.build());
}

test "setFields replaces" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.addField("old", "x", false);
    try b.setFields(&.{.{ .name = "a", .value = "1" }, .{ .name = "b", .value = "2", .@"inline" = true }});
    const e = try b.build();
    try std.testing.expectEqual(@as(usize, 2), e.fields.len);
    try std.testing.expectEqualStrings("a", e.fields[0].name);
    try std.testing.expect(e.fields[1].@"inline");
}

test "embedLength sums text" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.setTitle("ab");
    try b.setDescription("cde");
    try b.addField("f", "gh", false);
    const e = try b.build();
    try std.testing.expectEqual(@as(usize, 8), embed_mod.embedLength(e));
}

test "json shape" {
    var b = embed_mod.Builder.init(std.testing.allocator);
    defer b.deinit();
    b.setColor(255);
    try b.addField("n", "v", true);
    const e = try b.build();
    const body = try schema.stringify(std.testing.allocator, e);
    defer std.testing.allocator.free(body);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"color\":255") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"inline\":true") != null);
}

test "no leaks on build and deinit" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    {
        var b = embed_mod.Builder.init(allocator);
        try b.setTitle("t");
        try b.addField("n", "v", false);
        _ = try b.build();
        b.deinit();
    }
    try std.testing.expect(gpa.deinit() == .ok);
}
