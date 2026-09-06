const std = @import("std");
const discord = @import("discord-zig");

test "rtp header encode and decode" {
    const header = discord.voice.RtpHeader{
        .version = 0x80,
        .payload_type = 120,
        .sequence = 12345,
        .timestamp = 987654,
        .ssrc = 42,
    };

    var bytes: [12]u8 = undefined;
    header.encode(&bytes);

    const decoded = discord.voice.RtpHeader.decode(&bytes);
    try std.testing.expectEqual(header.version, decoded.version);
    try std.testing.expectEqual(header.payload_type, decoded.payload_type);
    try std.testing.expectEqual(header.sequence, decoded.sequence);
    try std.testing.expectEqual(header.timestamp, decoded.timestamp);
    try std.testing.expectEqual(header.ssrc, decoded.ssrc);
}

test "voice encryptor roundtrip with secretbox xsalsa20_poly1305" {
    const allocator = std.testing.allocator;
    const key = [_]u8{0x42} ** 32;

    const header = discord.voice.RtpHeader{
        .version = 0x80,
        .payload_type = 120,
        .sequence = 1,
        .timestamp = 960,
        .ssrc = 1001,
    };

    const opus_data = "raw-opus-audio-frame-data-bytes";
    const packet = try discord.voice.VoiceEncryptor.encryptPacket(allocator, header, opus_data, key);
    defer allocator.free(packet);

    try std.testing.expectEqual(12 + opus_data.len + discord.voice.VoiceEncryptor.tag_length, packet.len);

    const decrypted = try discord.voice.VoiceEncryptor.decryptPacket(allocator, packet, key);
    defer allocator.free(decrypted);

    try std.testing.expectEqualStrings(opus_data, decrypted);
}

test "audio player frame generation and sequence increments" {
    const allocator = std.testing.allocator;
    const key = [_]u8{0x77} ** 32;

    var player = discord.voice.AudioPlayer.init(555, key);
    try std.testing.expectEqual(@as(u16, 0), player.sequence);
    try std.testing.expectEqual(@as(u32, 0), player.timestamp);

    const frame1 = try player.nextPacket(allocator, "frame1");
    defer allocator.free(frame1);

    try std.testing.expectEqual(@as(u16, 1), player.sequence);
    try std.testing.expectEqual(@as(u32, 960), player.timestamp);

    const frame2 = try player.nextPacket(allocator, "frame2");
    defer allocator.free(frame2);

    try std.testing.expectEqual(@as(u16, 2), player.sequence);
    try std.testing.expectEqual(@as(u32, 1920), player.timestamp);

    const silence = try player.nextSilencePacket(allocator);
    defer allocator.free(silence);

    try std.testing.expectEqual(@as(u16, 3), player.sequence);
    try std.testing.expectEqual(@as(u32, 2880), player.timestamp);
}

test "ip discovery packet generation and parsing" {
    const ssrc: u32 = 0x12345678;
    const packet = discord.voice.createIpDiscoveryPacket(ssrc);
    try std.testing.expectEqual(@as(usize, 74), packet.len);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, packet[0..2], .big));
    try std.testing.expectEqual(@as(u16, 70), std.mem.readInt(u16, packet[2..4], .big));
    try std.testing.expectEqual(ssrc, std.mem.readInt(u32, packet[4..8], .big));

    var response = [_]u8{0} ** 74;
    @memcpy(response[0..8], packet[0..8]);
    const ip = "198.51.100.42";
    @memcpy(response[8 .. 8 + ip.len], ip);
    std.mem.writeInt(u16, response[72..74], 50005, .big);

    const parsed = try discord.voice.parseIpDiscoveryResponse(&response);
    try std.testing.expectEqualStrings(ip, parsed.ip);
    try std.testing.expectEqual(@as(u16, 50005), parsed.port);
}

