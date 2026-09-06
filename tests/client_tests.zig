const std = @import("std");
const Rest = @import("discord-zig").client.Rest;
const Client = @import("discord-zig").client.Client;
const parseBody = @import("discord-zig").client.parseBody;
const schema = @import("discord-zig").schema;
const websockets = @import("discord-zig").websockets;
const util = @import("discord-zig").util;
const channel_mod = @import("discord-zig").channel;
const guild_mod = @import("discord-zig").guild;
const member_mod = @import("discord-zig").member;
const poll_mod = @import("discord-zig").poll;
const attachment_mod = @import("discord-zig").attachment;
const slash_mod = @import("discord-zig").slash;

test "url and auth building" {
    var c = Rest.init(std.testing.allocator, std.testing.io, "token123");
    defer c.deinit();
    const url = try c.urlFor(std.testing.allocator, "/users/@me");
    defer std.testing.allocator.free(url);
    try std.testing.expectEqualStrings("https://discord.com/api/v10/users/@me", url);
    const auth = try c.authHeader(std.testing.allocator);
    defer std.testing.allocator.free(auth);
    try std.testing.expectEqualStrings("Bot token123", auth);
}

test "ensure success mapping" {
    try Rest.ensureSuccess(.{
        .status = .ok,
        .status_code = 200,
        .rate_limit = .{},
        .retry_after = null,
        .body = @constCast(@as([]const u8, "")),
    });
    try std.testing.expectError(error.Unauthorized, Rest.ensureSuccess(.{
        .status = .unauthorized,
        .status_code = 401,
        .rate_limit = .{},
        .retry_after = null,
        .body = @constCast(@as([]const u8, "")),
    }));
    try std.testing.expectError(error.RateLimited, Rest.ensureSuccess(.{
        .status = .too_many_requests,
        .status_code = 429,
        .rate_limit = .{},
        .retry_after = 1.0,
        .body = @constCast(@as([]const u8, "")),
    }));
}

test "non-JSON 200 body maps to InvalidResponseBody" {
    const html = "<html><body>blocked</body></html>";
    try std.testing.expectError(
        error.InvalidResponseBody,
        parseBody(schema.User, std.testing.allocator, 200, html),
    );
    try std.testing.expectError(
        error.InvalidResponseBody,
        parseBody(schema.User, std.testing.allocator, 200, ""),
    );
    var ok = try parseBody(
        schema.User,
        std.testing.allocator,
        200,
        "{\"id\":\"1\",\"username\":\"bot\"}",
    );
    defer ok.deinit();
    try std.testing.expectEqualStrings("bot", ok.value.username);
}

var on_calls: u32 = 0;
var once_calls: u32 = 0;
var second_calls: u32 = 0;
var reaction_calls: u32 = 0;
var last_emoji: ?[]const u8 = null;

fn onMessage(_: *Client, _: schema.Message) void {
    on_calls += 1;
}

fn onMessageAgain(_: *Client, _: schema.Message) void {
    second_calls += 1;
}

fn onReady(_: *Client, _: schema.Ready) void {
    once_calls += 1;
}

fn onReaction(_: *Client, r: schema.MessageReaction) void {
    reaction_calls += 1;
    last_emoji = r.emoji.name;
}

test "second registration overwrites slot" {
    on_calls = 0;
    second_calls = 0;
    var c = Client.init(std.testing.allocator, std.testing.io, .{});
    defer c.deinit();
    c.on(.message_create, onMessage);
    c.on(.message_create, onMessageAgain);
    const msg: schema.Message = .{ .id = "1", .channel_id = "2", .author = .{ .id = "3", .username = "bot" } };
    c.emit(.message_create, msg);
    try std.testing.expectEqual(@as(u32, 0), on_calls);
    try std.testing.expectEqual(@as(u32, 1), second_calls);
}

test "on fires every emit" {
    on_calls = 0;
    var c = Client.init(std.testing.allocator, std.testing.io, .{});
    defer c.deinit();
    c.on(.message_create, onMessage);
    const msg: schema.Message = .{ .id = "1", .channel_id = "2", .author = .{ .id = "3", .username = "bot" } };
    c.emit(.message_create, msg);
    c.emit(.message_create, msg);
    try std.testing.expectEqual(@as(u32, 2), on_calls);
}

test "once fires a single time" {
    once_calls = 0;
    var c = Client.init(std.testing.allocator, std.testing.io, .{});
    defer c.deinit();
    c.once("ready", onReady);
    const ready: schema.Ready = .{ .session_id = "s", .resume_gateway_url = "u", .user = .{ .id = "1", .username = "bot" } };
    c.emit(.ready, ready);
    c.emit(.ready, ready);
    try std.testing.expectEqual(@as(u32, 1), once_calls);
}

test "off clears handlers" {
    on_calls = 0;
    var c = Client.init(std.testing.allocator, std.testing.io, .{});
    defer c.deinit();
    c.on("messageCreate", onMessage);
    c.off(.message_create);
    const msg: schema.Message = .{ .id = "1", .channel_id = "2", .author = .{ .id = "3", .username = "bot" } };
    c.emit(.message_create, msg);
    try std.testing.expectEqual(@as(u32, 0), on_calls);
}

test "on accepts Events enum" {
    const Events = @import("discord-zig").events.Events;
    on_calls = 0;
    once_calls = 0;
    var c = Client.init(std.testing.allocator, std.testing.io, .{});
    defer c.deinit();
    c.on(Events.MessageCreate, onMessage);
    c.once(Events.ClientReady, onReady);
    const msg: schema.Message = .{ .id = "1", .channel_id = "2", .author = .{ .id = "3", .username = "bot" } };
    c.emit(.message_create, msg);
    try std.testing.expectEqual(@as(u32, 1), on_calls);
    const ready: schema.Ready = .{ .session_id = "s", .resume_gateway_url = "u", .user = .{ .id = "1", .username = "bot" } };
    c.emit(.ready, ready);
    c.emit(.ready, ready);
    try std.testing.expectEqual(@as(u32, 1), once_calls);
}

test "reaction handlers receive emoji" {
    reaction_calls = 0;
    last_emoji = null;
    var c = Client.init(std.testing.allocator, std.testing.io, .{});
    defer c.deinit();
    c.on("messageReactionAdd", onReaction);
    c.emit(.message_reaction_add, .{
        .user_id = "7",
        .channel_id = "9",
        .message_id = "42",
        .emoji = .{ .name = "🔥" },
    });
    try std.testing.expectEqual(@as(u32, 1), reaction_calls);
    try std.testing.expectEqualStrings("🔥", last_emoji.?);
}

const GwMockCtx = struct {
    server: *std.Io.net.Server,
    err: ?anyerror = error.ServerDidNotFinish,
};

fn gwReadFull(io: std.Io, stream: *std.Io.net.Stream, buf: []u8) !void {
    var off: usize = 0;
    while (off < buf.len) {
        var pfd = [_]std.posix.pollfd{.{ .fd = stream.socket.handle, .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = try std.posix.poll(&pfd, 10000);
        if (ready == 0) return error.Timeout;
        var data = [_][]u8{buf[off..]};
        const n = try io.vtable.netRead(io.userdata, stream.socket.handle, &data);
        if (n == 0) return error.ConnectionClosed;
        off += n;
    }
}

fn gwWriteAll(io: std.Io, stream: *std.Io.net.Stream, data: []const u8) !void {
    var wbuf: [4096]u8 = undefined;
    var w = stream.writer(io, &wbuf);
    try w.interface.writeAll(data);
    try w.interface.flush();
}

fn gwSendText(io: std.Io, stream: *std.Io.net.Stream, text: []const u8) !void {
    var hb: [10]u8 = undefined;
    const header = websockets.encodeHeader(0x1, text.len, &hb);
    try gwWriteAll(io, stream, header);
    try gwWriteAll(io, stream, text);
}

fn gwReadMaskedText(io: std.Io, stream: *std.Io.net.Stream, payload: []u8) ![]u8 {
    var hb: [2]u8 = undefined;
    try gwReadFull(io, stream, &hb);
    if (hb[0] & 0x0F != 0x1) return error.ExpectedText;
    if (hb[1] & 0x80 == 0) return error.ExpectedMask;
    var len: usize = hb[1] & 0x7F;
    if (len == 126) {
        var eb: [2]u8 = undefined;
        try gwReadFull(io, stream, &eb);
        len = std.mem.readInt(u16, &eb, .big);
    } else if (len == 127) {
        return error.FrameTooLarge;
    }
    if (len > payload.len) return error.FrameTooLarge;
    var mask: [4]u8 = undefined;
    try gwReadFull(io, stream, &mask);
    try gwReadFull(io, stream, payload[0..len]);
    websockets.applyMask(mask, payload[0..len]);
    return payload[0..len];
}

fn gwServerMain(ctx: *GwMockCtx) void {
    gwServerRun(ctx) catch |err| {
        ctx.err = err;
        return;
    };
    ctx.err = null;
}

fn gwServerRun(ctx: *GwMockCtx) !void {
    const io = std.testing.io;
    var stream = try ctx.server.accept(io);
    defer stream.close(io);

    var req_buf: [4096]u8 = undefined;
    var req_len: usize = 0;
    while (true) {
        if (req_len >= req_buf.len) return error.RequestTooLarge;
        var byte: [1]u8 = undefined;
        try gwReadFull(io, &stream, &byte);
        req_buf[req_len] = byte[0];
        req_len += 1;
        if (req_len >= 4 and std.mem.eql(u8, req_buf[req_len - 4 .. req_len], "\r\n\r\n")) break;
    }
    var key: []const u8 = "";
    var lines = std.mem.splitSequence(u8, req_buf[0..req_len], "\r\n");
    _ = lines.first();
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), "sec-websocket-key")) {
            key = std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
    }
    if (key.len == 0) return error.MissingKey;
    var accept: [28]u8 = undefined;
    websockets.acceptKey(key, &accept);
    var resp_buf: [256]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept});
    try gwWriteAll(io, &stream, resp);

    try gwSendText(io, &stream, "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}");

    var frame_buf: [4096]u8 = undefined;
    const identify = try gwReadMaskedText(io, &stream, &frame_buf);
    if (std.mem.indexOf(u8, identify, "\"op\":2") == null) return error.ScriptMismatch;

    try gwSendText(io, &stream, "{\"op\":0,\"s\":1,\"t\":\"READY\",\"d\":{\"session_id\":\"s1\",\"resume_gateway_url\":\"wss://x\",\"user\":{\"id\":\"1\",\"username\":\"bot\"}}}");
    try gwSendText(io, &stream, "{\"op\":0,\"s\":2,\"t\":\"MESSAGE_CREATE\",\"d\":{\"id\":\"10\",\"channel_id\":\"20\",\"author\":{\"id\":\"3\",\"username\":\"ann\"},\"content\":\"hello\"}}");
    try gwSendText(io, &stream, "{\"op\":1,\"d\":null}");

    const hb = try gwReadMaskedText(io, &stream, &frame_buf);
    if (std.mem.indexOf(u8, hb, "\"op\":1") == null) return error.ScriptMismatch;

    try gwWriteAll(io, &stream, "\x88\x00");
}

var gw_ready_calls: u32 = 0;
var gw_msg_calls: u32 = 0;
var gw_content: ?[]u8 = null;

fn gwOnReady(_: *Client, _: schema.Ready) void {
    gw_ready_calls += 1;
}

fn gwOnMessage(c: *Client, m: schema.Message) void {
    gw_msg_calls += 1;
    gw_content = c.allocator.dupe(u8, m.content) catch return;
}

