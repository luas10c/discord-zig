const std = @import("std");
const gateway = @import("discord-zig").gateway;

test "op mapping" {
    try std.testing.expectEqual(gateway.Op.dispatch, gateway.Op.fromInt(0));
    try std.testing.expectEqual(gateway.Op.hello, gateway.Op.fromInt(10));
    try std.testing.expectEqual(gateway.Op.heartbeat_ack, gateway.Op.fromInt(11));
}

test "decode dispatch" {
    var parsed = try gateway.decode(std.testing.allocator, "{\"op\":0,\"d\":{},\"s\":42,\"t\":\"READY\"}");
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u8, 0), parsed.value.op);
    try std.testing.expectEqual(@as(?i64, 42), parsed.value.s);
    try std.testing.expectEqualStrings("READY", parsed.value.t.?);
}

test "encode heartbeat" {
    const owned = try gateway.encodeHeartbeat(std.testing.allocator, 42);
    defer std.testing.allocator.free(owned);
    try std.testing.expectEqualStrings("{\"op\":1,\"d\":42}", owned);
    const null_owned = try gateway.encodeHeartbeat(std.testing.allocator, null);
    defer std.testing.allocator.free(null_owned);
    try std.testing.expectEqualStrings("{\"op\":1,\"d\":null}", null_owned);
}

test "parse hello" {
    const interval = try gateway.parseHello(std.testing.allocator, "{\"op\":10,\"d\":{\"heartbeat_interval\":45000}}");
    try std.testing.expectEqual(@as(u64, 45000), interval);
}

test "close code resume" {
    try std.testing.expect(!gateway.canResume(1000));
    try std.testing.expect(gateway.canResume(4000));
}

test "close code names" {
    try std.testing.expectEqualStrings("Authentication Failed", gateway.closeCodeName(4004));
    try std.testing.expectEqualStrings("Disallowed Intents", gateway.closeCodeName(4014));
    try std.testing.expectEqualStrings("Unknown", gateway.closeCodeName(4999));
}

test "parse gateway url" {
    const wss = gateway.parseGatewayUrl("wss://gateway.discord.gg/?v=10&encoding=json").?;
    try std.testing.expectEqualStrings("gateway.discord.gg", wss.host);
    try std.testing.expectEqual(@as(u16, 443), wss.port);
    try std.testing.expectEqualStrings("/?v=10&encoding=json", wss.path);
    try std.testing.expect(wss.tls);

    const ws = gateway.parseGatewayUrl("ws://127.0.0.1:18671/").?;
    try std.testing.expectEqualStrings("127.0.0.1", ws.host);
    try std.testing.expectEqual(@as(u16, 18671), ws.port);
    try std.testing.expectEqualStrings("/", ws.path);
    try std.testing.expect(!ws.tls);

    try std.testing.expect(gateway.parseGatewayUrl("https://example.com/") == null);
    try std.testing.expect(gateway.parseGatewayUrl("wss://") == null);
    try std.testing.expect(gateway.parseGatewayUrl("wss://host:notaport/") == null);
}

test "encode request guild members" {
    const body = try gateway.encodeRequestGuildMembers(std.testing.allocator, "10", "", 0);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"op\":8,\"d\":{\"guild_id\":\"10\",\"query\":\"\",\"limit\":0}}", body);

    const query = try gateway.encodeRequestGuildMembers(std.testing.allocator, "10", "ab", 5);
    defer std.testing.allocator.free(query);
    try std.testing.expectEqualStrings("{\"op\":8,\"d\":{\"guild_id\":\"10\",\"query\":\"ab\",\"limit\":5}}", query);
}
