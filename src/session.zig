const std = @import("std");
const gateway = @import("./gateway.zig");
const heartbeat = @import("./heartbeat.zig");
const intents = @import("./intents.zig");

pub const Config = struct {
    token: []const u8,
    intents: u32 = 0,
    shard: ?[2]u32 = null,
    presence: ?gateway.PresenceData = null,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    config: Config,
    seq: ?i64 = null,
    session_id: ?[]const u8 = null,
    resume_url: ?[]const u8 = null,
    hb: heartbeat.Monitor = .{},

    pub fn init(allocator: std.mem.Allocator, io: std.Io, config: Config) Session {
        return .{
            .allocator = allocator,
            .io = io,
            .config = config,
        };
    }

    pub fn deinit(self: *Session) void {
        if (self.session_id) |id| self.allocator.free(id);
        if (self.resume_url) |url| self.allocator.free(url);
    }

    pub fn intentsOrDefault(self: Session) u32 {
        if (self.config.intents != 0) return self.config.intents;
        return intents.defaults();
    }

    pub fn trackDispatch(self: *Session, s: ?i64) void {
        if (s) |value| self.seq = value;
    }

    pub fn storeReady(self: *Session, session_id: []const u8, resume_url: []const u8) !void {
        if (self.session_id) |id| self.allocator.free(id);
        if (self.resume_url) |url| self.allocator.free(url);
        self.session_id = try self.allocator.dupe(u8, session_id);
        self.resume_url = try self.allocator.dupe(u8, resume_url);
    }

    pub fn clearResume(self: *Session) void {
        if (self.session_id) |id| self.allocator.free(id);
        if (self.resume_url) |url| self.allocator.free(url);
        self.session_id = null;
        self.resume_url = null;
        self.seq = null;
    }

    pub fn heartbeatPayload(self: Session, allocator: std.mem.Allocator) ![]u8 {
        return gateway.encodeHeartbeat(allocator, self.seq);
    }

    pub fn identifyPayload(self: Session, allocator: std.mem.Allocator) ![]u8 {
        return gateway.encodeIdentifyFull(allocator, self.config.token, self.intentsOrDefault(), self.config.shard, self.config.presence);
    }

    pub fn resumePayload(self: Session, allocator: std.mem.Allocator) ![]u8 {
        const session_id = self.session_id orelse return error.MissingSession;
        return gateway.encodeResume(allocator, self.config.token, session_id, self.seq orelse 0);
    }
};
