const std = @import("std");
const cache_mod = @import("discord-zig").cache;
const events = @import("discord-zig").events;
const snowflake = @import("discord-zig").snowflake;

fn feed(cache: *cache_mod.Cache, t: events.Type, body: []const u8) !void {
    return feedWith(std.testing.allocator, cache, t, body);
}

fn feedWith(allocator: std.mem.Allocator, cache: *cache_mod.Cache, t: events.Type, body: []const u8) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
    defer parsed.deinit();
    try cache.update(t, parsed.value);
}

fn messageJson(allocator: std.mem.Allocator, id: []const u8) ![]u8 {
    return std.fmt.allocPrint(allocator,
        \\{{"id":"{s}","channel_id":"9","author":{{"id":"7","username":"u"}},"content":"hi"}}
    , .{id});
}

test "default limits" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    try std.testing.expectEqual(@as(?usize, 200), c.limits.messages);
    try std.testing.expect(c.limits.guild_members == null);
    try std.testing.expect(c.limits.guilds == null);
}

test "limits literal like cacheWithLimits" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{ .guild_members = 12000, .messages = 50 });
    defer c.deinit();
    try std.testing.expectEqual(@as(?usize, 12000), c.limits.guild_members);
    try std.testing.expectEqual(@as(?usize, 50), c.limits.messages);
}

test "message put and get" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    const body = try messageJson(std.testing.allocator, "111");
    defer std.testing.allocator.free(body);
    try feed(&c, .message_create, body);
    const got = c.messages.get(111) orelse return error.MissingEntry;
    try std.testing.expectEqualStrings("hi", got.content);
    try std.testing.expectEqual(@as(usize, 1), c.counts().messages);
}

test "fifo eviction drops oldest" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{ .messages = 2 });
    defer c.deinit();
    for ([_] []const u8{ "1", "2", "3" }) |id| {
        const body = try messageJson(std.testing.allocator, id);
        defer std.testing.allocator.free(body);
        try feed(&c, .message_create, body);
    }
    try std.testing.expect(c.messages.get(1) == null);
    try std.testing.expect(c.messages.get(2) != null);
    try std.testing.expect(c.messages.get(3) != null);
}

test "update refreshes recency" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{ .messages = 2 });
    defer c.deinit();
    for ([_] []const u8{ "1", "2" }) |id| {
        const body = try messageJson(std.testing.allocator, id);
        defer std.testing.allocator.free(body);
        try feed(&c, .message_create, body);
    }
    const again = try messageJson(std.testing.allocator, "1");
    defer std.testing.allocator.free(again);
    try feed(&c, .message_update, again);
    const third = try messageJson(std.testing.allocator, "3");
    defer std.testing.allocator.free(third);
    try feed(&c, .message_create, third);
    try std.testing.expect(c.messages.get(1) != null);
    try std.testing.expect(c.messages.get(2) == null);
    try std.testing.expect(c.messages.get(3) != null);
}

test "delete removes entry" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    const body = try messageJson(std.testing.allocator, "42");
    defer std.testing.allocator.free(body);
    try feed(&c, .message_create, body);
    try feed(&c, .message_delete, "{\"id\":\"42\",\"channel_id\":\"9\"}");
    try std.testing.expect(c.messages.get(42) == null);
    try feed(&c, .message_delete, "{\"channel_id\":\"9\"}");
}

test "member add get and remove" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    try feed(&c, .guild_member_add, "{\"guild_id\":\"100\",\"user\":{\"id\":\"7\",\"username\":\"u\"},\"nick\":\"n\"}");
    const key = cache_mod.memberKey(100, 7);
    const got = c.members.get(key) orelse return error.MissingEntry;
    try std.testing.expectEqualStrings("n", got.nick.?);
    try std.testing.expectEqual(@as(u64, 100), cache_mod.memberKeyGuild(key));
    try std.testing.expectEqual(@as(u64, 7), cache_mod.memberKeyUser(key));
    try feed(&c, .guild_member_remove, "{\"guild_id\":\"100\",\"user\":{\"id\":\"7\"}}");
    try std.testing.expect(c.members.get(key) == null);
}