test "gateway loop dispatches promptly" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var srv: std.Io.net.Server = undefined;
    var chosen: u16 = 0;
    for ([_]u16{ 18661, 18662, 18663, 18664, 18665 }) |p| {
        var addr = std.Io.net.IpAddress{ .ip4 = .loopback(p) };
        if (std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true })) |s| {
            srv = s;
            chosen = p;
            break;
        } else |_| continue;
    }
    if (chosen == 0) return error.CannotBindTestServer;
    defer srv.deinit(io);

    var ctx = GwMockCtx{ .server = &srv };
    const thread = try std.Thread.spawn(.{}, gwServerMain, .{&ctx});
    errdefer {
        _ = std.os.linux.shutdown(srv.socket.handle, std.os.linux.SHUT.RDWR);
        thread.join();
    }

    gw_ready_calls = 0;
    gw_msg_calls = 0;
    var c = Client.init(allocator, io, .{});
    defer c.deinit();
    c.session.config.token = "x";
    c.on(.message_create, gwOnMessage);
    c.once(.ready, gwOnReady);

    var sock = try websockets.connectOptions(io, allocator, .{
        .host = "127.0.0.1",
        .port = chosen,
        .path = "/?v=10&encoding=json",
        .tls = false,
    });
    defer sock.deinit();

    const t0 = util.nowMs(io);
    if (c.serve(&sock)) {
        return error.TestExpectedCloseError;
    } else |err| {
        try std.testing.expectEqual(error.GatewayReconnect, err);
    }
    const dt = util.nowMs(io) - t0;

    _ = std.os.linux.shutdown(srv.socket.handle, std.os.linux.SHUT.RDWR);
    thread.join();
    if (ctx.err) |e| {
        std.debug.print("mock gateway failed: {any}\n", .{e});
        return error.MockServerFailed;
    }
    try std.testing.expectEqual(@as(u32, 1), gw_ready_calls);
    try std.testing.expectEqual(@as(u32, 1), gw_msg_calls);
    try std.testing.expectEqualStrings("hello", gw_content.?);
    allocator.free(gw_content.?);
    gw_content = null;
    try std.testing.expect(dt < 10000);
}

const ReStep = union(enum) {
    send_text: []const u8,
    expect_op: u8,
    send_close: u16,
};

const ReMockCtx = struct {
    server: *std.Io.net.Server,
    scripts: []const []const ReStep,
    err: ?anyerror = error.ServerDidNotFinish,
    identifies: u32 = 0,
    resumes: u32 = 0,
    heartbeats: u32 = 0,
};

fn reServerMain(ctx: *ReMockCtx) void {
    reServerRun(ctx) catch |err| {
        ctx.err = err;
        return;
    };
    ctx.err = null;
}

fn reHandshake(io: std.Io, stream: *std.Io.net.Stream) !void {
    var req_buf: [4096]u8 = undefined;
    var req_len: usize = 0;
    while (true) {
        if (req_len >= req_buf.len) return error.RequestTooLarge;
        var byte: [1]u8 = undefined;
        try gwReadFull(io, stream, &byte);
        req_buf[req_len] = byte[0];
        req_len += 1;
        if (req_len >= 4 and std.mem.eql(u8, req_buf[req_len - 4 .. req_len], "\r\n\r\n")) break;
    }
    var key: []const u8 = "";
    var lines = std.mem.splitSequence(u8, req_buf[0..req_len], "\r\n");
    _ = lines.first();
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        if (std.ascii.eqlIgnoreCase(std.mem.trim(u8, line[0..colon], " \t"), "sec-websocket-key")) {
            key = std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
    }
    if (key.len == 0) return error.MissingKey;
    var accept: [28]u8 = undefined;
    websockets.acceptKey(key, &accept);
    var resp_buf: [256]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept});
    try gwWriteAll(io, stream, resp);
}

fn reServerRun(ctx: *ReMockCtx) !void {
    const io = std.testing.io;
    for (ctx.scripts) |steps| {
        var stream = try ctx.server.accept(io);
        defer stream.close(io);
        try reHandshake(io, &stream);
        var frame_buf: [4096]u8 = undefined;
        for (steps) |step| {
            switch (step) {
                .send_text => |text| try gwSendText(io, &stream, text),
                .expect_op => |op| {
                    const payload = try gwReadMaskedText(io, &stream, &frame_buf);
                    var needle: [8]u8 = undefined;
                    const n = try std.fmt.bufPrint(&needle, "\"op\":{d}", .{op});
                    if (std.mem.indexOf(u8, payload, n) == null) return error.ScriptMismatch;
                    switch (op) {
                        2 => ctx.identifies += 1,
                        6 => ctx.resumes += 1,
                        1 => ctx.heartbeats += 1,
                        else => {},
                    }
                },
                .send_close => |code| {
                    var hb: [10]u8 = undefined;
                    const header = websockets.encodeHeader(0x8, 2, &hb);
                    try gwWriteAll(io, &stream, header);
                    const hi: u8 = @intCast(code >> 8);
                    const lo: u8 = @intCast(code & 0xFF);
                    try gwWriteAll(io, &stream, &[_]u8{ hi, lo });
                },
            }
        }
    }
}

const ReSetup = struct {
    port: u16,
    server: std.Io.net.Server,
    thread: std.Thread,
    ctx: ReMockCtx,
    joined: bool = false,

    pub fn join(self: *ReSetup) void {
        if (!self.joined) {
            _ = std.os.linux.shutdown(self.server.socket.handle, std.os.linux.SHUT.RDWR);
            self.thread.join();
            self.joined = true;
        }
    }
};

fn withReconnectMock(scripts: []const []const ReStep) !*ReSetup {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const setup = try allocator.create(ReSetup);
    errdefer allocator.destroy(setup);
    var bound = false;
    for ([_]u16{ 18671, 18672, 18673, 18674, 18675 }) |p| {
        var addr = std.Io.net.IpAddress{ .ip4 = .loopback(p) };
        if (std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true })) |s| {
            setup.* = .{
                .port = p,
                .server = s,
                .thread = undefined,
                .ctx = .{ .server = undefined, .scripts = scripts },
            };
            bound = true;
            break;
        } else |_| continue;
    }
    if (!bound) return error.CannotBindTestServer;
    errdefer setup.server.deinit(io);
    setup.ctx.server = &setup.server;
    setup.thread = try std.Thread.spawn(.{}, reServerMain, .{&setup.ctx});
    return setup;
}

fn destroyReconnectMock(setup: *ReSetup) void {
    setup.join();
    setup.server.deinit(std.testing.io);
    std.testing.allocator.destroy(setup);
}

fn checkReconnectMock(setup: *ReSetup) !void {
    setup.join();
    if (setup.ctx.err) |e| {
        std.debug.print("mock gateway failed: {any}\n", .{e});
        return error.MockServerFailed;
    }
}

fn resumeUrlFor(allocator: std.mem.Allocator, port: u16) ![]u8 {
    return std.fmt.allocPrint(allocator, "ws://127.0.0.1:{d}/", .{port});
}

test "op 7 requests reconnect" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const conn = [_]ReStep{
        .{ .send_text = "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}" },
        .{ .expect_op = 2 },
        .{ .send_text = "{\"op\":7,\"d\":null}" },
    };
    const scripts = [_][]const ReStep{&conn};
    const setup = try withReconnectMock(&scripts);
    defer destroyReconnectMock(setup);

    var c = Client.init(allocator, io, .{});
    defer c.deinit();
    c.session.config.token = "x";

    var sock = try websockets.connectOptions(io, allocator, .{
        .host = "127.0.0.1",
        .port = setup.port,
        .path = "/?v=10&encoding=json",
        .tls = false,
    });
    defer sock.deinit();
    try std.testing.expectError(error.GatewayReconnect, c.serve(&sock));
    try checkReconnectMock(setup);
    try std.testing.expectEqual(@as(u32, 1), setup.ctx.identifies);
}

test "op 9 resumable requests reconnect" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const conn = [_]ReStep{
        .{ .send_text = "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}" },
        .{ .expect_op = 2 },
        .{ .send_text = "{\"op\":9,\"d\":true}" },
    };
    const scripts = [_][]const ReStep{&conn};
    const setup = try withReconnectMock(&scripts);
    defer destroyReconnectMock(setup);

    var c = Client.init(allocator, io, .{});
    defer c.deinit();
    c.session.config.token = "x";

    var sock = try websockets.connectOptions(io, allocator, .{
        .host = "127.0.0.1",
        .port = setup.port,
        .path = "/?v=10&encoding=json",
        .tls = false,
    });
    defer sock.deinit();
    try std.testing.expectError(error.GatewayReconnect, c.serve(&sock));
    try checkReconnectMock(setup);
}

test "op 9 fatal reidentifies and clears session" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const conn = [_]ReStep{
        .{ .send_text = "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}" },
        .{ .expect_op = 6 },
        .{ .send_text = "{\"op\":9,\"d\":false}" },
    };
    const scripts = [_][]const ReStep{&conn};
    const setup = try withReconnectMock(&scripts);
    defer destroyReconnectMock(setup);

    var c = Client.init(allocator, io, .{});
    defer c.deinit();
    c.session.config.token = "x";
    try c.session.storeReady("s1", "wss://x");
    c.session.trackDispatch(7);

    var sock = try websockets.connectOptions(io, allocator, .{
        .host = "127.0.0.1",
        .port = setup.port,
        .path = "/?v=10&encoding=json",
        .tls = false,
    });
    defer sock.deinit();
    try std.testing.expectError(error.GatewayReidentify, c.serve(&sock));
    try checkReconnectMock(setup);
    try std.testing.expectEqual(@as(u32, 1), setup.ctx.resumes);
    try std.testing.expect(c.session.session_id == null);
    try std.testing.expect(c.session.seq == null);
}

test "resumeable close requests reconnect" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const conn = [_]ReStep{
        .{ .send_text = "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}" },
        .{ .expect_op = 2 },
        .{ .send_close = 4000 },
    };
    const scripts = [_][]const ReStep{&conn};
    const setup = try withReconnectMock(&scripts);
    defer destroyReconnectMock(setup);

    var c = Client.init(allocator, io, .{});
    defer c.deinit();
    c.session.config.token = "x";

    var sock = try websockets.connectOptions(io, allocator, .{
        .host = "127.0.0.1",
        .port = setup.port,
        .path = "/?v=10&encoding=json",
        .tls = false,
    });
    defer sock.deinit();
    try std.testing.expectError(error.GatewayReconnect, c.serve(&sock));
    try checkReconnectMock(setup);
}

test "fatal close returns GatewayClosed" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const conn = [_]ReStep{
        .{ .send_text = "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}" },
        .{ .expect_op = 2 },
        .{ .send_close = 4014 },
    };
    const scripts = [_][]const ReStep{&conn};
    const setup = try withReconnectMock(&scripts);
    defer destroyReconnectMock(setup);

    var c = Client.init(allocator, io, .{});
    defer c.deinit();
    c.session.config.token = "x";

    var sock = try websockets.connectOptions(io, allocator, .{
        .host = "127.0.0.1",
        .port = setup.port,
        .path = "/?v=10&encoding=json",
        .tls = false,
    });
    defer sock.deinit();
    try std.testing.expectError(error.GatewayClosed, c.serve(&sock));
    try checkReconnectMock(setup);
}

test "serveForever reconnects and resumes" {
    const allocator = std.testing.allocator;
    const io = std.testing.io;
    const conn1 = [_]ReStep{
        .{ .send_text = "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}" },
        .{ .expect_op = 6 },
        .{ .send_text = "{\"op\":7,\"d\":null}" },
    };
    const conn2 = [_]ReStep{
        .{ .send_text = "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}" },
        .{ .expect_op = 6 },
        .{ .send_text = "{\"op\":1,\"d\":null}" },
        .{ .expect_op = 1 },
        .{ .send_close = 4014 },
    };
    const scripts = [_][]const ReStep{ &conn1, &conn2 };
    const setup = try withReconnectMock(&scripts);
    defer destroyReconnectMock(setup);

    var c = Client.init(allocator, io, .{});
    defer c.deinit();
    c.session.config.token = "x";
    const url = try resumeUrlFor(allocator, setup.port);
    defer allocator.free(url);
    try c.session.storeReady("s1", url);
    c.session.trackDispatch(5);

    try std.testing.expectError(error.GatewayClosed, c.serveForever());
    try checkReconnectMock(setup);
    try std.testing.expectEqual(@as(u32, 0), setup.ctx.identifies);
    try std.testing.expectEqual(@as(u32, 2), setup.ctx.resumes);
    try std.testing.expectEqual(@as(u32, 1), setup.ctx.heartbeats);
}

