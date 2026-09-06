const std = @import("std");
const permission = @import("discord-zig").permission;
const schema = @import("discord-zig").schema;

test "flag values match discord docs" {
    try std.testing.expectEqual(@as(u64, 1), permission.create_instant_invite);
    try std.testing.expectEqual(@as(u64, 8), permission.administrator);
    try std.testing.expectEqual(@as(u64, 1) << 11, permission.send_messages);
    try std.testing.expectEqual(@as(u64, 1) << 45, permission.use_external_sounds);
    try std.testing.expectEqual(@as(u64, 1) << 48, permission.set_voice_channel_status);
    try std.testing.expectEqual(@as(u64, 1) << 49, permission.send_polls);
    try std.testing.expectEqual(@as(u64, 1) << 50, permission.use_external_apps);
    try std.testing.expectEqual(@as(u64, 1) << 51, permission.pin_messages);
    try std.testing.expectEqual(@as(u64, 1) << 52, permission.bypass_slowmode);
}

test "PermissionFlagsBits matches snake consts" {
    try std.testing.expectEqual(permission.administrator, permission.PermissionFlagsBits.Administrator);
    try std.testing.expectEqual(permission.send_messages, permission.PermissionFlagsBits.SendMessages);
    try std.testing.expectEqual(permission.bypass_slowmode, permission.PermissionFlagsBits.BypassSlowmode);
    try std.testing.expectEqual(permission.use_external_apps, permission.PermissionFlagsBits.UseExternalApps);
}

test "of combines mixed flag styles" {
    const v = permission.of(.{ .administrator, permission.Bits.send_messages, permission.PermissionFlagsBits.ManageGuild });
    try std.testing.expectEqual(permission.administrator | permission.send_messages | permission.manage_guild, v);
    try std.testing.expectEqual(permission.kick_members, permission.of(.kick_members));
    try std.testing.expectEqual(@as(u64, 0), permission.of(.{}));
    try std.testing.expect(permission.has(v, permission.administrator));
    try std.testing.expect(!permission.has(v, permission.ban_members));
}

test "Flags init add remove" {
    var f = permission.Flags.init(.{.send_messages});
    try std.testing.expect(f.has(.send_messages));
    f.add(.{.attach_files});
    try std.testing.expect(f.has(.attach_files));
    f.remove(.{.send_messages});
    try std.testing.expect(!f.has(.send_messages));
}

test "parse role permission strings" {
    try std.testing.expectEqual(@as(u64, 8), permission.parse("8"));
    try std.testing.expectEqual(@as(u64, 66321471), permission.parse("66321471"));
    try std.testing.expectEqual(@as(u64, 0), permission.parse("nope"));
}

test "resolveMember ors roles with owner and admin shortcuts" {
    const roles = [_]schema.Role{
        .{ .id = "10", .name = "@everyone", .permissions = "1024" },
        .{ .id = "20", .name = "mod", .permissions = "6" },
        .{ .id = "30", .name = "admin", .permissions = "8" },
    };
    const plain = schema.GuildMember{
        .user = .{ .id = "1", .username = "a" },
        .roles = &.{ "10", "20" },
    };
    try std.testing.expectEqual(@as(u64, 1030), permission.resolveMember(&roles, plain, "99"));

    const admin = schema.GuildMember{
        .user = .{ .id = "2", .username = "b" },
        .roles = &.{"30"},
    };
    try std.testing.expectEqual(permission.all(), permission.resolveMember(&roles, admin, "99"));

    const owner = schema.GuildMember{
        .user = .{ .id = "99", .username = "o" },
        .roles = &.{},
    };
    try std.testing.expectEqual(permission.all(), permission.resolveMember(&roles, owner, "99"));

    const ghost = schema.GuildMember{ .roles = &.{"10"} };
    try std.testing.expectEqual(@as(u64, 0), permission.resolveMember(&roles, ghost, "99"));
}

test "applyOverwrite denies then allows" {
    const base = permission.view_channel | permission.send_messages;
    const denied = permission.applyOverwrite(base, 0, permission.send_messages);
    try std.testing.expect(!permission.has(denied, permission.send_messages));
    try std.testing.expect(permission.has(denied, permission.view_channel));
    const allowed = permission.applyOverwrite(denied, permission.send_messages, 0);
    try std.testing.expectEqual(base, allowed);
}

test "resolveChannelPermissions follows docs order" {
    const overwrites = [_]schema.PermissionOverwrite{
        .{ .id = "10", .@"type" = 0, .allow = "0", .deny = "2048" },
        .{ .id = "20", .@"type" = 0, .allow = "2048", .deny = "0" },
        .{ .id = "5", .@"type" = 1, .allow = "0", .deny = "1024" },
    };
    const base = permission.view_channel | permission.send_messages | permission.manage_messages;
    const resolved = permission.resolveChannelPermissions(base, "5", &.{ "10", "20" }, "10", &overwrites);
    try std.testing.expect(permission.has(resolved, permission.send_messages));
    try std.testing.expect(!permission.has(resolved, permission.view_channel));
    try std.testing.expect(permission.has(resolved, permission.manage_messages));

    const admin_base = permission.resolveChannelPermissions(permission.administrator, "5", &.{}, "10", &overwrites);
    try std.testing.expectEqual(permission.all(), admin_base);
}

test "compareRolePositions orders by position then id" {
    const low = schema.Role{ .id = "1", .name = "a", .position = 1 };
    const high = schema.Role{ .id = "2", .name = "b", .position = 5 };
    try std.testing.expectEqual(std.math.Order.lt, permission.compareRolePositions(low, high));
    try std.testing.expectEqual(std.math.Order.gt, permission.compareRolePositions(high, low));
    try std.testing.expectEqual(std.math.Order.eq, permission.compareRolePositions(low, low));
    const same_pos_low_id = schema.Role{ .id = "1", .name = "a", .position = 3 };
    const same_pos_high_id = schema.Role{ .id = "9", .name = "b", .position = 3 };
    try std.testing.expectEqual(std.math.Order.lt, permission.compareRolePositions(same_pos_low_id, same_pos_high_id));
}
