const std = @import("std");

pub const api_version: u8 = 10;
pub const max_payload_bytes: usize = 4096;
pub const max_events_per_minute: u32 = 120;

pub const GatewayOpcodes = enum(u8) {
    Dispatch = 0,
    Heartbeat = 1,
    Identify = 2,
    PresenceUpdate = 3,
    VoiceStateUpdate = 4,
    Resume = 6,
    Reconnect = 7,
    RequestGuildMembers = 8,
    InvalidSession = 9,
    Hello = 10,
    HeartbeatAck = 11,
    _,

    pub const dispatch = GatewayOpcodes.Dispatch;
    pub const heartbeat = GatewayOpcodes.Heartbeat;
    pub const identify = GatewayOpcodes.Identify;
    pub const presence_update = GatewayOpcodes.PresenceUpdate;
    pub const voice_state_update = GatewayOpcodes.VoiceStateUpdate;
    pub const resume_session = GatewayOpcodes.Resume;
    pub const reconnect = GatewayOpcodes.Reconnect;
    pub const request_guild_members = GatewayOpcodes.RequestGuildMembers;
    pub const invalid_session = GatewayOpcodes.InvalidSession;
    pub const hello = GatewayOpcodes.Hello;
    pub const heartbeat_ack = GatewayOpcodes.HeartbeatAck;

    pub fn fromInt(value: u8) GatewayOpcodes {
        return std.enums.fromInt(GatewayOpcodes, value) orelse .Dispatch;
    }
};

pub const Op = GatewayOpcodes;
pub const GatewayOp = GatewayOpcodes;

pub const Payload = struct {
    op: u8,
    d: ?std.json.Value = null,
    s: ?i64 = null,
    t: ?[]const u8 = null,
};

pub const Hello = struct {
    heartbeat_interval: u64,
};

pub const Ready = struct {
    session_id: []const u8,
    resume_gateway_url: []const u8,
};

pub const Properties = struct {
    os: []const u8 = "linux",
    browser: []const u8 = "discord-zig",
    device: []const u8 = "discord-zig",
};

pub fn decode(allocator: std.mem.Allocator, text: []const u8) !std.json.Parsed(Payload) {
    return std.json.parseFromSlice(Payload, allocator, text, .{ .ignore_unknown_fields = true });
}

pub fn encodeHeartbeat(allocator: std.mem.Allocator, seq: ?i64) ![]u8 {
    if (seq) |s| {
        return std.fmt.allocPrint(allocator, "{{\"op\":1,\"d\":{d}}}", .{s});
    }
    return allocator.dupe(u8, "{\"op\":1,\"d\":null}");
}

/// Variante sem alocação para o caminho quente (heartbeat a cada ~45s):
/// escreve em `out` e retorna o slice usado.
pub fn encodeHeartbeatBuf(seq: ?i64, out: *[32]u8) []u8 {
    if (seq) |s| {
        return std.fmt.bufPrint(out, "{{\"op\":1,\"d\":{d}}}", .{s}) catch out[0..0];
    }
    const text = "{\"op\":1,\"d\":null}";
    @memcpy(out[0..text.len], text);
    return out[0..text.len];
}

pub const ActivityType = enum(u8) {
    Playing = 0,
    Streaming = 1,
    Listening = 2,
    Watching = 3,
    Custom = 4,
    Competing = 5,
};

pub const PresenceStatus = enum {
    online,
    dnd,
    idle,
    invisible,
    offline,
};

pub const Activity = struct {
    name: []const u8,
    type: ActivityType = .Playing,
    url: ?[]const u8 = null,
};

pub const PresenceData = struct {
    activities: []const Activity = &.{},
    status: PresenceStatus = .online,
    afk: bool = false,
    since: ?i64 = null,
};

pub fn encodePresenceUpdate(allocator: std.mem.Allocator, presence: PresenceData) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try std.json.Stringify.value(.{
        .op = 3,
        .d = .{
            .since = presence.since,
            .activities = presence.activities,
            .status = @tagName(presence.status),
            .afk = presence.afk,
        },
    }, .{ .emit_null_optional_fields = true }, &out.writer);
    return out.toOwnedSlice();
}