const HttpScriptCtx = struct {
    server: *std.Io.net.Server,
    err: ?anyerror = error.ServerDidNotFinish,
    hits: usize = 0,
    want: usize = 0,
    mode: HttpScriptMode = .rate_limit_then_ok,
    stop: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
};

const HttpScriptMode = enum {
    rate_limit_then_ok,
    blackhole,
};

fn httpScriptReadFull(io: std.Io, stream: *std.Io.net.Stream, buf: []u8) !void {
    var off: usize = 0;
    while (off < buf.len) {
        var pfd = [_]std.posix.pollfd{.{ .fd = stream.socket.handle, .events = std.posix.POLL.IN, .revents = 0 }};
        const ready = try std.posix.poll(&pfd, 10000);
        if (ready == 0) return error.Timeout;
        var data = [_][]u8{buf[off..]};
        const n = try io.vtable.netRead(io.userdata, stream.socket.handle, &data);
        if (n == 0) return error.ConnectionClosed;
        off += n;
    }
}

fn httpScriptWriteAll(io: std.Io, stream: *std.Io.net.Stream, data: []const u8) !void {
    var wbuf: [4096]u8 = undefined;
    var w = stream.writer(io, &wbuf);
    try w.interface.writeAll(data);
    try w.interface.flush();
}

fn httpScriptMain(ctx: *HttpScriptCtx) void {
    httpScriptRun(ctx) catch |err| {
        ctx.err = err;
        return;
    };
    ctx.err = null;
}

fn httpScriptRun(ctx: *HttpScriptCtx) !void {
    const io = std.testing.io;
    while (ctx.hits < ctx.want) {
        var stream = try ctx.server.accept(io);
        defer stream.close(io);
        ctx.hits += 1;

        var head_buf: [8192]u8 = undefined;
        var head_len: usize = 0;
        while (true) {
            if (head_len >= head_buf.len) return error.RequestTooLarge;
            var byte: [1]u8 = undefined;
            try httpScriptReadFull(io, &stream, &byte);
            head_buf[head_len] = byte[0];
            head_len += 1;
            if (head_len >= 4 and std.mem.eql(u8, head_buf[head_len - 4 .. head_len], "\r\n\r\n")) break;
        }

        switch (ctx.mode) {
            .rate_limit_then_ok => {
                if (ctx.hits == 1) {
                    const body = "{\"message\":\"slow down\",\"retry_after\":0.01,\"global\":false}";
                    var resp_buf: [256]u8 = undefined;
                    const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 429 Too Many Requests\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ body.len, body });
                    try httpScriptWriteAll(io, &stream, resp);
                } else {
                    const body = "{\"id\":\"1\",\"username\":\"bot\"}";
                    var resp_buf: [256]u8 = undefined;
                    const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ body.len, body });
                    try httpScriptWriteAll(io, &stream, resp);
                }
            },
            .blackhole => {
                var waited: u32 = 0;
                while (!ctx.stop.load(.acquire) and waited < 120_000) {
                    io.sleep(.{ .nanoseconds = 50 * std.time.ns_per_ms }, .awake) catch {};
                    waited += 50;
                }
            },
        }
    }
}

const HttpScriptSetup = struct {
    port: u16,
    server: std.Io.net.Server,
    thread: std.Thread,
    ctx: HttpScriptCtx,
};

fn withHttpScript(mode: HttpScriptMode, want: usize) !*HttpScriptSetup {
    const io = std.testing.io;
    const setup = try std.testing.allocator.create(HttpScriptSetup);
    errdefer std.testing.allocator.destroy(setup);

    var bound = false;
    for ([_]u16{ 18571, 18572, 18573 }) |p| {
        var addr = std.Io.net.IpAddress{ .ip4 = .loopback(p) };
        if (std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true })) |s| {
            setup.* = .{
                .port = p,
                .server = s,
                .thread = undefined,
                .ctx = .{ .server = undefined, .want = want, .mode = mode },
            };
            bound = true;
            break;
        } else |_| continue;
    }
    if (!bound) return error.CannotBindTestServer;
    errdefer setup.server.deinit(io);

    setup.ctx.server = &setup.server;
    setup.thread = try std.Thread.spawn(.{}, httpScriptMain, .{&setup.ctx});
    return setup;
}

fn destroyHttpScript(setup: *HttpScriptSetup) void {
    setup.ctx.stop.store(true, .release);
    _ = std.os.linux.shutdown(setup.server.socket.handle, std.os.linux.SHUT.RDWR);
    setup.thread.join();
    setup.server.deinit(std.testing.io);
    std.testing.allocator.destroy(setup);
}

test "rate limited request retries then succeeds" {
    const allocator = std.testing.allocator;
    const setup = try withHttpScript(.rate_limit_then_ok, 2);
    defer destroyHttpScript(setup);

    var rest = Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var me = try rest.getCurrentUser();
    defer me.deinit();
    try std.testing.expectEqualStrings("1", me.value.id);
    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 2), setup.ctx.hits);
}

test "hung request fails fast with timeout" {
    const allocator = std.testing.allocator;
    const setup = try withHttpScript(.blackhole, 1);
    defer destroyHttpScript(setup);

    var rest = Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);
    rest.timeout_ns = 300 * std.time.ns_per_ms;

    const t0 = util.nowMs(std.testing.io);
    try std.testing.expectError(error.Timeout, rest.getCurrentUser());
    const elapsed = util.nowMs(std.testing.io) - t0;
    try std.testing.expect(elapsed < 15000);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.hits);
}

const CrudReq = struct {
    method: [8]u8 = [_]u8{0} ** 8,
    method_len: usize = 0,
    path: [256]u8 = [_]u8{0} ** 256,
    path_len: usize = 0,
    body: [1024]u8 = [_]u8{0} ** 1024,
    body_len: usize = 0,
    reason: [128]u8 = [_]u8{0} ** 128,
    reason_len: usize = 0,

    fn methodStr(self: *const CrudReq) []const u8 {
        return self.method[0..self.method_len];
    }

    fn pathStr(self: *const CrudReq) []const u8 {
        return self.path[0..self.path_len];
    }

    fn bodyStr(self: *const CrudReq) []const u8 {
        return self.body[0..self.body_len];
    }

    fn reasonStr(self: *const CrudReq) []const u8 {
        return self.reason[0..self.reason_len];
    }
};

const CrudMockCtx = struct {
    server: *std.Io.net.Server,
    err: ?anyerror = null,
    reqs: [32]CrudReq = [_]CrudReq{.{}} ** 32,
    count: usize = 0,
    want: usize = 0,
};

const crud_msg = "{\"id\":\"M\",\"channel_id\":\"C\",\"author\":{\"id\":\"U\",\"username\":\"u\"},\"content\":\"hi\"}";
const crud_msg_list = "[{\"id\":\"100\",\"channel_id\":\"C\",\"author\":{\"id\":\"5\",\"username\":\"w\"},\"content\":\"yo\"}]";
const crud_users = "[{\"id\":\"9\",\"username\":\"z\"}]";
const crud_channel = "{\"id\":\"C\",\"type\":0,\"name\":\"general\"}";
const crud_guild = "{\"id\":\"G\",\"name\":\"srv\"}";
const crud_guild_list = "[{\"id\":\"G\",\"name\":\"srv\"}]";
const crud_member = "{\"user\":{\"id\":\"U\",\"username\":\"u\"},\"roles\":[],\"joined_at\":\"\",\"guild_id\":\"\"}";
const crud_member_list = "[{\"user\":{\"id\":\"U\",\"username\":\"u\"},\"roles\":[],\"joined_at\":\"\",\"guild_id\":\"\"}]";
const crud_role = "{\"id\":\"R\",\"name\":\"mod\",\"permissions\":\"8\",\"color\":0,\"hoist\":false,\"mentionable\":false,\"managed\":false,\"position\":1}";
const crud_role_list = "[{\"id\":\"R\",\"name\":\"mod\",\"permissions\":\"8\",\"color\":0,\"hoist\":false,\"mentionable\":false,\"managed\":false,\"position\":1}]";
const crud_ban = "{\"reason\":\"spam\",\"user\":{\"id\":\"U\",\"username\":\"u\"}}";
const crud_voters = "{\"users\":[{\"id\":\"9\",\"username\":\"z\"}]}";
const crud_user = "{\"id\":\"U\",\"username\":\"u\"}";
const crud_invite = "{\"code\":\"ABC\",\"max_age\":0,\"max_uses\":0,\"temporary\":false,\"uses\":0}";
const crud_invite_list = "[{\"code\":\"ABC\",\"max_age\":0,\"max_uses\":0,\"temporary\":false,\"uses\":0}]";
const crud_channels_list = "[{\"id\":\"C\",\"type\":0,\"name\":\"general\"}]";
const crud_thread_active = "{\"threads\":[],\"members\":[],\"has_more\":false}";
const crud_audit = "{\"entries\":[{\"id\":\"1\",\"action_type\":1}],\"users\":[]}";
const crud_onboarding = "{\"default_channel_ids\":[],\"enabled\":false,\"mode\":0}";
const crud_template = "{\"code\":\"T\",\"name\":\"t\"}";
const crud_template_list = "[{\"code\":\"T\",\"name\":\"t\"}]";
const crud_app_cmd = "{\"id\":\"C1\",\"application_id\":\"A\",\"name\":\"ping\",\"description\":\"x\",\"type\":1}";
const crud_app_cmd_list = "[{\"id\":\"C1\",\"application_id\":\"A\",\"name\":\"ping\",\"description\":\"x\",\"type\":1}]";
const crud_cmd_perms = "{\"id\":\"C1\",\"application_id\":\"A\",\"guild_id\":\"G\",\"permissions\":[]}";
const crud_cmd_perms_list = "[{\"id\":\"C1\",\"application_id\":\"A\",\"guild_id\":\"G\",\"permissions\":[]}]";
const crud_webhook = "{\"id\":\"W\",\"channel_id\":\"C\",\"name\":\"hook\"}";
const crud_vanity = "{\"code\":\"vip\",\"uses\":7}";
const crud_prune = "{\"pruned\":3}";
const crud_bulkban = "{\"banned_users\":[\"1\",\"2\"]}";
const crud_thread_member = "{\"id\":\"th1\",\"user_id\":\"u1\",\"join_timestamp\":\"2026-01-01T00:00:00Z\"}";
const crud_thread_members_list = "[{\"id\":\"th1\",\"user_id\":\"u1\",\"join_timestamp\":\"2026-01-01T00:00:00Z\"}]";const crud_scheduled_event_users = "[{\"guild_scheduled_event_id\":\"ev1\",\"user\":{\"id\":\"u1\",\"username\":\"bob\"}}]";

fn crudRespond(io: std.Io, stream: *std.Io.net.Stream, status: []const u8, body: []const u8) !void {
    var resp_buf: [256]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 {s}\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{ status, body.len });
    try httpScriptWriteAll(io, stream, resp);
    if (body.len > 0) try httpScriptWriteAll(io, stream, body);
}

fn crudMain(ctx: *CrudMockCtx) void {
    crudRun(ctx) catch |err| {
        ctx.err = err;
        return;
    };
    ctx.err = null;
}