test "setLimits shrinks store" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    for ([_] []const u8{ "1", "2", "3" }) |id| {
        const body = try messageJson(std.testing.allocator, id);
        defer std.testing.allocator.free(body);
        try feed(&c, .message_create, body);
    }
    try std.testing.expectEqual(@as(usize, 3), c.counts().messages);
    c.setLimits(.{ .messages = 1 });
    try std.testing.expectEqual(@as(usize, 1), c.counts().messages);
    try std.testing.expect(c.messages.get(3) != null);
}

test "sweep keeps matching entries" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    try feed(&c, .message_create, "{\"id\":\"1\",\"channel_id\":\"9\",\"author\":{\"id\":\"7\",\"username\":\"u\",\"bot\":true},\"content\":\"b\"}");
    const human = try messageJson(std.testing.allocator, "2");
    defer std.testing.allocator.free(human);
    try feed(&c, .message_create, human);
    const Ctx = struct {};
    const keep_bots = struct {
        fn f(_: Ctx, msg: *const @import("discord-zig").schema.Message) bool {
            return msg.author.bot;
        }
    }.f;
    const removed = c.messages.sweep(Ctx{}, keep_bots);
    try std.testing.expectEqual(@as(usize, 1), removed);
    try std.testing.expect(c.messages.get(1) != null);
    try std.testing.expect(c.messages.get(2) == null);
}

test "sweepMessagesOlderThan uses snowflake time" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    const now: u64 = 1700000000000;
    const old_id = snowflake.Snowflake.fromTimestampMs(now - 100_000).value;
    const new_id = snowflake.Snowflake.fromTimestampMs(now - 1_000).value;
    var buf: [32]u8 = undefined;
    const old_text = try std.fmt.bufPrint(&buf, "{d}", .{old_id});
    const old_body = try messageJson(std.testing.allocator, old_text);
    defer std.testing.allocator.free(old_body);
    try feed(&c, .message_create, old_body);
    var buf2: [32]u8 = undefined;
    const new_text = try std.fmt.bufPrint(&buf2, "{d}", .{new_id});
    const new_body = try messageJson(std.testing.allocator, new_text);
    defer std.testing.allocator.free(new_body);
    try feed(&c, .message_create, new_body);
    const removed = c.sweepMessagesOlderThan(now, 10_000);
    try std.testing.expectEqual(@as(usize, 1), removed);
    try std.testing.expect(c.messages.get(old_id) == null);
    try std.testing.expect(c.messages.get(new_id) != null);
}

test "bad data is skipped without error" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    try feed(&c, .message_create, "{\"channel_id\":\"9\"}");
    try feed(&c, .unknown, "{\"id\":\"1\"}");
    try feed(&c, .guild_member_add, "{\"nick\":\"n\"}");
    const counts = c.counts();
    try std.testing.expectEqual(@as(usize, 0), counts.messages);
    try std.testing.expectEqual(@as(usize, 0), counts.members);
}

test "clear empties everything" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    const body = try messageJson(std.testing.allocator, "5");
    defer std.testing.allocator.free(body);
    try feed(&c, .message_create, body);
    try feed(&c, .guild_member_add, "{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"}}");
    c.clear();
    const counts = c.counts();
    try std.testing.expectEqual(@as(usize, 0), counts.messages);
    try std.testing.expectEqual(@as(usize, 0), counts.members);
}

