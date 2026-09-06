const std = @import("std");
const message = @import("discord-zig").message;

test "flag values match discord.js" {
    try std.testing.expectEqual(@as(u32, 1), message.crossposted);
    try std.testing.expectEqual(@as(u32, 2), message.is_crossposted);
    try std.testing.expectEqual(@as(u32, 4), message.suppress_embeds);
    try std.testing.expectEqual(@as(u32, 8), message.source_message_deleted);
    try std.testing.expectEqual(@as(u32, 16), message.urgent);
    try std.testing.expectEqual(@as(u32, 32), message.has_thread);
    try std.testing.expectEqual(@as(u32, 64), message.ephemeral);
    try std.testing.expectEqual(@as(u32, 128), message.loading);
    try std.testing.expectEqual(@as(u32, 256), message.failed_to_mention_some_roles_in_thread);
    try std.testing.expectEqual(@as(u32, 4096), message.suppress_notifications);
    try std.testing.expectEqual(@as(u32, 8192), message.is_voice_message);
    try std.testing.expectEqual(@as(u32, 16384), message.has_snapshot);
    try std.testing.expectEqual(@as(u32, 32768), message.is_components_v2);
}

test "has checks bits" {
    const v = message.ephemeral | message.loading;
    try std.testing.expect(message.has(v, message.ephemeral));
    try std.testing.expect(!message.has(v, message.suppress_embeds));
}

test "of combines flags like discord.js array" {
    const MF = message.MessageFlags;
    const v = message.of(.{ MF.Ephemeral, MF.SuppressNotifications });
    try std.testing.expectEqual(message.ephemeral | message.suppress_notifications, v);
}

test "of accepts single flag and mixed values" {
    const MF = message.MessageFlags;
    try std.testing.expectEqual(message.loading, message.of(MF.Loading));
    try std.testing.expectEqual(
        message.ephemeral | message.urgent,
        message.of(.{ MF.Ephemeral, message.Bits.urgent, 0 }),
    );
}

test "of empty is zero" {
    try std.testing.expectEqual(@as(u32, 0), message.of(.{}));
}

test "MessageFlags matches discord.js values" {
    try std.testing.expectEqual(@as(u32, 64), message.MessageFlags.Ephemeral);
    try std.testing.expectEqual(message.ephemeral, message.MessageFlags.Ephemeral);
    try std.testing.expectEqual(message.suppress_notifications, message.MessageFlags.SuppressNotifications);
    try std.testing.expectEqual(message.suppress_embeds, message.MessageFlags.SuppressEmbeds);
    try std.testing.expectEqual(message.loading, message.MessageFlags.Loading);
    try std.testing.expectEqual(
        message.ephemeral | message.suppress_notifications,
        message.of(.{ message.MessageFlags.Ephemeral, message.MessageFlags.SuppressNotifications }),
    );
}

test "Flags init from tuple like discord.js array" {
    const MF = message.MessageFlags;
    const f = message.Flags.init(.{ MF.Ephemeral, MF.SuppressNotifications });
    try std.testing.expectEqual(message.ephemeral | message.suppress_notifications, f.bits);
    try std.testing.expectEqual(@as(u32, 0), (message.Flags{}).bits);
}

test "Flags has add remove" {
    const MF = message.MessageFlags;
    var f = message.Flags.init(.{MF.Ephemeral});
    try std.testing.expect(f.has(MF.Ephemeral));
    try std.testing.expect(!f.has(MF.Loading));
    f.add(.{ MF.Loading, MF.SuppressEmbeds });
    try std.testing.expect(f.has(MF.Loading));
    try std.testing.expect(f.has(MF.SuppressEmbeds));
    f.remove(.{MF.Ephemeral});
    try std.testing.expect(!f.has(MF.Ephemeral));
    try std.testing.expect(f.has(MF.Loading));
}