fn crudRun(ctx: *CrudMockCtx) !void {
    const io = std.testing.io;
    while (ctx.count < ctx.want) {
        var stream = try ctx.server.accept(io);
        defer stream.close(io);
        var slot = &ctx.reqs[ctx.count];
        ctx.count += 1;

        var head_buf: [8192]u8 = undefined;
        var head_len: usize = 0;
        while (true) {
            if (head_len >= head_buf.len) return error.RequestTooLarge;
            var byte: [1]u8 = undefined;
            try httpScriptReadFull(io, &stream, &byte);
            head_buf[head_len] = byte[0];
            head_len += 1;
            if (head_len >= 4 and std.mem.eql(u8, head_buf[head_len - 4 .. head_len], "\r\n\r\n")) break;
        }

        var lines = std.mem.splitSequence(u8, head_buf[0..head_len], "\r\n");
        var parts = std.mem.splitScalar(u8, lines.first(), ' ');
        const method = parts.first();
        const path = parts.next() orelse return error.BadRequestLine;
        @memcpy(slot.method[0..method.len], method);
        slot.method_len = method.len;
        @memcpy(slot.path[0..path.len], path);
        slot.path_len = path.len;

        var content_len: usize = 0;
        var rest_lines = std.mem.splitSequence(u8, head_buf[0..head_len], "\r\n");
        _ = rest_lines.first();
        while (rest_lines.next()) |line| {
            if (line.len == 0) break;
            const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
            const name = std.mem.trim(u8, line[0..colon], " \t");
            const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
            if (std.ascii.eqlIgnoreCase(name, "content-length")) {
                content_len = try std.fmt.parseInt(usize, value, 10);
            }
            if (std.ascii.eqlIgnoreCase(name, "x-audit-log-reason")) {
                const n = @min(value.len, slot.reason.len);
                @memcpy(slot.reason[0..n], value[0..n]);
                slot.reason_len = n;
            }
        }
        if (content_len > slot.body.len) return error.BodyTooLarge;
        if (content_len > 0) try httpScriptReadFull(io, &stream, slot.body[0..content_len]);
        slot.body_len = content_len;

        const m = slot.methodStr();
        const p = slot.pathStr();
        const is_delete = std.mem.eql(u8, m, "DELETE");
        if (std.mem.indexOf(u8, p, "bulk-delete") != null) {
            try crudRespond(io, &stream, "204 No Content", "");
        } else if (std.mem.indexOf(u8, p, "/typing") != null) {
            try crudRespond(io, &stream, "204 No Content", "");
        } else if (std.mem.indexOf(u8, p, "/crosspost") != null) {
            try crudRespond(io, &stream, "200 OK", crud_msg);
        } else if (std.mem.indexOf(u8, p, "/reactions") != null) {
            if (std.mem.eql(u8, m, "GET")) {
                try crudRespond(io, &stream, "200 OK", crud_users);
            } else {
                try crudRespond(io, &stream, "204 No Content", "");
            }
        } else if (std.mem.indexOf(u8, p, "/pins") != null) {
            try crudRespond(io, &stream, "204 No Content", "");
        } else if (std.mem.indexOf(u8, p, "/threads") != null) {
            if (std.mem.eql(u8, m, "GET")) {
                try crudRespond(io, &stream, "200 OK", crud_thread_active);
            } else if (is_delete or std.mem.eql(u8, m, "PUT")) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else {
                try crudRespond(io, &stream, "200 OK", crud_channel);
            }
        } else if (std.mem.indexOf(u8, p, "/invites") != null) {
            if (is_delete) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else if (std.mem.eql(u8, m, "GET")) {
                try crudRespond(io, &stream, "200 OK", crud_invite_list);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_invite);
            }
        } else if (std.mem.indexOf(u8, p, "/thread-members") != null) {
            if (is_delete or std.mem.eql(u8, m, "PUT")) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else if (std.mem.indexOf(u8, p, "/thread-members/") != null) {
                try crudRespond(io, &stream, "200 OK", crud_thread_member);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_thread_members_list);
            }
        } else if (std.mem.indexOf(u8, p, "/scheduled-events") != null) {
            if (std.mem.indexOf(u8, p, "/users") != null) {
                try crudRespond(io, &stream, "200 OK", crud_scheduled_event_users);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_channel);
            }
        } else if (std.mem.indexOf(u8, p, "/messages?limit=") != null) {
            try crudRespond(io, &stream, "200 OK", crud_msg_list);
        } else if (std.mem.eql(u8, m, "POST") and std.mem.endsWith(u8, p, "/messages")) {
            try crudRespond(io, &stream, "200 OK", crud_msg);
        } else if (std.mem.indexOf(u8, p, "/messages/") != null) {
            if (is_delete) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else {
                try crudRespond(io, &stream, "200 OK", crud_msg);
            }
        } else if (std.mem.indexOf(u8, p, "/bans/") != null) {
            if (std.mem.eql(u8, m, "GET")) {
                try crudRespond(io, &stream, "200 OK", crud_ban);
            } else {
                try crudRespond(io, &stream, "204 No Content", "");
            }
        } else if (std.mem.indexOf(u8, p, "/members/search") != null) {
            try crudRespond(io, &stream, "200 OK", crud_member_list);
        } else if (std.mem.indexOf(u8, p, "/members/") != null and std.mem.indexOf(u8, p, "/roles/") != null) {
            try crudRespond(io, &stream, "204 No Content", "");
        } else if (std.mem.indexOf(u8, p, "/members") != null) {
            if (is_delete) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else if (std.mem.indexOf(u8, p, "?limit=") != null and std.mem.eql(u8, m, "GET")) {
                try crudRespond(io, &stream, "200 OK", crud_member_list);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_member);
            }
        } else if (std.mem.indexOf(u8, p, "/roles") != null) {
            if (is_delete) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else if (std.mem.eql(u8, m, "PATCH") and std.mem.endsWith(u8, p, "/roles")) {
                try crudRespond(io, &stream, "200 OK", crud_role_list);
            } else if (std.mem.eql(u8, m, "GET") and std.mem.endsWith(u8, p, "/roles")) {
                try crudRespond(io, &stream, "200 OK", crud_role_list);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_role);
            }
        } else if (std.mem.indexOf(u8, p, "/audit-logs") != null) {
            try crudRespond(io, &stream, "200 OK", crud_audit);
        } else if (std.mem.indexOf(u8, p, "/onboarding") != null) {
            try crudRespond(io, &stream, "200 OK", crud_onboarding);
        } else if (std.mem.indexOf(u8, p, "/templates") != null) {
            if (std.mem.eql(u8, m, "GET")) {
                try crudRespond(io, &stream, "200 OK", crud_template_list);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_template);
            }
        } else if (std.mem.indexOf(u8, p, "/applications/") != null) {
            if (is_delete) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else if (std.mem.indexOf(u8, p, "/permissions") != null) {
                if (std.mem.endsWith(u8, p, "/commands/permissions")) {
                    try crudRespond(io, &stream, "200 OK", crud_cmd_perms_list);
                } else {
                    try crudRespond(io, &stream, "200 OK", crud_cmd_perms);
                }
            } else if (std.mem.eql(u8, m, "GET") and std.mem.endsWith(u8, p, "/commands")) {
                try crudRespond(io, &stream, "200 OK", crud_app_cmd_list);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_app_cmd);
            }
        } else if (std.mem.indexOf(u8, p, "/webhooks") != null) {
            if (is_delete) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else if (std.mem.indexOf(u8, p, "/messages/") != null) {
                try crudRespond(io, &stream, "200 OK", crud_msg);
            } else if (std.mem.indexOf(u8, p, "?wait=") != null) {
                try crudRespond(io, &stream, "200 OK", crud_msg);
            } else if (std.mem.eql(u8, m, "GET")) {
                try crudRespond(io, &stream, "200 OK", crud_webhook);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_webhook);
            }
        } else if (std.mem.indexOf(u8, p, "/permissions/") != null) {
            try crudRespond(io, &stream, "204 No Content", "");
        } else if (std.mem.indexOf(u8, p, "/polls/") != null) {
            if (std.mem.eql(u8, m, "GET")) {
                try crudRespond(io, &stream, "200 OK", crud_voters);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_msg);
            }
        } else if (std.mem.eql(u8, m, "GET") and std.mem.indexOf(u8, p, "/guilds/") != null and std.mem.indexOf(u8, p, "/channels") != null) {
            try crudRespond(io, &stream, "200 OK", crud_channels_list);
        } else if (std.mem.indexOf(u8, p, "/channels") != null) {
            if (std.mem.eql(u8, m, "GET") and std.mem.indexOf(u8, p, "/guilds/") == null) {
                try crudRespond(io, &stream, "200 OK", crud_channel);
            } else if (is_delete and std.mem.indexOf(u8, p, "/guilds/") == null) {
                try crudRespond(io, &stream, "200 OK", crud_channel);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_channel);
            }
        } else if (std.mem.indexOf(u8, p, "/users/@me/guilds/") != null and std.mem.indexOf(u8, p, "/member") != null) {
            try crudRespond(io, &stream, "200 OK", crud_member);
        } else if (std.mem.indexOf(u8, p, "/users/@me/guilds") != null) {
            if (is_delete) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else {
                try crudRespond(io, &stream, "200 OK", crud_guild_list);
            }
        } else if (std.mem.indexOf(u8, p, "/users/") != null) {
            if (is_delete) {
                try crudRespond(io, &stream, "204 No Content", "");
            } else if (std.mem.eql(u8, m, "POST")) {
                try crudRespond(io, &stream, "200 OK", crud_channel);
            } else {
                try crudRespond(io, &stream, "200 OK", crud_user);
            }
        } else if (std.mem.indexOf(u8, p, "/vanity-url") != null) {
            try crudRespond(io, &stream, "200 OK", crud_vanity);
        } else if (std.mem.indexOf(u8, p, "/prune") != null) {
            try crudRespond(io, &stream, "200 OK", crud_prune);
        } else if (std.mem.indexOf(u8, p, "/bulk-ban") != null) {
            try crudRespond(io, &stream, "200 OK", crud_bulkban);
        } else if (std.mem.indexOf(u8, p, "/guilds/") != null) {
            try crudRespond(io, &stream, "200 OK", crud_guild);
        } else if (is_delete) {
            try crudRespond(io, &stream, "204 No Content", "");
        } else {
            try crudRespond(io, &stream, "200 OK", crud_msg);
        }
    }
}

const CrudMockSetup = struct {
    port: u16,
    server: std.Io.net.Server,
    thread: std.Thread,
    ctx: CrudMockCtx,
    joined: bool = false,

    pub fn join(self: *CrudMockSetup) void {
        if (!self.joined) {
            _ = std.os.linux.shutdown(self.server.socket.handle, std.os.linux.SHUT.RDWR);
            self.thread.join();
            self.joined = true;
        }
    }
};

fn withCrudMock(want: usize) !*CrudMockSetup {
    const io = std.testing.io;
    const setup = try std.testing.allocator.create(CrudMockSetup);
    errdefer std.testing.allocator.destroy(setup);

    var bound = false;
    for ([_]u16{ 18581, 18582, 18583 }) |p| {
        var addr = std.Io.net.IpAddress{ .ip4 = .loopback(p) };
        if (std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true })) |s| {
            setup.* = .{
                .port = p,
                .server = s,
                .thread = undefined,
                .ctx = .{ .server = undefined, .want = want, .err = null },
            };
            bound = true;
            break;
        } else |_| continue;
    }
    if (!bound) return error.CannotBindTestServer;
    errdefer setup.server.deinit(io);

    setup.ctx.server = &setup.server;
    setup.thread = try std.Thread.spawn(.{}, crudMain, .{&setup.ctx});
    return setup;
}

fn destroyCrudMock(setup: *CrudMockSetup) void {
    setup.join();
    setup.server.deinit(std.testing.io);
    std.testing.allocator.destroy(setup);
}