pub fn encodeIdentifyFull(
    allocator: std.mem.Allocator,
    token: []const u8,
    intents: u32,
    shard: ?[2]u32,
    presence: ?PresenceData,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();

    var d_obj: struct {
        token: []const u8,
        intents: u32,
        properties: Properties = .{},
        shard: ?[2]u32 = null,
        presence: ?struct {
            since: ?i64 = null,
            activities: []const Activity = &.{},
            status: []const u8 = "online",
            afk: bool = false,
        } = null,
    } = .{
        .token = token,
        .intents = intents,
        .properties = .{},
        .shard = shard,
    };

    if (presence) |p| {
        d_obj.presence = .{
            .since = p.since,
            .activities = p.activities,
            .status = @tagName(p.status),
            .afk = p.afk,
        };
    }

    try std.json.Stringify.value(.{
        .op = 2,
        .d = d_obj,
    }, .{ .emit_null_optional_fields = false }, &out.writer);
    return out.toOwnedSlice();
}

pub fn encodeIdentify(allocator: std.mem.Allocator, token: []const u8, intents: u32) ![]u8 {
    return encodeIdentifyFull(allocator, token, intents, null, null);
}

pub fn encodeResume(allocator: std.mem.Allocator, token: []const u8, session_id: []const u8, seq: i64) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try std.json.Stringify.value(.{
        .op = 6,
        .d = .{
            .token = token,
            .session_id = session_id,
            .seq = seq,
        },
    }, .{}, &out.writer);
    return out.toOwnedSlice();
}

pub fn encodeRequestGuildMembers(allocator: std.mem.Allocator, guild_id: []const u8, query: []const u8, limit: u32) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try std.json.Stringify.value(.{
        .op = 8,
        .d = .{
            .guild_id = guild_id,
            .query = query,
            .limit = limit,
        },
    }, .{}, &out.writer);
    return out.toOwnedSlice();
}

pub fn encodeVoiceStateUpdate(
    allocator: std.mem.Allocator,
    guild_id: []const u8,
    channel_id: ?[]const u8,
    self_mute: bool,
    self_deaf: bool,
) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    try std.json.Stringify.value(.{
        .op = 4,
        .d = .{
            .guild_id = guild_id,
            .channel_id = channel_id,
            .self_mute = self_mute,
            .self_deaf = self_deaf,
        },
    }, .{ .emit_null_optional_fields = true }, &out.writer);
    return out.toOwnedSlice();
}

pub fn parseHello(allocator: std.mem.Allocator, text: []const u8) !u64 {
    const parsed = try std.json.parseFromSlice(struct {
        op: u8,
        d: struct {
            heartbeat_interval: u64,
        },
    }, allocator, text, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    return parsed.value.d.heartbeat_interval;
}

pub fn canResume(close_code: u16) bool {
    return switch (close_code) {
        1000, 1001, 4010, 4011, 4012, 4013, 4014 => false,
        else => true,
    };
}

pub fn closeCodeName(close_code: u16) []const u8 {
    return switch (close_code) {
        1000 => "Normal Closure",
        1001 => "Going Away",
        4000 => "Unknown Error",
        4001 => "Unknown Opcode",
        4002 => "Decode Error",
        4003 => "Not Authenticated",
        4004 => "Authentication Failed",
        4005 => "Already Authenticated",
        4007 => "Invalid Sequence",
        4008 => "Rate Limited",
        4009 => "Session Timed Out",
        4010 => "Invalid Shard",
        4011 => "Sharding Required",
        4012 => "Invalid API Version",
        4013 => "Invalid Intents",
        4014 => "Disallowed Intents",
        else => "Unknown",
    };
}

pub const GatewayTarget = struct {
    host: []const u8,
    port: u16,
    path: []const u8,
    tls: bool,
};

pub fn parseGatewayUrl(url: []const u8) ?GatewayTarget {
    const scheme_end = std.mem.indexOf(u8, url, "://") orelse return null;
    const scheme = url[0..scheme_end];
    const tls = if (std.mem.eql(u8, scheme, "wss")) true else if (std.mem.eql(u8, scheme, "ws")) false else return null;
    const rest = url[scheme_end + 3 ..];
    if (rest.len == 0) return null;
    const slash = std.mem.indexOfScalar(u8, rest, '/');
    const authority = if (slash) |i| rest[0..i] else rest;
    const path = if (slash) |i| rest[i..] else "/";
    if (std.mem.indexOfScalar(u8, authority, ':')) |ci| {
        if (ci == 0) return null;
        const port = std.fmt.parseInt(u16, authority[ci + 1 ..], 10) catch return null;
        return .{ .host = authority[0..ci], .port = port, .path = path, .tls = tls };
    }
    return .{ .host = authority, .port = if (tls) 443 else 80, .path = path, .tls = tls };
}
