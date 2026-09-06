const std = @import("std");
const schema = @import("./schema.zig");
const gateway = @import("./gateway.zig");

pub const VoiceOpcodes = enum(u8) {
    Identify = 0,
    SelectProtocol = 1,
    Ready = 2,
    Heartbeat = 3,
    SessionDescription = 4,
    Speaking = 5,
    HeartbeatAck = 6,
    Resume = 7,
    Hello = 8,
    Resumed = 9,
    ClientConnect = 12,
    ClientDisconnect = 13,
    DavePrepareTransition = 21,
    DaveExecuteTransition = 22,
    DaveTransitionReady = 23,
    DavePrepareEpoch = 24,
    DaveMLSExternalSender = 25,
    DaveMLSKeyPackage = 26,
    DaveMLSProposals = 27,
    DaveMLSCommitWelcome = 28,
    DaveMLSAnnounce = 29,
    _,

    pub const DAVEPrepareTransition = VoiceOpcodes.DavePrepareTransition;
    pub const DAVEExecuteTransition = VoiceOpcodes.DaveExecuteTransition;
    pub const DAVETransitionReady = VoiceOpcodes.DaveTransitionReady;
    pub const DAVEPrepareEpoch = VoiceOpcodes.DavePrepareEpoch;
};

pub const VoiceOp = VoiceOpcodes;

pub const SpeakingFlags = struct {
    pub const microphone: u32 = 1 << 0;
    pub const soundshare: u32 = 1 << 1;
    pub const priority: u32 = 1 << 2;
};

pub const silence_frame = [_]u8{ 0xF8, 0xFF, 0xFE };

pub const RtpHeader = struct {
    version: u8 = 0x80,
    payload_type: u8 = 0x78,
    sequence: u16,
    timestamp: u32,
    ssrc: u32,

    pub const size: usize = 12;

    pub fn encode(self: RtpHeader, out: *[12]u8) void {
        out[0] = self.version;
        out[1] = self.payload_type;
        std.mem.writeInt(u16, out[2..4], self.sequence, .big);
        std.mem.writeInt(u32, out[4..8], self.timestamp, .big);
        std.mem.writeInt(u32, out[8..12], self.ssrc, .big);
    }

    pub fn decode(bytes: *const [12]u8) RtpHeader {
        return .{
            .version = bytes[0],
            .payload_type = bytes[1],
            .sequence = std.mem.readInt(u16, bytes[2..4], .big),
            .timestamp = std.mem.readInt(u32, bytes[4..8], .big),
            .ssrc = std.mem.readInt(u32, bytes[8..12], .big),
        };
    }
};

pub const VoiceEncryptor = struct {
    pub const tag_length: usize = std.crypto.nacl.SecretBox.tag_length;

    /// Escreve o pacote em `out` (precisa de `12 + frame.len + tag_length`
    /// bytes) e retorna o slice usado. Reutilizar o buffer evita um alloc
    /// por frame (~50/s por stream de áudio).
    pub fn encryptPacketBuf(
        header: RtpHeader,
        opus_frame: []const u8,
        secret_key: [32]u8,
        out: []u8,
    ) []u8 {
        const packet_len = RtpHeader.size + opus_frame.len + tag_length;
        std.debug.assert(out.len >= packet_len);
        const packet = out[0..packet_len];

        header.encode(packet[0..12]);

        var nonce = [_]u8{0} ** 24;
        @memcpy(nonce[0..12], packet[0..12]);

        std.crypto.nacl.SecretBox.seal(packet[12..], opus_frame, nonce, secret_key);
        return packet;
    }

    pub fn encryptPacket(
        allocator: std.mem.Allocator,
        header: RtpHeader,
        opus_frame: []const u8,
        secret_key: [32]u8,
    ) ![]u8 {
        const packet = try allocator.alloc(u8, RtpHeader.size + opus_frame.len + tag_length);
        errdefer allocator.free(packet);
        return encryptPacketBuf(header, opus_frame, secret_key, packet);
    }

    /// Decodifica em `out` (precisa de `packet.len - 12 - tag_length` bytes).
    pub fn decryptPacketBuf(
        packet: []const u8,
        secret_key: [32]u8,
        out: []u8,
    ) ![]u8 {
        if (packet.len < RtpHeader.size + tag_length) return error.PacketTooShort;
        const header = RtpHeader.decode(packet[0..12]);
        _ = header;

        var nonce = [_]u8{0} ** 24;
        @memcpy(nonce[0..12], packet[0..12]);

        const opus_len = packet.len - RtpHeader.size - tag_length;
        std.debug.assert(out.len >= opus_len);
        const opus = out[0..opus_len];

        try std.crypto.nacl.SecretBox.open(opus, packet[12..], nonce, secret_key);
        return opus;
    }

    pub fn decryptPacket(
        allocator: std.mem.Allocator,
        packet: []const u8,
        secret_key: [32]u8,
    ) ![]u8 {
        if (packet.len < RtpHeader.size + tag_length) return error.PacketTooShort;
        const opus = try allocator.alloc(u8, packet.len - RtpHeader.size - tag_length);
        errdefer allocator.free(opus);
        return decryptPacketBuf(packet, secret_key, opus);
    }
};