test "crud messages channels guilds members roles" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(28);
    defer destroyCrudMock(setup);

    var rest = Rest.init(allocator, std.testing.io, "tok");
    defer rest.deinit();
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    defer allocator.free(rest.base_url);

    var got = try rest.getMessage("C", "M");
    defer got.deinit();
    try std.testing.expectEqualStrings("M", got.value.id);

    var edited = try rest.editMessage("C", "M", "new");
    defer edited.deinit();
    try rest.deleteMessage("C", "M", "spam");
    try rest.react("C", "M", "🔥");
    try rest.typing("C");
    try rest.pinMessage("C", "M", "x");

    var chan = try rest.getChannel("C");
    defer chan.deinit();
    try std.testing.expectEqualStrings("general", chan.value.name.?);
    var created_chan = try rest.createGuildChannel("G", "chat", .guild_text);
    defer created_chan.deinit();
    var guild = try rest.getGuild("G");
    defer guild.deinit();
    try std.testing.expectEqualStrings("srv", guild.value.name);
    var member = try rest.getMember("G", "U");
    defer member.deinit();
    try rest.addRole("G", "U", "R", null);
    try rest.kick("G", "U", "bye");
    try rest.ban("G", "U", 0, null);
    var roles = try rest.listRoles("G");
    defer roles.deinit();
    try std.testing.expectEqual(@as(usize, 1), roles.value.len);
    var role = try rest.createRole("G", "mod", null);
    defer role.deinit();
    try std.testing.expectEqualStrings("R", role.value.id);
    var ban = try rest.getBan("G", "U");
    defer ban.deinit();
    try std.testing.expectEqualStrings("spam", ban.value.reason.?);
    var members = try rest.listMembers("G", 5, "0");
    defer members.deinit();
    try std.testing.expectEqual(@as(usize, 1), members.value.len);
    var nicked = try rest.editMemberNick("G", "U", "nick", null);
    defer nicked.deinit();
    var timed = try rest.timeoutMember("G", "U", null, null);
    defer timed.deinit();

    try std.testing.expect(try rest.awaitUserReaction("C", "M", "🔥", "9", 2000, 50));
    var waited = try rest.awaitMessage("C", "5", "0", 2000, 50);
    defer {
        if (waited) |*w| w.deinit();
    }
    try std.testing.expectEqualStrings("M", waited.?.value.id);
    try std.testing.expectEqualStrings("/channels/C/messages/100", setup.ctx.reqs[21].pathStr());

    try rest.deleteMessagesBulk("C", &.{"1"});
    try rest.unban("G", "U", null);
    var xposted = try rest.crosspost("C", "M");
    defer xposted.deinit();
    var guilds = try rest.listGuilds(10);
    defer guilds.deinit();
    try std.testing.expectEqual(@as(usize, 1), guilds.value.len);
    try rest.editChannelPermissions("C", "20", .role, 1024, 0, "mod");
    try rest.deleteChannelPermissions("C", "20", null);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 28), setup.ctx.count);

    try std.testing.expectEqualStrings("PATCH", setup.ctx.reqs[1].methodStr());
    try std.testing.expectEqualStrings("{\"content\":\"new\"}", setup.ctx.reqs[1].bodyStr());
    try std.testing.expectEqualStrings("spam", setup.ctx.reqs[2].reasonStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[3].pathStr(), "%F0%9F%94%A5") != null);
    try std.testing.expectEqualStrings("{\"name\":\"chat\",\"type\":0}", setup.ctx.reqs[7].bodyStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[12].bodyStr(), "delete_message_seconds") != null);
    try std.testing.expectEqualStrings("PUT", setup.ctx.reqs[26].methodStr());
    try std.testing.expectEqualStrings("/channels/C/permissions/20", setup.ctx.reqs[26].pathStr());
    try std.testing.expectEqualStrings("{\"allow\":\"1024\",\"deny\":\"0\",\"type\":0}", setup.ctx.reqs[26].bodyStr());
    try std.testing.expectEqualStrings("mod", setup.ctx.reqs[26].reasonStr());
    try std.testing.expectEqualStrings("DELETE", setup.ctx.reqs[27].methodStr());
    try std.testing.expectEqualStrings("/channels/C/permissions/20", setup.ctx.reqs[27].pathStr());
}

test "users fetch send and close dm" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(4);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var h = try client.users.fetch("123");
    try std.testing.expectEqualStrings("123", h.id);
    const again = try client.users.fetch("123");
    try std.testing.expectEqualStrings("123", again.id);
    var sent = try h.send("hi");
    defer sent.deinit();
    try std.testing.expectEqualStrings("M", sent.value.id);
    try client.rest.closeDM("C");

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 4), setup.ctx.count);
    try std.testing.expectEqualStrings("/users/123", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("/users/@me/channels", setup.ctx.reqs[1].pathStr());
}

test "messages reply forward suppress sendRich" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(4);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var replied = try client.rest.replyTo("C", "M", "hi");
    defer replied.deinit();
    var fwd = try client.rest.forwardMessage("C2", "C", "M");
    defer fwd.deinit();
    var sup = try client.rest.setSuppressEmbeds("C", "M", true);
    defer sup.deinit();
    var rich = try client.rest.createRichMessage("C", .{
        .content = "hi",
        .flags = 64,
        .stickers = &.{"S"},
    });
    defer rich.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 4), setup.ctx.count);
    try std.testing.expectEqualStrings("{\"content\":\"hi\",\"message_reference\":{\"message_id\":\"M\"}}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("{\"message_reference\":{\"message_id\":\"M\",\"channel_id\":\"C\",\"type\":1}}", setup.ctx.reqs[1].bodyStr());
    try std.testing.expectEqualStrings("{\"flags\":4}", setup.ctx.reqs[2].bodyStr());
    try std.testing.expectEqualStrings("{\"content\":\"hi\",\"flags\":64,\"sticker_ids\":[\"S\"]}", setup.ctx.reqs[3].bodyStr());
}

test "channels create edit list full" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(3);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var created = try client.rest.createChannel("G", .{ .name = "temp", .kind = schema.ChannelType.guild_voice, .user_limit = @as(u32, 5), .parent_id = "P" });
    defer created.deinit();
    var edited = try client.rest.editChannelFull("C", .{ .name = "new", .rate_limit_per_user = @as(u32, 10) }, null);
    defer edited.deinit();
    var listed = try client.rest.listGuildChannels("G");
    defer listed.deinit();
    try std.testing.expectEqual(@as(usize, 1), listed.value.len);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 3), setup.ctx.count);
    try std.testing.expectEqualStrings("{\"name\":\"temp\",\"type\":2,\"parent_id\":\"P\",\"user_limit\":5}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("{\"name\":\"new\",\"rate_limit_per_user\":10}", setup.ctx.reqs[1].bodyStr());
    try std.testing.expectEqualStrings("/guilds/G/channels", setup.ctx.reqs[2].pathStr());
}

test "invites create fetch delete" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(4);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var chan = channel_mod.Channel.init(&client, "C");
    var created = try chan.invites.create(3600, 5);
    defer created.deinit();
    try std.testing.expectEqualStrings("ABC", created.value.code);
    var listed = try chan.invites.fetch();
    defer listed.deinit();
    try std.testing.expectEqual(@as(usize, 1), listed.value.len);
    try chan.invites.delete("ABC", null);
    var glisted = try client.rest.fetchGuildInvites("G");
    defer glisted.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 4), setup.ctx.count);
    try std.testing.expectEqualStrings("/channels/C/invites", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("{\"max_age\":3600,\"max_uses\":5}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("/invites/ABC", setup.ctx.reqs[2].pathStr());
}

test "threads start join leave add archive active" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(7);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var chan = channel_mod.Channel.init(&client, "C");
    var t1 = try chan.threads.startFromMessage("M", "t1", 60);
    defer t1.deinit();
    var t2 = try chan.threads.start("t2", .public_thread, 60);
    defer t2.deinit();
    try chan.threads.join();
    try chan.threads.leave();
    try chan.threads.addMember("U");
    var archived = try chan.threads.setArchived(true);
    defer archived.deinit();
    var active = try client.rest.fetchActiveThreads("G");
    defer active.deinit();
    try std.testing.expect(!active.value.has_more);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 7), setup.ctx.count);
    try std.testing.expectEqualStrings("/channels/C/messages/M/threads", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("{\"name\":\"t1\",\"auto_archive_duration\":60}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("/channels/C/thread-members/@me", setup.ctx.reqs[2].pathStr());
}

test "roles edit positions" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(2);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var g = guild_mod.Guild.init(&client, "G");
    var edited = try g.roles.edit("R", .{ .name = "mod", .permissions = @as(u64, 8) }, "audit");
    defer edited.deinit();
    var moved = try g.roles.setPositions(&.{.{ .id = "R", .position = 3 }});
    defer moved.deinit();
    try std.testing.expectEqual(@as(usize, 1), moved.value.len);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 2), setup.ctx.count);
    try std.testing.expectEqualStrings("{\"name\":\"mod\",\"permissions\":\"8\"}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("audit", setup.ctx.reqs[0].reasonStr());
    try std.testing.expectEqualStrings("[{\"id\":\"R\",\"position\":3}]", setup.ctx.reqs[1].bodyStr());
}

test "guild edit audit onboarding templates" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(6);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var g = guild_mod.Guild.init(&client, "G");
    var edited = try g.edit(.{ .name = "srv", .verification_level = @as(u32, 1) });
    defer edited.deinit();
    var audit = try g.fetchAuditLogs(10, 1, "U");
    defer audit.deinit();
    try std.testing.expectEqual(@as(usize, 1), audit.value.entries.len);
    var onboard = try g.fetchOnboarding();
    defer onboard.deinit();
    var onboard2 = try g.editOnboarding(true, &.{ "10", "20" });
    defer onboard2.deinit();
    var templates = try g.fetchTemplates();
    defer templates.deinit();
    try std.testing.expectEqual(@as(usize, 1), templates.value.len);
    var tpl = try g.createTemplate("t", null);
    defer tpl.deinit();
    try std.testing.expectEqualStrings("T", tpl.value.code);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 6), setup.ctx.count);
    try std.testing.expectEqualStrings("{\"name\":\"srv\",\"verification_level\":1}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("/guilds/G/audit-logs?limit=10&action_type=1&user_id=U", setup.ctx.reqs[1].pathStr());
}

test "members voice mute move disconnect" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(4);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var m = member_mod.Member.init(&client, "G", "U");
    var muted = try m.voice.setMute(true, null);
    defer muted.deinit();
    var deaf = try m.voice.setDeaf(false, null);
    defer deaf.deinit();
    var moved = try m.voice.move("C", null);
    defer moved.deinit();
    var disc = try m.voice.disconnect(null);
    defer disc.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 4), setup.ctx.count);
    try std.testing.expectEqualStrings("{\"mute\":true}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("{\"channel_id\":\"C\"}", setup.ctx.reqs[2].bodyStr());
    try std.testing.expectEqualStrings("{\"channel_id\":null}", setup.ctx.reqs[3].bodyStr());
}

test "member presence reads cache" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(0);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var v = try std.json.parseFromSlice(std.json.Value, allocator, "{\"user\":{\"id\":\"9\"},\"guild_id\":\"G\",\"status\":\"online\"}", .{});
    defer v.deinit();
    try client.cache.update(.presence_update, v.value);
    try std.testing.expectEqual(@as(usize, 1), client.cache.counts().presences);

    const m = member_mod.Member.init(&client, "G", "9");
    const p = m.presence().?;
    try std.testing.expectEqualStrings("online", p.status);
    const ghost = member_mod.Member.init(&client, "G", "404");
    try std.testing.expect(ghost.presence() == null);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 0), setup.ctx.count);
}

