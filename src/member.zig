const std = @import("std");
const schema = @import("./schema.zig");
const client_mod = @import("./client.zig");
const permission = @import("./permission.zig");

pub const Member = struct {
    client: *client_mod.Client,
    guild_id: []const u8,
    user_id: []const u8,
    roles: Roles = .{},
    voice: Voice = .{},

    pub fn init(client: *client_mod.Client, guild_id: []const u8, user_id: []const u8) Member {
        return .{ .client = client, .guild_id = guild_id, .user_id = user_id };
    }

    pub fn fetch(self: Member) !std.json.Parsed(schema.GuildMember) {
        return self.client.rest.getMember(self.guild_id, self.user_id);
    }

    pub fn editNick(self: Member, nick: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        return self.client.rest.editMemberNick(self.guild_id, self.user_id, nick, reason);
    }

    pub fn kick(self: Member, reason: ?[]const u8) !void {
        return self.client.rest.kick(self.guild_id, self.user_id, reason);
    }

    pub fn ban(self: Member, delete_message_seconds: u32, reason: ?[]const u8) !void {
        return self.client.rest.ban(self.guild_id, self.user_id, delete_message_seconds, reason);
    }

    pub fn timeout(self: Member, disabled_until: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        return self.client.rest.timeoutMember(self.guild_id, self.user_id, disabled_until, reason);
    }

    pub fn timeoutDuration(self: Member, duration_seconds: u32, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        return self.client.rest.timeoutMemberDuration(self.guild_id, self.user_id, duration_seconds, reason);
    }


    pub fn presence(self: Member) ?*const schema.Presence {
        const key = std.fmt.parseInt(u64, self.user_id, 10) catch return null;
        return self.client.cache.presences.get(key);
    }

    pub fn permissions(self: Member, guild_roles: []const schema.Role, owner_id: []const u8) !u64 {
        var fetched = try self.fetch();
        defer fetched.deinit();
        return permission.resolveMember(guild_roles, fetched.value, owner_id);
    }

    pub fn permissionsIn(self: Member, channel: schema.Channel, guild_roles: []const schema.Role, owner_id: []const u8) !u64 {
        var fetched = try self.fetch();
        defer fetched.deinit();
        const base = permission.resolveMember(guild_roles, fetched.value, owner_id);
        return permission.resolveChannelPermissions(base, self.user_id, fetched.value.roles, self.guild_id, channel.permission_overwrites);
    }
};

pub const Roles = struct {
    _slot: usize = 0,

    fn member(self: *Roles) *Member {
        return @fieldParentPtr("roles", self);
    }

    pub fn add(self: *Roles, role_id: []const u8, reason: ?[]const u8) !void {
        const m = self.member();
        return m.client.rest.addRole(m.guild_id, m.user_id, role_id, reason);
    }

    pub fn remove(self: *Roles, role_id: []const u8, reason: ?[]const u8) !void {
        const m = self.member();
        return m.client.rest.removeRole(m.guild_id, m.user_id, role_id, reason);
    }

    pub fn set(self: *Roles, role_ids: []const []const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const m = self.member();
        return m.client.rest.editMemberRoles(m.guild_id, m.user_id, role_ids, reason);
    }
};

pub const Voice = struct {
    _slot: usize = 0,

    fn member(self: *Voice) *Member {
        return @fieldParentPtr("voice", self);
    }

    pub fn setMute(self: *Voice, mute: bool, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const m = self.member();
        return m.client.rest.setMemberMute(m.guild_id, m.user_id, mute, reason);
    }

    pub fn setDeaf(self: *Voice, deaf: bool, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const m = self.member();
        return m.client.rest.setMemberDeaf(m.guild_id, m.user_id, deaf, reason);
    }

    pub fn move(self: *Voice, channel_id: ?[]const u8, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const m = self.member();
        return m.client.rest.moveMember(m.guild_id, m.user_id, channel_id, reason);
    }

    pub fn disconnect(self: *Voice, reason: ?[]const u8) !std.json.Parsed(schema.GuildMember) {
        const m = self.member();
        return m.client.rest.disconnectMember(m.guild_id, m.user_id, reason);
    }
};