test "voice gateway message encoders and parsers" {
    const allocator = std.testing.allocator;

    const id_json = try discord.voice.encodeIdentify(allocator, "guild1", "user1", "session1", "token1");
    defer allocator.free(id_json);
    try std.testing.expect(std.mem.indexOf(u8, id_json, "\"server_id\":\"guild1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, id_json, "\"op\":0") != null);

    const proto_json = try discord.voice.encodeSelectProtocol(allocator, "1.2.3.4", 50000, "xsalsa20_poly1305");
    defer allocator.free(proto_json);
    try std.testing.expect(std.mem.indexOf(u8, proto_json, "\"address\":\"1.2.3.4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, proto_json, "\"op\":1") != null);

    const hb_json = try discord.voice.encodeHeartbeat(allocator, 9999);
    defer allocator.free(hb_json);
    try std.testing.expect(std.mem.indexOf(u8, hb_json, "\"op\":3") != null);

    const spk_json = try discord.voice.encodeSpeaking(allocator, 1234, discord.voice.SpeakingFlags.microphone, 0);
    defer allocator.free(spk_json);
    try std.testing.expect(std.mem.indexOf(u8, spk_json, "\"op\":5") != null);

    const hello_payload = "{\"op\":8,\"d\":{\"heartbeat_interval\":41250}}";
    const interval = try discord.voice.parseHello(allocator, hello_payload);
    try std.testing.expectEqual(@as(f64, 41250), interval);

    var dummy_key: [32]u8 = [_]u8{9} ** 32;
    var session_desc: std.Io.Writer.Allocating = .init(allocator);
    defer session_desc.deinit();
    try std.json.Stringify.value(.{
        .op = 4,
        .d = .{
            .mode = "xsalsa20_poly1305",
            .secret_key = &dummy_key,
        },
    }, .{}, &session_desc.writer);

    const parsed_key = try discord.voice.parseSessionDescriptionKey(allocator, session_desc.written());
    try std.testing.expectEqualSlices(u8, &dummy_key, &parsed_key);
}

test "voice connection state tracking" {
    var conn = discord.voice.VoiceConnection.init("guild123", "chan456");
    try std.testing.expect(!conn.isReady());
    try std.testing.expect(conn.getPlayer() == null);

    conn.ssrc = 777;
    conn.secret_key = [_]u8{0xAA} ** 32;
    try std.testing.expect(conn.isReady());
    try std.testing.expect(conn.getPlayer() != null);
}

test "voice opcodes matching discord.js" {
    const VoiceOpcodes = discord.VoiceOpcodes;

    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(VoiceOpcodes.Identify));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(VoiceOpcodes.SelectProtocol));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(VoiceOpcodes.Ready));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(VoiceOpcodes.Heartbeat));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(VoiceOpcodes.SessionDescription));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(VoiceOpcodes.Speaking));
    try std.testing.expectEqual(@as(u8, 6), @intFromEnum(VoiceOpcodes.HeartbeatAck));
    try std.testing.expectEqual(@as(u8, 7), @intFromEnum(VoiceOpcodes.Resume));
    try std.testing.expectEqual(@as(u8, 8), @intFromEnum(VoiceOpcodes.Hello));
    try std.testing.expectEqual(@as(u8, 9), @intFromEnum(VoiceOpcodes.Resumed));
    try std.testing.expectEqual(@as(u8, 12), @intFromEnum(VoiceOpcodes.ClientConnect));
    try std.testing.expectEqual(@as(u8, 13), @intFromEnum(VoiceOpcodes.ClientDisconnect));
    try std.testing.expectEqual(@as(u8, 21), @intFromEnum(VoiceOpcodes.DavePrepareTransition));
    try std.testing.expectEqual(VoiceOpcodes.DavePrepareTransition, VoiceOpcodes.DAVEPrepareTransition);

    const op = VoiceOpcodes.Resume;
    const name = switch (op) {
        VoiceOpcodes.Identify => "identify",
        VoiceOpcodes.Ready => "ready",
        VoiceOpcodes.Resume => "resume",
        else => "other",
    };
    try std.testing.expectEqualStrings("resume", name);
}
