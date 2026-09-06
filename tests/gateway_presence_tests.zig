const std = @import("std");
const discord = @import("discord-zig");

test "gateway opcodes and presence encoding" {
    const allocator = std.testing.allocator;
    const GatewayOpcodes = discord.GatewayOpcodes;

    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(GatewayOpcodes.Dispatch));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(GatewayOpcodes.Heartbeat));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(GatewayOpcodes.Identify));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(GatewayOpcodes.PresenceUpdate));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(GatewayOpcodes.Resume));

    const presence_json = try discord.gateway.encodePresenceUpdate(allocator, .{
        .activities = &[_]discord.gateway.Activity{.{
            .name = "Playing Zig",
            .type = .Playing,
        }},
        .status = .online,
    });
    defer allocator.free(presence_json);

    try std.testing.expect(std.mem.indexOf(u8, presence_json, "\"op\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, presence_json, "\"name\":\"Playing Zig\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, presence_json, "\"status\":\"online\"") != null);

    const identify_sharded = try discord.gateway.encodeIdentifyFull(allocator, "my-token", 513, .{ 0, 4 }, .{
        .activities = &[_]discord.gateway.Activity{.{
            .name = "Bot Shard 0",
            .type = .Custom,
        }},
        .status = .dnd,
    });
    defer allocator.free(identify_sharded);

    try std.testing.expect(std.mem.indexOf(u8, identify_sharded, "\"shard\":[0,4]") != null);
    try std.testing.expect(std.mem.indexOf(u8, identify_sharded, "\"status\":\"dnd\"") != null);
}

test "audio stream worker prepares packets" {
    const allocator = std.testing.allocator;
    const key = [_]u8{0x55} ** 32;

    var player = discord.voice.AudioPlayer.init(1234, key);
    var worker = discord.voice.AudioStreamWorker.init(&player);

    const frame = try worker.prepareFrame(allocator, "opus-payload");
    defer allocator.free(frame);

    try std.testing.expect(frame.len > 12);
    try std.testing.expectEqual(@as(u16, 1), player.sequence);

    const silence = try worker.prepareSilence(allocator);
    defer allocator.free(silence);
    try std.testing.expectEqual(@as(u16, 2), player.sequence);
}

test "schema entitlement and entitlement types" {
    const EntitlementType = discord.EntitlementType;
    try std.testing.expectEqual(@as(u8, 8), @intFromEnum(EntitlementType.ApplicationSubscription));

    const ent = discord.Entitlement{
        .id = "ent1",
        .sku_id = "sku1",
        .application_id = "app1",
        .user_id = "u1",
        .type = 8,
    };
    try std.testing.expectEqualStrings("ent1", ent.id);
    try std.testing.expectEqualStrings("sku1", ent.sku_id);
}