test "app commands fetch edit delete permissions" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(7);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    const cmds = slash_mod.ApplicationCommands.init(&client.rest, "A");
    var all = try cmds.fetchAll();
    defer all.deinit();
    try std.testing.expectEqual(@as(usize, 1), all.value.len);
    var one = try cmds.fetch("C1");
    defer one.deinit();
    var edited = try cmds.edit("C1", "{\"name\":\"ping\"}");
    defer edited.deinit();
    try cmds.delete("C1");
    var perms = try cmds.fetchPermissions("G");
    defer perms.deinit();
    var single = try cmds.fetchCommandPermissions("G", "C1");
    defer single.deinit();
    var set = try cmds.setCommandPermissions("G", "C1", &.{.{ .id = "R", .kind = 0, .permission = true }});
    defer set.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 7), setup.ctx.count);
    try std.testing.expectEqualStrings("/applications/A/commands", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("DELETE", setup.ctx.reqs[3].methodStr());
    try std.testing.expectEqualStrings("/applications/A/guilds/G/commands/permissions", setup.ctx.reqs[4].pathStr());
    try std.testing.expectEqualStrings("/applications/A/guilds/G/commands/C1/permissions", setup.ctx.reqs[6].pathStr());
    try std.testing.expectEqualStrings("{\"permissions\":[{\"id\":\"R\",\"kind\":0,\"permission\":true}]}", setup.ctx.reqs[6].bodyStr());
}

test "webhooks create fetch edit execute delete" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(8);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var created = try client.rest.createWebhook("C", "hook");
    defer created.deinit();
    try std.testing.expectEqualStrings("W", created.value.id);
    var fetched = try client.rest.fetchWebhook("W");
    defer fetched.deinit();
    var edited = try client.rest.editWebhook("W", "hook2", null);
    defer edited.deinit();
    try client.rest.deleteWebhook("W", null);
    var sent = try client.rest.executeWebhook("W", "T", "{\"content\":\"hi\"}");
    defer sent.deinit();
    var got = try client.rest.getWebhookMessage("W", "T", "M");
    defer got.deinit();
    var emsg = try client.rest.editWebhookMessage("W", "T", "M", "{\"content\":\"yo\"}");
    defer emsg.deinit();
    try client.rest.deleteWebhookMessage("W", "T", "M");

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 8), setup.ctx.count);
    try std.testing.expectEqualStrings("{\"name\":\"hook\"}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("/webhooks/W/T?wait=true", setup.ctx.reqs[4].pathStr());
}

test "polls create end fetch voters" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(3);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var b = poll_mod.Builder.init(allocator);
    defer b.deinit();
    try b.setQuestion("Best?");
    try b.addAnswer(.{ .text = "A" });
    const built = try b.build();

    var created = try client.rest.createPollMessage("C", built);
    defer created.deinit();
    var ended = try client.rest.endPoll("C", "M");
    defer ended.deinit();
    var voters = try client.rest.fetchPollAnswerVoters("C", "M", 1, null, 25);
    defer voters.deinit();
    try std.testing.expectEqual(@as(usize, 1), voters.value.users.len);
    try std.testing.expectEqualStrings("9", voters.value.users[0].id);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 3), setup.ctx.count);
    try std.testing.expectEqualStrings("POST", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/channels/C/messages", setup.ctx.reqs[0].pathStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "\"poll\"") != null);
    try std.testing.expectEqualStrings("/channels/C/polls/M/expire", setup.ctx.reqs[1].pathStr());
    try std.testing.expectEqualStrings("/channels/C/polls/M/answers/1?limit=25", setup.ctx.reqs[2].pathStr());
}

test "channel facade sendPoll endPoll fetchPollAnswerVoters and sendRich with poll" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(4);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var b = poll_mod.Builder.init(allocator);
    defer b.deinit();
    try b.setQuestion("Color?");
    try b.addAnswer(.{ .text = "Red" });
    try b.addAnswer(.{ .text = "Blue" });
    const built = try b.build();

    var chan = channel_mod.Channel.init(&client, "C");
    var sent_poll = try chan.sendPoll(built);
    defer sent_poll.deinit();

    var ended = try chan.messages.endPoll("M");
    defer ended.deinit();

    var voters = try chan.messages.fetchPollAnswerVoters("M", 1, null, 10);
    defer voters.deinit();

    var rich_with_poll = try chan.sendRich(.{
        .content = "Please answer:",
        .poll = built,
    });
    defer rich_with_poll.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 4), setup.ctx.count);
    try std.testing.expectEqualStrings("POST", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/channels/C/messages", setup.ctx.reqs[0].pathStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "\"Color?\"") != null);
    try std.testing.expectEqualStrings("/channels/C/polls/M/expire", setup.ctx.reqs[1].pathStr());
    try std.testing.expectEqualStrings("/channels/C/polls/M/answers/1?limit=10", setup.ctx.reqs[2].pathStr());
    try std.testing.expectEqualStrings("POST", setup.ctx.reqs[3].methodStr());
    try std.testing.expectEqualStrings("/channels/C/messages", setup.ctx.reqs[3].pathStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[3].bodyStr(), "\"content\":\"Please answer:\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[3].bodyStr(), "\"poll\"") != null);
}

test "attachments upload sends multipart with payload" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var b = attachment_mod.Builder.init(allocator);
    defer b.deinit();
    try b.setFilename("a.txt");
    try b.setData("hi");
    const built = try b.build();

    var sent = try client.rest.createMessageWithAttachments("C", "yo", &.{built});
    defer sent.deinit();
    try std.testing.expectEqualStrings("M", sent.value.id);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("POST", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/channels/C/messages", setup.ctx.reqs[0].pathStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "name=\"payload_json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "filename=\"a.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[0].bodyStr(), "\"attachments\"") != null);
}

fn crudRest(allocator: std.mem.Allocator, setup: *CrudMockSetup) !Rest {
    var rest = Rest.init(allocator, std.testing.io, "tok");
    rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    return rest;
}

fn crudClient(allocator: std.mem.Allocator, setup: *CrudMockSetup) !Client {
    var client = Client.init(allocator, std.testing.io, .{});
    client.rest.base_url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}", .{setup.port});
    return client;
}

test "channel facade sends messages and edits overwrites" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(4);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var chan = channel_mod.Channel.init(&client, "C");
    var sent = try chan.send("hi");
    defer sent.deinit();
    try std.testing.expectEqualStrings("M", sent.value.id);
    try chan.messages.react("M", "🔥");
    try chan.permissionOverwrites.editTarget("20", .role, 1024, 0, null);
    try chan.bulkDelete(&.{"1"});

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 4), setup.ctx.count);
    try std.testing.expectEqualStrings("POST", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/channels/C/messages", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("{\"content\":\"hi\"}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("/channels/C/permissions/20", setup.ctx.reqs[2].pathStr());
}

test "guild facade delegates members roles bans" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(3);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var g = guild_mod.Guild.init(&client, "G");
    var m = try g.members.fetch("U");
    defer m.deinit();
    try std.testing.expectEqualStrings("U", m.value.user.?.id);
    try g.members.kick("U", null);
    var r = try g.roles.create("mod", null);
    defer r.deinit();
    try std.testing.expectEqualStrings("R", r.value.id);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 3), setup.ctx.count);
    try std.testing.expectEqualStrings("/guilds/G/members/U", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("DELETE", setup.ctx.reqs[1].methodStr());
}

test "member facade roles timeout kick" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(3);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var m = member_mod.Member.init(&client, "G", "U");
    try m.roles.add("R", null);
    var timed = try m.timeout(null, null);
    defer timed.deinit();
    try m.kick(null);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 3), setup.ctx.count);
    try std.testing.expectEqualStrings("PUT", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/guilds/G/members/U/roles/R", setup.ctx.reqs[0].pathStr());
}

test "member permissionsIn resolves channel overwrites" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var m = member_mod.Member.init(&client, "G", "U");
    const roles = [_]schema.Role{
        .{ .id = "10", .name = "@everyone", .permissions = "1024" },
    };
    const chan = schema.Channel{
        .id = "C",
        .permission_overwrites = &.{.{ .id = "10", .@"type" = 0, .allow = "0", .deny = "1024" }},
    };
    const bits = try m.permissionsIn(chan, &roles, "99");
    try std.testing.expectEqual(@as(u64, 0), bits);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
}

test "guilds fetch hits cache before network" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    const cached = try schema.parse(schema.Guild, allocator, "{\"id\":\"10\",\"name\":\"cached\"}");
    var owned_guild: ?std.json.Parsed(schema.Guild) = cached;
    errdefer if (owned_guild) |*p| p.deinit();
    try client.cache.guilds.putParsed(10, owned_guild.?);
    owned_guild = null;

    const hit = try client.guilds.fetch("10");
    try std.testing.expectEqualStrings("10", hit.id);
    try std.testing.expectEqual(@as(usize, 0), setup.ctx.count);

    const miss = try client.guilds.fetch("99");
    try std.testing.expectEqualStrings("99", miss.id);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("/guilds/99", setup.ctx.reqs[0].pathStr());
    const again = try client.guilds.fetch("99");
    try std.testing.expectEqualStrings("99", again.id);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);

    try std.testing.expect(setup.ctx.err == null);
}

test "guild facade edit sends name and description" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var g = guild_mod.Guild.init(&client, "G");
    var edited = try g.edit(.{ .name = "new", .reason = "audit" });
    defer edited.deinit();
    try std.testing.expectEqualStrings("G", edited.value.id);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("PATCH", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/guilds/G", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("{\"name\":\"new\"}", setup.ctx.reqs[0].bodyStr());
    try std.testing.expectEqualStrings("audit", setup.ctx.reqs[0].reasonStr());
}

test "guilds fetchAll lists guilds without id" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var all = try client.guilds.fetchAll(10);
    defer all.deinit();
    try std.testing.expectEqual(@as(usize, 1), all.value.len);
    try std.testing.expectEqualStrings("G", all.value[0].id);

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("GET", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/users/@me/guilds?limit=10", setup.ctx.reqs[0].pathStr());
}

test "guild channels fetch is guild scoped with findByName" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    const foreign = try schema.parse(schema.Channel, allocator, "{\"id\":\"30\",\"type\":0,\"guild_id\":\"OTHER\",\"name\":\"general\"}");
    var owned_foreign: ?std.json.Parsed(schema.Channel) = foreign;
    errdefer if (owned_foreign) |*p| p.deinit();
    try client.cache.channels.putParsed(30, owned_foreign.?);
    owned_foreign = null;
    const local = try schema.parse(schema.Channel, allocator, "{\"id\":\"20\",\"type\":0,\"guild_id\":\"G\",\"name\":\"general\"}");
    var owned_local: ?std.json.Parsed(schema.Channel) = local;
    errdefer if (owned_local) |*p| p.deinit();
    try client.cache.channels.putParsed(20, owned_local.?);
    owned_local = null;

    var g = guild_mod.Guild.init(&client, "G");
    const found = g.channels.findByName("general").?;
    try std.testing.expectEqualStrings("20", found.id);
    try std.testing.expect(g.channels.findByName("missing") == null);

    const hit = try g.channels.fetch("20");
    try std.testing.expectEqualStrings("20", hit.id);
    const miss = try g.channels.fetch("21");
    try std.testing.expectEqualStrings("21", miss.id);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);

    const any = try client.channels.fetch("30");
    try std.testing.expectEqualStrings("30", any.id);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);

    setup.join();
    try std.testing.expect(setup.ctx.err == null);
}

test "Client.init supports discord.js GatewayIntentBits .intents exclusively" {
    const discord = @import("discord-zig");
    const GatewayIntentBits = discord.GatewayIntentBits;
    const expected = discord.intents.guilds | discord.intents.guild_messages | discord.intents.message_content;

    var client = Client.init(std.testing.allocator, std.testing.io, .{
        .intents = .{
            GatewayIntentBits.Guilds,
            GatewayIntentBits.GuildMessages,
            GatewayIntentBits.MessageContent,
        },
    });
    defer client.deinit();
    try std.testing.expectEqual(expected, client.session.config.intents);
    try std.testing.expectEqual(expected, client.session.intentsOrDefault());

    // Default (no intents passed)
    var c_def = Client.init(std.testing.allocator, std.testing.io, .{});
    defer c_def.deinit();
    try std.testing.expectEqual(@as(u32, 0), c_def.session.config.intents);
    try std.testing.expectEqual(discord.intents.defaults(), c_def.session.intentsOrDefault());
}