test "roles threads emojis update and remove" {
    var c = cache_mod.Cache.init(std.testing.allocator, .{});
    defer c.deinit();
    try feed(&c, .guild_role_create, "{\"id\":\"11\",\"name\":\"mod\",\"permissions\":\"6\"}");
    try feed(&c, .thread_create, "{\"id\":\"22\",\"type\":11,\"guild_id\":\"1\",\"name\":\"t\"}");
    try feed(&c, .guild_emojis_update, "{\"guild_id\":\"1\",\"emojis\":[{\"id\":\"33\",\"name\":\"fire\"},{\"name\":\"🔥\"}]}");
    try std.testing.expectEqual(@as(usize, 1), c.counts().roles);
    try std.testing.expectEqual(@as(usize, 1), c.counts().threads);
    try std.testing.expectEqual(@as(usize, 1), c.counts().emojis);
    try std.testing.expectEqualStrings("mod", c.roles.get(11).?.name);
    try feed(&c, .guild_role_delete, "{\"guild_id\":\"1\",\"role_id\":\"11\"}");
    try feed(&c, .thread_delete, "{\"id\":\"22\",\"channel_id\":\"9\"}");
    try std.testing.expectEqual(@as(usize, 0), c.counts().roles);
    try std.testing.expectEqual(@as(usize, 0), c.counts().threads);
    try std.testing.expectEqual(@as(usize, 1), c.counts().emojis);
}

test "no leaks across put evict remove sweep clear" {
    var gpa: std.heap.DebugAllocator(.{}) = .init;
    const allocator = gpa.allocator();
    {
        var c = cache_mod.Cache.init(allocator, .{ .messages = 2, .guild_members = 1 });
        for ([_] []const u8{ "1", "2", "3" }) |id| {
            const body = try messageJson(allocator, id);
            defer allocator.free(body);
            try feedWith(allocator, &c, .message_create, body);
        }
        try feedWith(allocator, &c, .guild_member_add, "{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"}}");
        try feedWith(allocator, &c, .guild_member_add, "{\"guild_id\":\"1\",\"user\":{\"id\":\"3\",\"username\":\"v\"}}");
        try feedWith(allocator, &c, .message_delete, "{\"id\":\"2\",\"channel_id\":\"9\"}");
        _ = c.sweepMessagesOlderThan(1700000000000, 60_000);
        c.setLimits(.{});
        c.clear();
        c.deinit();
    }
    try std.testing.expect(gpa.deinit() == .ok);
}

test "collection functional methods filter map partition every some" {
    const allocator = std.testing.allocator;
    var c = cache_mod.Cache.init(allocator, .{});
    defer c.deinit();

    const m1 = try messageJson(allocator, "10");
    defer allocator.free(m1);
    try feed(&c, .message_create, m1);

    const m2 = try messageJson(allocator, "20");
    defer allocator.free(m2);
    try feed(&c, .message_create, m2);

    var filtered = try c.messages.filter(allocator, @as(u64, 15), struct {
        fn pred(threshold: u64, msg: *const @import("discord-zig").schema.Message) bool {
            const id_val = std.fmt.parseInt(u64, msg.id, 10) catch 0;
            return id_val > threshold;
        }
    }.pred);
    defer filtered.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), filtered.items.len);
    try std.testing.expectEqualStrings("20", filtered.items[0].id);

    var mapped = try c.messages.map(allocator, []const u8, {}, struct {
        fn trans(_: void, msg: *const @import("discord-zig").schema.Message) []const u8 {
            return msg.id;
        }
    }.trans);
    defer mapped.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), mapped.items.len);

    var part = try c.messages.partition(allocator, @as(u64, 15), struct {
        fn pred(threshold: u64, msg: *const @import("discord-zig").schema.Message) bool {
            const id_val = std.fmt.parseInt(u64, msg.id, 10) catch 0;
            return id_val > threshold;
        }
    }.pred);
    defer part.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 1), part.matches.items.len);
    try std.testing.expectEqual(@as(usize, 1), part.non_matches.items.len);

    const has_hi = c.messages.every({}, struct {
        fn pred(_: void, msg: *const @import("discord-zig").schema.Message) bool {
            return std.mem.eql(u8, msg.content, "hi");
        }
    }.pred);
    try std.testing.expect(has_hi);

    const some_twenty = c.messages.some({}, struct {
        fn pred(_: void, msg: *const @import("discord-zig").schema.Message) bool {
            return std.mem.eql(u8, msg.id, "20");
        }
    }.pred);
    try std.testing.expect(some_twenty);
}