pub const AudioPlayer = struct {
    sequence: u16 = 0,
    timestamp: u32 = 0,
    ssrc: u32,
    secret_key: [32]u8,

    pub fn init(ssrc: u32, secret_key: [32]u8) AudioPlayer {
        return .{
            .ssrc = ssrc,
            .secret_key = secret_key,
        };
    }

    pub fn nextPacket(self: *AudioPlayer, allocator: std.mem.Allocator, opus_frame: []const u8) ![]u8 {
        const packet = try allocator.alloc(u8, RtpHeader.size + opus_frame.len + VoiceEncryptor.tag_length);
        errdefer allocator.free(packet);
        return self.nextPacketBuf(opus_frame, packet);
    }

    /// Variante sem alocação: `out` precisa de `12 + frame.len + tag_length`.
    pub fn nextPacketBuf(self: *AudioPlayer, opus_frame: []const u8, out: []u8) []u8 {
        const header = RtpHeader{
            .sequence = self.sequence,
            .timestamp = self.timestamp,
            .ssrc = self.ssrc,
        };
        self.sequence +%= 1;
        self.timestamp +%= 960;
        return VoiceEncryptor.encryptPacketBuf(header, opus_frame, self.secret_key, out);
    }

    pub fn nextSilencePacket(self: *AudioPlayer, allocator: std.mem.Allocator) ![]u8 {
        return self.nextPacket(allocator, &silence_frame);
    }
};

pub fn createIpDiscoveryPacket(ssrc: u32) [74]u8 {
    var packet = [_]u8{0} ** 74;
    std.mem.writeInt(u16, packet[0..2], 1, .big);
    std.mem.writeInt(u16, packet[2..4], 70, .big);
    std.mem.writeInt(u32, packet[4..8], ssrc, .big);
    return packet;
}

pub fn parseIpDiscoveryResponse(packet: *const [74]u8) !struct { ip: []const u8, port: u16 } {
    const raw_ip = packet[8..72];
    const zero_idx = std.mem.indexOfScalar(u8, raw_ip, 0) orelse raw_ip.len;
    const port = std.mem.readInt(u16, packet[72..74], .big);
    return .{
        .ip = raw_ip[0..zero_idx],
        .port = port,
    };
}

pub fn encodeIdentify(
    allocator: std.mem.Allocator,
    server_id: []const u8,
    user_id: []const u8,
    session_id: []const u8,
    token: []const u8,
) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .op = @intFromEnum(VoiceOpcodes.Identify),
        .d = .{
            .server_id = server_id,
            .user_id = user_id,
            .session_id = session_id,
            .token = token,
        },
    }, .{});
}