test "parsePermissionValue handles flags, tuples, arrays, strings and enums" {
    const perm = @import("discord-zig").permission;
    try std.testing.expectEqual(@as(u64, 1024), Rest.parsePermissionValue(perm.view_channel));
    try std.testing.expectEqual(@as(u64, 1024), Rest.parsePermissionValue(@as(u64, 1024)));
    try std.testing.expectEqual(@as(u64, 1024), Rest.parsePermissionValue("1024"));
    try std.testing.expectEqual(@as(u64, 1024), Rest.parsePermissionValue(perm.Bits.view_channel));
    try std.testing.expectEqual(@as(u64, 1024), Rest.parsePermissionValue(.{perm.view_channel}));
    try std.testing.expectEqual(@as(u64, 1024 | 2048), Rest.parsePermissionValue(.{ perm.view_channel, perm.send_messages }));
    try std.testing.expectEqual(@as(u64, 1024), Rest.parsePermissionValue(&.{perm.view_channel}));
    try std.testing.expectEqual(@as(u64, 1024), Rest.parsePermissionValue([_]u64{perm.view_channel}));
    try std.testing.expectEqual(@as(u64, 0), Rest.parsePermissionValue(@as(?u64, null)));
}

test "permissionOverwrites.set batch overwrite" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var chan = channel_mod.Channel.init(&client, "C");
    var res = try chan.permissionOverwrites.set(&.{
        .{
            .id = "1098316516774129684",
            .deny = @import("discord-zig").permission.view_channel,
        },
        .{
            .id = "1544569004075782207",
            .kind = schema.OverwriteType.member,
            .allow = .{ @import("discord-zig").permission.view_channel },
        },
    }, "privacy update");
    defer res.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("PATCH", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/channels/C", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("privacy update", setup.ctx.reqs[0].reasonStr());
    const body = setup.ctx.reqs[0].bodyStr();
    try std.testing.expect(std.mem.indexOf(u8, body, "\"permission_overwrites\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"id\":\"1098316516774129684\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"deny\":\"1024\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"id\":\"1544569004075782207\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"allow\":\"1024\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":1") != null);
}

test "permissionOverwrites editOptions and delete" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(2);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var chan = channel_mod.Channel.init(&client, "C");
    try chan.permissionOverwrites.editOptions("1098316516774129684", .{
        .deny = @import("discord-zig").permission.view_channel,
    }, "deny everyone");

    try chan.permissionOverwrites.delete("1544569004075782207", "remove user");

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 2), setup.ctx.count);
    try std.testing.expectEqualStrings("PUT", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/channels/C/permissions/1098316516774129684", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("deny everyone", setup.ctx.reqs[0].reasonStr());
    try std.testing.expectEqualStrings("{\"allow\":\"0\",\"deny\":\"1024\",\"type\":0}", setup.ctx.reqs[0].bodyStr());

    try std.testing.expectEqualStrings("DELETE", setup.ctx.reqs[1].methodStr());
    try std.testing.expectEqualStrings("/channels/C/permissions/1544569004075782207", setup.ctx.reqs[1].pathStr());
    try std.testing.expectEqualStrings("remove user", setup.ctx.reqs[1].reasonStr());
}

test "channel edit accepts permission_overwrites" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var chan = channel_mod.Channel.init(&client, "C");
    var res = try chan.edit(.{
        .name = "private-room",
        .permission_overwrites = &.{
            .{ .id = "1", .deny = @import("discord-zig").permission.view_channel },
        },
    }, null);
    defer res.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("PATCH", setup.ctx.reqs[0].methodStr());
    const body = setup.ctx.reqs[0].bodyStr();
    try std.testing.expect(std.mem.indexOf(u8, body, "\"name\":\"private-room\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"permission_overwrites\":[") != null);
}

test "PermissionsBitField.Flags with permissionOverwrites.set" {
    const discord = @import("discord-zig");
    const PermissionsBitField = discord.PermissionsBitField;
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var chan = channel_mod.Channel.init(&client, "C");
    var res = try chan.permissionOverwrites.set(&.{
        .{
            .id = "1098316516774129684",
            .allow = .{},
            .deny = .{ PermissionsBitField.Flags.ViewChannel },
        },
        .{
            .id = "1544569004075782207",
            .kind = schema.OverwriteType.member,
            .allow = .{ PermissionsBitField.Flags.ViewChannel },
        },
    }, null);
    defer res.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    const body = setup.ctx.reqs[0].bodyStr();
    try std.testing.expect(std.mem.indexOf(u8, body, "\"allow\":\"0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"deny\":\"1024\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"allow\":\"1024\"") != null);
}

test "permissionOverwrites.edit with &[_]PermissionOverwrite exact user syntax" {
    const discord = @import("discord-zig");
    const PermissionOverwrite = discord.PermissionOverwrite;
    const PermissionsBitField = discord.PermissionsBitField;
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var channel = channel_mod.Channel.init(&client, "C");
    const guild = struct { id: []const u8 = "1098316516774129684" }{};
    const user = struct { id: []const u8 = "1544569004075782207" }{};

    try channel.permissionOverwrites.edit(&[_]PermissionOverwrite{
        .{
            .id = guild.id,
            .allow = &[_]u64{},
            .deny = &[_]u64{
                PermissionsBitField.Flags.ViewChannel,
            },
        },
        .{
            .id = user.id,
            .allow = &[_]u64{
                PermissionsBitField.Flags.ViewChannel,
            },
            .deny = &[_]u64{},
        },
    });

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("PATCH", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/channels/C", setup.ctx.reqs[0].pathStr());
    const body = setup.ctx.reqs[0].bodyStr();
    try std.testing.expect(std.mem.indexOf(u8, body, "\"permission_overwrites\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"id\":\"1098316516774129684\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"deny\":\"1024\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"allow\":\"0\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"id\":\"1544569004075782207\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"allow\":\"1024\"") != null);
}

test "guild channels create with permissionOverwrites and type" {
    const discord = @import("discord-zig");
    const ChannelType = discord.ChannelType;
    const PermissionOverwrite = discord.PermissionOverwrite;
    const PermissionsBitField = discord.PermissionsBitField;
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var g = guild_mod.Guild.init(&client, "1098316516774129684");
    var created = try g.channels.create(.{
        .name = "tickets",
        .@"type" = ChannelType.guild_text,
        .permissionOverwrites = &[_]PermissionOverwrite{
            .{
                .id = "1098316516774129684",
                .allow = &[_]u64{},
                .deny = &[_]u64{ PermissionsBitField.Flags.ViewChannel },
            },
            .{
                .id = "1544569004075782207",
                .allow = &[_]u64{ PermissionsBitField.Flags.ViewChannel },
                .deny = &[_]u64{},
            },
        },
    });
    defer created.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqualStrings("POST", setup.ctx.reqs[0].methodStr());
    try std.testing.expectEqualStrings("/guilds/1098316516774129684/channels", setup.ctx.reqs[0].pathStr());
    const body = setup.ctx.reqs[0].bodyStr();
    try std.testing.expect(std.mem.indexOf(u8, body, "\"name\":\"tickets\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"permission_overwrites\":[") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"id\":\"1098316516774129684\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"deny\":\"1024\"") != null);
}

test "guild channels create ChannelType.GuildVoice identical to discord.js" {
    const discord = @import("discord-zig");
    const ChannelType = discord.ChannelType;
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var g = guild_mod.Guild.init(&client, "1098316516774129684");
    var created = try g.channels.create(.{
        .name = "General Voice",
        .@"type" = ChannelType.GuildVoice,
    });
    defer created.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    const body = setup.ctx.reqs[0].bodyStr();
    try std.testing.expect(std.mem.indexOf(u8, body, "\"name\":\"General Voice\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "\"type\":2") != null);
}

test "ChannelType values match discord.js 14.22.1 specification" {
    const discord = @import("discord-zig");
    const ChannelType = discord.ChannelType;

    try std.testing.expectEqual(@as(u8, 0), @intFromEnum(ChannelType.GuildText));
    try std.testing.expectEqual(@as(u8, 1), @intFromEnum(ChannelType.DM));
    try std.testing.expectEqual(@as(u8, 2), @intFromEnum(ChannelType.GuildVoice));
    try std.testing.expectEqual(@as(u8, 3), @intFromEnum(ChannelType.GroupDM));
    try std.testing.expectEqual(@as(u8, 4), @intFromEnum(ChannelType.GuildCategory));
    try std.testing.expectEqual(@as(u8, 5), @intFromEnum(ChannelType.GuildAnnouncement));
    try std.testing.expectEqual(@as(u8, 10), @intFromEnum(ChannelType.AnnouncementThread));
    try std.testing.expectEqual(@as(u8, 11), @intFromEnum(ChannelType.PublicThread));
    try std.testing.expectEqual(@as(u8, 12), @intFromEnum(ChannelType.PrivateThread));
    try std.testing.expectEqual(@as(u8, 13), @intFromEnum(ChannelType.GuildStageVoice));
    try std.testing.expectEqual(@as(u8, 14), @intFromEnum(ChannelType.GuildDirectory));
    try std.testing.expectEqual(@as(u8, 15), @intFromEnum(ChannelType.GuildForum));
    try std.testing.expectEqual(@as(u8, 16), @intFromEnum(ChannelType.GuildMedia));

    // Deprecated aliases in discord.js
    try std.testing.expectEqual(ChannelType.GuildAnnouncement, ChannelType.GuildNews);
    try std.testing.expectEqual(ChannelType.AnnouncementThread, ChannelType.GuildNewsThread);
    try std.testing.expectEqual(ChannelType.PublicThread, ChannelType.GuildPublicThread);
    try std.testing.expectEqual(ChannelType.PrivateThread, ChannelType.GuildPrivateThread);
}

test "exact user syntax cacheWithLimits" {
    const discord = @import("discord-zig");
    const cacheWithLimits = discord.cacheWithLimits;
    const allocator = std.testing.allocator;

    var client = discord.Client.init(allocator, std.testing.io, .{
        .cache = cacheWithLimits(.{
            .GuildMemberManager = 12000,
            .MessageManager = 50,
        }),
    });
    defer client.deinit();

    try std.testing.expectEqual(@as(?usize, 12000), client.cache.limits.guild_members);
    try std.testing.expectEqual(@as(?usize, 50), client.cache.limits.messages);
}

test "cacheWithLimits with all supported Discord.js managers" {
    const discord = @import("discord-zig");
    const cacheWithLimits = discord.cacheWithLimits;
    const allocator = std.testing.allocator;

    var client = discord.Client.init(allocator, std.testing.io, .{
        .cache = cacheWithLimits(.{
            .GuildMemberManager = 5000,
            .MessageManager = 100,
            .GuildManager = 50,
            .ChannelManager = 200,
            .UserManager = 1000,
            .RoleManager = 300,
            .ThreadManager = 50,
            .GuildEmojiManager = 150,
            .PresenceManager = 500,
        }),
    });
    defer client.deinit();

    try std.testing.expectEqual(@as(?usize, 5000), client.cache.limits.guild_members);
    try std.testing.expectEqual(@as(?usize, 100), client.cache.limits.messages);
    try std.testing.expectEqual(@as(?usize, 50), client.cache.limits.guilds);
    try std.testing.expectEqual(@as(?usize, 200), client.cache.limits.channels);
    try std.testing.expectEqual(@as(?usize, 1000), client.cache.limits.users);
    try std.testing.expectEqual(@as(?usize, 300), client.cache.limits.roles);
    try std.testing.expectEqual(@as(?usize, 50), client.cache.limits.threads);
    try std.testing.expectEqual(@as(?usize, 150), client.cache.limits.emojis);
    try std.testing.expectEqual(@as(?usize, 500), client.cache.limits.presences);
}

