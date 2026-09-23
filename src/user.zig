const std = @import("std");
const schema = @import("./schema.zig");
const client_mod = @import("./client.zig");

pub const Users = struct {
    _slot: usize = 0,

    fn client(self: *Users) *client_mod.Client {
        return @alignCast(@fieldParentPtr("users", self));
    }

    pub fn fetch(self: *Users, id: []const u8) !User {
        const c = self.client();
        const key = std.fmt.parseInt(u64, id, 10) catch null;
        if (key) |k| {
            if (c.cache.users.get(k) != null) return User.init(c, id);
        }
        var fetched = try c.rest.fetchUser(id);
        if (key) |k| {
            var owned: ?std.json.Parsed(schema.User) = fetched;
            errdefer if (owned) |*p| p.deinit();
            try c.cache.users.putParsed(k, owned.?);
            owned = null;
        } else {
            fetched.deinit();
        }
        return User.init(c, id);
    }
};

pub const User = struct {
    client: *client_mod.Client,
    id: []const u8,

    pub fn init(client: *client_mod.Client, id: []const u8) User {
        return .{ .client = client, .id = id };
    }

    pub fn fetch(self: User) !std.json.Parsed(schema.User) {
        return self.client.rest.fetchUser(self.id);
    }

    pub fn send(self: User, content: []const u8) !std.json.Parsed(schema.Message) {
        const c = self.client;
        const user_key = std.fmt.parseInt(u64, self.id, 10) catch null;
        if (user_key) |k| {
            if (c.dm_channels.get(k)) |channel_id| {
                var id_buf: [24]u8 = undefined;
                const channel_text = std.fmt.bufPrint(&id_buf, "{d}", .{channel_id}) catch unreachable;
                if (c.rest.createMessage(channel_text, content)) |msg| {
                    return msg;
                } else |_| {
                    // Canal memoizado morreu (ex.: DM fechado): descarta a
                    // memoização e reabre abaixo.
                    _ = c.dm_channels.remove(k);
                }
            }
        }
        var dm = try c.rest.createDM(self.id);
        defer dm.deinit();
        if (user_key) |k| {
            if (std.fmt.parseInt(u64, dm.value.id, 10) catch null) |dm_key| {
                c.dm_channels.put(c.allocator, k, dm_key) catch {};
            }
        }
        return c.rest.createMessage(dm.value.id, content);
    }
};

pub const ClientUser = struct {
    _slot: usize = 0,
    id: []const u8 = "",
    username: []const u8 = "",
    discriminator: []const u8 = "0",
    avatar: ?[]const u8 = null,
    bot: bool = true,

    fn client(self: *ClientUser) *client_mod.Client {
        return @alignCast(@fieldParentPtr("user", self));
    }

    pub fn setPresence(self: *ClientUser, data: @import("./gateway.zig").PresenceData) !void {
        return self.client().setPresence(data);
    }

    pub fn setActivity(self: *ClientUser, name: []const u8, opt: struct { type: @import("./gateway.zig").ActivityType = .Playing, url: ?[]const u8 = null }) !void {
        return self.client().setPresence(.{
            .activities = &[_]@import("./gateway.zig").Activity{.{
                .name = name,
                .type = opt.type,
                .url = opt.url,
            }},
            .status = .online,
        });
    }

    pub fn setStatus(self: *ClientUser, status: @import("./gateway.zig").PresenceStatus) !void {
        return self.client().setPresence(.{
            .status = status,
        });
    }

    pub fn setUsername(self: *ClientUser, new_name: []const u8) !std.json.Parsed(schema.User) {
        return self.client().rest.editCurrentUser(new_name, null);
    }

    pub fn fetch(self: *ClientUser) !std.json.Parsed(schema.User) {
        return self.client().rest.getCurrentUser();
    }
};
