const std = @import("std");
const discord = @import("discord-zig");
const Client = discord.client.Client;
const Events = discord.events.Events;

const GatewayIntentBits = discord.GatewayIntentBits;

pub fn main(init: std.process.Init) !void {
    const token = init.environ_map.get("DISCORD_TOKEN") orelse {
        std.debug.print("missing DISCORD_TOKEN\n", .{});
        std.process.exit(1);
    };

    var client = Client.init(init.gpa, init.io, .{
        .intents = .{
            GatewayIntentBits.Guilds,
            GatewayIntentBits.GuildMessages,
            GatewayIntentBits.MessageContent,
        },
    });
    defer client.deinit();

    client.on(Events.MessageCreate, onMessage);
    client.once(Events.ClientReady, onReady);

    try client.login(token);
}

fn onReady(c: *Client, ready: discord.schema.Ready) void {
    const t = ready.user.tag(c.allocator) catch return;
    defer c.allocator.free(t);
    std.debug.print("ready: {s}\n", .{t});
}

fn onMessage(_c: *Client, msg: discord.schema.Message) void {
    _ = _c;
    std.debug.print("message: {s}\n", .{msg.content});
}