test "cacheWithLimits with all newly extended v15 managers" {
    const discord = @import("discord-zig");
    const cacheWithLimits = discord.cacheWithLimits;
    const allocator = std.testing.allocator;

    var client = discord.Client.init(allocator, std.testing.io, .{
        .cache = cacheWithLimits(.{
            .GuildScheduledEventManager = 25,
            .StageInstanceManager = 10,
            .AutoModerationRuleManager = 15,
            .GuildBanManager = 100,
            .GuildInviteManager = 80,
            .GuildStickerManager = 60,
            .VoiceStateManager = 500,
            .ApplicationCommandManager = 200,
            .ReactionManager = 1000,
        }),
    });
    defer client.deinit();

    try std.testing.expectEqual(@as(?usize, 25), client.cache.limits.scheduled_events);
    try std.testing.expectEqual(@as(?usize, 10), client.cache.limits.stage_instances);
    try std.testing.expectEqual(@as(?usize, 15), client.cache.limits.auto_moderation_rules);
    try std.testing.expectEqual(@as(?usize, 100), client.cache.limits.bans);
    try std.testing.expectEqual(@as(?usize, 80), client.cache.limits.invites);
    try std.testing.expectEqual(@as(?usize, 60), client.cache.limits.stickers);
    try std.testing.expectEqual(@as(?usize, 500), client.cache.limits.voice_states);
    try std.testing.expectEqual(@as(?usize, 200), client.cache.limits.application_commands);
    try std.testing.expectEqual(@as(?usize, 1000), client.cache.limits.reactions);
}

test "cache store collection methods has, size, first, last, at, find" {
    const discord = @import("discord-zig");
    const allocator = std.testing.allocator;

    var store = discord.cache.Store(u64, discord.schema.Channel).init(allocator, 10);
    defer store.deinit();

    try std.testing.expectEqual(@as(usize, 0), store.size());
    try std.testing.expect(!store.has(100));
    try std.testing.expect(store.first() == null);
    try std.testing.expect(store.last() == null);

    const c1 = try std.json.parseFromSlice(discord.schema.Channel, allocator, "{\"id\":\"100\",\"name\":\"general\"}", .{});
    try store.putParsed(100, c1);
    const c2 = try std.json.parseFromSlice(discord.schema.Channel, allocator, "{\"id\":\"200\",\"name\":\"dev\"}", .{});
    try store.putParsed(200, c2);

    try std.testing.expectEqual(@as(usize, 2), store.size());
    try std.testing.expect(store.has(100));
    try std.testing.expect(store.has(200));
    try std.testing.expect(!store.has(300));

    try std.testing.expectEqualStrings("100", store.first().?.id);
    try std.testing.expectEqualStrings("200", store.last().?.id);
    try std.testing.expectEqualStrings("100", store.at(0).?.id);
    try std.testing.expectEqualStrings("200", store.at(1).?.id);
    try std.testing.expect(store.at(2) == null);

    const Pred = struct {
        fn isDev(_: void, ch: *const discord.schema.Channel) bool {
            if (ch.name) |n| return std.mem.eql(u8, n, "dev");
            return false;
        }
    };
    const found = store.find({}, Pred.isDev);
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("200", found.?.id);
}

test "context menu command builder and interaction helpers" {
    const discord = @import("discord-zig");
    const allocator = std.testing.allocator;

    var builder = discord.ContextMenuCommandBuilder.init(allocator);
    defer builder.deinit();

    try builder.setName("Report User");
    builder.setType(.user);
    try builder.setDefaultMemberPermissions("8");
    builder.setNsfw(false);

    const cmd = try builder.build();
    try std.testing.expectEqualStrings("Report User", cmd.name);
    try std.testing.expectEqual(@as(u32, 2), cmd.type);
    try std.testing.expectEqualStrings("8", cmd.default_member_permissions.?);

    const int_json =
        \\{
        \\  "id": "1",
        \\  "token": "tok",
        \\  "application_id": "app",
        \\  "type": 3,
        \\  "data": {
        \\    "component_type": 3,
        \\    "custom_id": "select_menu_1",
        \\    "values": ["val1", "val2"]
        \\  }
        \\}
    ;
    var parsed = try std.json.parseFromSlice(discord.schema.Interaction, allocator, int_json, .{});
    defer parsed.deinit();

    try std.testing.expect(!discord.slash.Interaction.isCommand(parsed.value));
    try std.testing.expect(!discord.slash.Interaction.isButton(parsed.value));
    try std.testing.expect(discord.slash.Interaction.isStringSelectMenu(parsed.value));
    try std.testing.expect(discord.slash.Interaction.isAnySelectMenu(parsed.value));
    try std.testing.expectEqualStrings("select_menu_1", discord.slash.Interaction.customId(parsed.value).?);
    try std.testing.expectEqual(@as(usize, 2), discord.slash.Interaction.values(parsed.value).len);
}

test "component builder exports and styles" {
    const discord = @import("discord-zig");
    const allocator = std.testing.allocator;

    try std.testing.expectEqual(discord.schema.ButtonStyle.primary, discord.ButtonStyle.Primary);
    try std.testing.expectEqual(discord.schema.ButtonStyle.danger, discord.ButtonStyle.Danger);
    try std.testing.expectEqual(discord.schema.TextInputStyle.paragraph, discord.TextInputStyle.Paragraph);

    var sel = discord.StringSelectMenuBuilder.init(allocator);
    defer sel.deinit();
    try sel.setCustomId("custom1");
    try sel.addOption(.{ .label = "Opt 1", .value = "val1" });
    const built_sel = try sel.build();
    try std.testing.expectEqualStrings("custom1", built_sel.custom_id.?);

    var ch_sel = discord.ChannelSelectMenuBuilder.init(allocator);
    defer ch_sel.deinit();
    try ch_sel.setCustomId("ch_custom");
    try ch_sel.setChannelTypes(&[_]discord.ChannelType{ .GuildVoice, .GuildText });
    const built_ch = try ch_sel.build();
    try std.testing.expectEqualStrings("ch_custom", built_ch.custom_id.?);
    try std.testing.expectEqual(@as(usize, 2), built_ch.channel_types.len);
}

test "client joinVoiceChannel and webhook client" {
    const discord = @import("discord-zig");
    const allocator = std.testing.allocator;

    var client = discord.Client.init(allocator, std.testing.io, .{});
    defer client.deinit();

    const conn = try client.joinVoiceChannel(.{
        .guild_id = "111",
        .channel_id = "222",
        .self_mute = true,
        .self_deaf = false,
    });
    try std.testing.expectEqualStrings("111", conn.guild_id);
    try std.testing.expectEqualStrings("222", conn.channel_id);
    try std.testing.expect(conn.self_mute);
    try std.testing.expect(!conn.self_deaf);

    var webhook = discord.WebhookClient.init(allocator, std.testing.io, "w1", "tok1");
    defer webhook.deinit();
    try std.testing.expectEqualStrings("w1", webhook.id);
    try std.testing.expectEqualStrings("tok1", webhook.token);
}

test "guild and channel extended facades" {
    const discord = @import("discord-zig");
    const allocator = std.testing.allocator;

    var client = discord.Client.init(allocator, std.testing.io, .{});
    defer client.deinit();

    const g = discord.guild.Guild.init(&client, "G1");
    const c = discord.channel.Channel.init(&client, "C1");

    _ = g.emojis;
    _ = g.stickers;
    _ = g.scheduledEvents;
    _ = g.autoModeration;
    _ = g.stageInstances;
    _ = g.commands;
    _ = g.invites;
    _ = g.webhooks;
    _ = g.voice;
    _ = c.webhooks;
    _ = c.threads.members;
    _ = client.application;
}

test "channel threads members facade operations" {
    const discord = @import("discord-zig");
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(4);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var c = discord.channel.Channel.init(&client, "C_THREAD");

    // 1. fetch all members
    var list = try c.threads.members.fetchAll(50);
    defer list.deinit();
    try std.testing.expectEqual(@as(usize, 1), list.value.len);
    try std.testing.expectEqualStrings("th1", list.value[0].id.?);

    // 2. fetch single member
    var member = try c.threads.members.fetch("u1");
    defer member.deinit();
    try std.testing.expectEqualStrings("u1", member.value.user_id.?);

    // 3. add member
    try c.threads.members.add("u2");

    // 4. remove member
    try c.threads.members.remove("u2");

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 4), setup.ctx.count);
}

test "guild scheduled events fetchSubscribers facade" {
    const discord = @import("discord-zig");
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(1);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var g = discord.guild.Guild.init(&client, "G_EVENT");
    var subs = try g.scheduledEvents.fetchSubscribers("ev1", 100);
    defer subs.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 1), setup.ctx.count);
    try std.testing.expectEqual(@as(usize, 1), subs.value.len);
    try std.testing.expectEqualStrings("ev1", subs.value[0].guild_scheduled_event_id);
    try std.testing.expectEqualStrings("u1", subs.value[0].user.id);
    try std.testing.expectEqualStrings("bob", subs.value[0].user.username);
}

test "guild vanity welcome widget prune bulkban search fetchme" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(9);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var g = guild_mod.Guild.init(&client, "G");
    var vanity = try g.fetchVanityUrl();
    defer vanity.deinit();
    try std.testing.expectEqualStrings("vip", vanity.value.code.?);
    var welcome = try g.fetchWelcomeScreen();
    defer welcome.deinit();
    var widget = try g.fetchWidget();
    defer widget.deinit();
    try std.testing.expectEqual(@as(u64, 0), widget.value.presence_count);
    var pruned = try g.prune(7, &.{}, null);
    defer pruned.deinit();
    try std.testing.expectEqual(@as(?u64, 3), pruned.value.pruned);
    var banned = try g.bulkBan(&.{ "1", "2" }, 0, null);
    defer banned.deinit();
    try std.testing.expectEqual(@as(usize, 2), banned.value.banned_users.len);
    var found = try g.searchMembers("ann", 5);
    defer found.deinit();
    try std.testing.expectEqual(@as(usize, 1), found.value.len);
    var me = try g.fetchMe();
    defer me.deinit();
    try std.testing.expectEqualStrings("U", me.value.user.?.id);
    var wedit = try g.editWelcomeScreen(true, "hi");
    defer wedit.deinit();
    var wset = try g.editWidgetSettings(true, "C", null);
    defer wset.deinit();

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 9), setup.ctx.count);
    try std.testing.expectEqualStrings("/guilds/G/vanity-url", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("/guilds/G/prune", setup.ctx.reqs[3].pathStr());
    try std.testing.expectEqualStrings("/guilds/G/bulk-ban", setup.ctx.reqs[4].pathStr());
    try std.testing.expect(std.mem.indexOf(u8, setup.ctx.reqs[5].pathStr(), "/members/search?query=ann") != null);
}

test "generate invite url" {
    const url = try Rest.generateInvite(std.testing.allocator, "123", 8, &.{ "bot", "applications.commands" });
    defer std.testing.allocator.free(url);
    try std.testing.expectEqualStrings("https://discord.com/oauth2/authorize?client_id=123&permissions=8&scope=bot%20applications.commands", url);
}

test "threads archived and members" {
    const allocator = std.testing.allocator;
    const setup = try withCrudMock(4);
    defer destroyCrudMock(setup);
    var client = try crudClient(allocator, setup);
    defer allocator.free(client.rest.base_url);
    defer client.deinit();

    var chan = channel_mod.Channel.init(&client, "C");
    var arch_pub = try chan.threads.fetchArchivedPublic(null, 10);
    defer arch_pub.deinit();
    var priv = try chan.threads.fetchArchivedPrivate("100", 10);
    defer priv.deinit();
    var members = try chan.threads.fetchMembers(10, false);
    defer members.deinit();
    try chan.threads.removeMember("U");

    try std.testing.expect(setup.ctx.err == null);
    try std.testing.expectEqual(@as(usize, 4), setup.ctx.count);
    try std.testing.expectEqualStrings("/channels/C/threads/archived/public?limit=10", setup.ctx.reqs[0].pathStr());
    try std.testing.expectEqualStrings("/channels/C/threads/archived/private?before=100&limit=10", setup.ctx.reqs[1].pathStr());
}