pub fn encodeSelectProtocol(
    allocator: std.mem.Allocator,
    ip: []const u8,
    port: u16,
    mode: []const u8,
) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .op = @intFromEnum(VoiceOpcodes.SelectProtocol),
        .d = .{
            .protocol = "udp",
            .data = .{
                .address = ip,
                .port = port,
                .mode = mode,
            },
        },
    }, .{});
}

pub fn encodeHeartbeat(allocator: std.mem.Allocator, nonce: u64) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .op = @intFromEnum(VoiceOpcodes.Heartbeat),
        .d = nonce,
    }, .{});
}

pub fn encodeSpeaking(allocator: std.mem.Allocator, ssrc: u32, flags: u32, delay: u32) ![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .op = @intFromEnum(VoiceOpcodes.Speaking),
        .d = .{
            .speaking = flags,
            .delay = delay,
            .ssrc = ssrc,
        },
    }, .{});
}

pub const VoiceHello = struct {
    heartbeat_interval: f64,
};

pub const VoiceReady = struct {
    ssrc: u32,
    ip: []const u8,
    port: u16,
    modes: []const []const u8,
    heartbeat_interval: ?f64 = null,
};

pub fn parseHello(allocator: std.mem.Allocator, json_text: []const u8) !f64 {
    const Raw = struct {
        op: u8 = 0,
        d: struct {
            heartbeat_interval: f64 = 0,
        },
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, json_text, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    return parsed.value.d.heartbeat_interval;
}

pub fn parseSessionDescriptionKey(allocator: std.mem.Allocator, json_text: []const u8) ![32]u8 {
    const Raw = struct {
        op: u8 = 0,
        d: struct {
            mode: []const u8 = "",
            secret_key: []const u8 = &.{},
        },
    };
    var parsed = try std.json.parseFromSlice(Raw, allocator, json_text, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    if (parsed.value.d.secret_key.len != 32) return error.InvalidSecretKeyLength;
    var key: [32]u8 = undefined;
    @memcpy(&key, parsed.value.d.secret_key[0..32]);
    return key;
}

pub const VoiceConnection = struct {
    guild_id: []const u8,
    channel_id: []const u8,
    self_mute: bool = false,
    self_deaf: bool = false,
    endpoint: ?[]const u8 = null,
    token: ?[]const u8 = null,
    session_id: ?[]const u8 = null,
    ssrc: ?u32 = null,
    secret_key: ?[32]u8 = null,
    player: ?AudioPlayer = null,

    pub fn init(guild_id: []const u8, channel_id: []const u8) VoiceConnection {
        return .{
            .guild_id = guild_id,
            .channel_id = channel_id,
        };
    }

    pub fn isReady(self: VoiceConnection) bool {
        return self.secret_key != null and self.ssrc != null;
    }

    pub fn getPlayer(self: *VoiceConnection) ?*AudioPlayer {
        if (self.player) |*p| return p;
        if (self.ssrc) |ssrc| {
            if (self.secret_key) |key| {
                self.player = AudioPlayer.init(ssrc, key);
                return &self.player.?;
            }
        }
        return null;
    }

    pub fn createWorker(self: *VoiceConnection) ?AudioStreamWorker {
        if (self.getPlayer()) |p| {
            return AudioStreamWorker.init(p);
        }
        return null;
    }
};

pub const AudioStreamWorker = struct {
    player: *AudioPlayer,
    is_playing: bool = false,
    paused: bool = false,

    pub fn init(player: *AudioPlayer) AudioStreamWorker {
        return .{ .player = player };
    }

    pub fn prepareFrame(self: *AudioStreamWorker, allocator: std.mem.Allocator, opus_frame: []const u8) ![]u8 {
        return self.player.nextPacket(allocator, opus_frame);
    }

    pub fn prepareSilence(self: *AudioStreamWorker, allocator: std.mem.Allocator) ![]u8 {
        return self.player.nextSilencePacket(allocator);
    }
};
