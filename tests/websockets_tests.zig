const std = @import("std");
const websockets = @import("discord-zig").websockets;

test "constants target discord v10 json" {
    try std.testing.expectEqualStrings("gateway.discord.gg", websockets.host);
    try std.testing.expectEqual(@as(u16, 443), websockets.port);
    try std.testing.expectEqualStrings("/?v=10&encoding=json", websockets.path);
}

test "accept key matches rfc6455 vector" {
    var out: [28]u8 = undefined;
    websockets.acceptKey("dGhlIHNhbXBsZSBub25jZQ==", &out);
    try std.testing.expectEqualStrings("s3pPLMBiTxaQ9kYGzzhZRbK+xOo=", &out);
}

test "header encoding boundaries" {
    var buf: [10]u8 = undefined;
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 0 }, websockets.encodeHeader(0x1, 0, &buf));
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 125 }, websockets.encodeHeader(0x1, 125, &buf));
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 126, 0, 126 }, websockets.encodeHeader(0x1, 126, &buf));
    try std.testing.expectEqualSlices(u8, &.{ 0x81, 126, 0xFF, 0xFF }, websockets.encodeHeader(0x1, 65535, &buf));
    try std.testing.expectEqualSlices(u8, &.{ 0x82, 127, 0, 0, 0, 0, 0, 1, 0, 0 }, websockets.encodeHeader(0x2, 65536, &buf));
}

test "mask roundtrip" {
    var data = [_]u8{ 1, 2, 3, 4, 5, 250, 0, 255 };
    const original = data;
    websockets.applyMask(.{ 10, 20, 30, 40 }, &data);
    try std.testing.expect(!std.mem.eql(u8, &original, &data));
    websockets.applyMask(.{ 10, 20, 30, 40 }, &data);
    try std.testing.expectEqualSlices(u8, &original, &data);
}

test "handshake validation accepts good response" {
    const key = "dGhlIHNhbXBsZSBub25jZQ==";
    const response =
        "HTTP/1.1 101 Switching Protocols\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n" ++
        "\r\n";
    try websockets.validateHandshakeResponse(key, response);
}

test "handshake validation rejects wrong accept" {
    const response =
        "HTTP/1.1 101 Switching Protocols\r\n" ++
        "Upgrade: websocket\r\n" ++
        "Connection: Upgrade\r\n" ++
        "Sec-WebSocket-Accept:AAAAAAAAAAAAAAAAAAAAAAAAAAA=\r\n" ++
        "\r\n";
    try std.testing.expectError(error.InvalidAcceptHeader, websockets.validateHandshakeResponse("dGhlIHNhbXBsZSBub25jZQ==", response));
}

test "handshake validation rejects non-101" {
    try std.testing.expectError(error.InvalidHandshakeResponse, websockets.validateHandshakeResponse("k", "HTTP/1.1 200 OK\r\n\r\n"));
}

test "message data filters control frames" {
    const text = websockets.Message{ .type = .text, .data = @constCast("hi") };
    try std.testing.expectEqualStrings("hi", websockets.messageData(text).?);
    const ping = websockets.Message{ .type = .ping, .data = &.{} };
    try std.testing.expect(websockets.messageData(ping) == null);
}

const MockCtx = struct {
    server: *std.Io.net.Server,
    err: ?anyerror = error.ServerDidNotFinish,
};

fn srvReadFull(io: std.Io, stream: *std.Io.net.Stream, buf: []u8) !void {
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

fn srvWriteAll(io: std.Io, stream: *std.Io.net.Stream, data: []const u8) !void {
    var wbuf: [4096]u8 = undefined;
    var w = stream.writer(io, &wbuf);
    try w.interface.writeAll(data);
    try w.interface.flush();
}

fn srvExtractKey(req: []const u8) ![]const u8 {
    var lines = std.mem.splitSequence(u8, req, "\r\n");
    _ = lines.first();
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        if (std.ascii.eqlIgnoreCase(name, "sec-websocket-key")) {
            return std.mem.trim(u8, line[colon + 1 ..], " \t");
        }
    }
    return error.MissingKey;
}

const SrvFrame = struct {
    opcode: u8,
    len: usize,
};

fn srvReadFrame(io: std.Io, stream: *std.Io.net.Stream, payload: []u8) !SrvFrame {
    var hb: [2]u8 = undefined;
    try srvReadFull(io, stream, &hb);
    const opcode = hb[0] & 0x0F;
    const masked = hb[1] & 0x80 != 0;
    var len: usize = hb[1] & 0x7F;
    if (len == 126) {
        var eb: [2]u8 = undefined;
        try srvReadFull(io, stream, &eb);
        len = std.mem.readInt(u16, &eb, .big);
    } else if (len == 127) {
        return error.FrameTooLarge;
    }
    if (!masked) return error.ExpectedMask;
    if (len > payload.len) return error.FrameTooLarge;
    var mask: [4]u8 = undefined;
    try srvReadFull(io, stream, &mask);
    try srvReadFull(io, stream, payload[0..len]);
    websockets.applyMask(mask, payload[0..len]);
    return .{ .opcode = opcode, .len = len };
}

fn mockServerMain(ctx: *MockCtx) void {
    mockServerRun(ctx) catch |err| {
        ctx.err = err;
        return;
    };
    ctx.err = null;
}

fn mockServerRun(ctx: *MockCtx) !void {
    const io = std.testing.io;
    var stream = try ctx.server.accept(io);
    defer stream.close(io);

    var req_buf: [16384]u8 = undefined;
    var req_len: usize = 0;
    while (true) {
        if (req_len >= req_buf.len) return error.RequestTooLarge;
        var byte: [1]u8 = undefined;
        try srvReadFull(io, &stream, &byte);
        req_buf[req_len] = byte[0];
        req_len += 1;
        if (req_len >= 4 and std.mem.eql(u8, req_buf[req_len - 4 .. req_len], "\r\n\r\n")) break;
    }
    const key = try srvExtractKey(req_buf[0..req_len]);
    var accept: [28]u8 = undefined;
    websockets.acceptKey(key, &accept);
    var resp_buf: [256]u8 = undefined;
    const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: {s}\r\n\r\n", .{accept});
    try srvWriteAll(io, &stream, resp);

    try srvWriteAll(io, &stream, "\x89\x02hb");
    try srvWriteAll(io, &stream, "\x01\x06hello ");
    try srvWriteAll(io, &stream, "\x80\x05world");

    var saw_pong = false;
    var saw_text = false;
    var payload: [4096]u8 = undefined;
    while (true) {
        const fr = try srvReadFrame(io, &stream, &payload);
        switch (fr.opcode) {
            0xA => {
                if (!std.mem.eql(u8, payload[0..fr.len], "hb")) return error.ScriptMismatch;
                saw_pong = true;
            },
            0x1 => {
                if (!std.mem.eql(u8, payload[0..fr.len], "{\"op\":1}")) return error.ScriptMismatch;
                saw_text = true;
            },
            0x8 => {
                if (!saw_pong or !saw_text) return error.ScriptMismatch;
                return;
            },
            else => return error.UnexpectedOpcode,
        }
    }
}

test "cert cache loads once and frees cleanly" {
    var cache = websockets.CertCache.init(std.testing.allocator);
    try std.testing.expect(!cache.loaded);
    cache.deinit();
    var cache2 = websockets.CertCache.init(std.testing.allocator);
    defer cache2.deinit();
    try cache2.ensure(std.testing.io);
    try std.testing.expect(cache2.loaded);
    try cache2.ensure(std.testing.io);
    try std.testing.expect(cache2.loaded);
}

test "full duplex against mock server" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    var srv: std.Io.net.Server = undefined;
    var chosen: u16 = 0;
    for ([_]u16{ 18441, 18442, 18443 }) |p| {
        var addr = std.Io.net.IpAddress{ .ip4 = .loopback(p) };
        if (std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true })) |s| {
            srv = s;
            chosen = p;
            break;
        } else |_| continue;
    }
    if (chosen == 0) return error.CannotBindTestServer;
    defer srv.deinit(io);

    var ctx = MockCtx{ .server = &srv };
    const thread = try std.Thread.spawn(.{}, mockServerMain, .{&ctx});
    errdefer {
        _ = std.os.linux.shutdown(srv.socket.handle, std.os.linux.SHUT.RDWR);
        thread.join();
    }

    var ca = websockets.CertCache.init(allocator);
    defer ca.deinit();

    var sock: ?websockets.Socket = try websockets.connectOptions(io, allocator, .{
        .host = "127.0.0.1",
        .port = chosen,
        .path = "/?v=10&encoding=json",
        .tls = false,
        .ca = &ca,
    });
    try std.testing.expect(ca.loaded);
    defer if (sock) |*s| s.deinit();
    sock.?.setReadTimeout(5000);

    const msg = (try sock.?.read()) orelse return error.TestUnexpectedNull;
    const text = websockets.messageData(msg) orelse return error.TestExpectedText;
    try std.testing.expectEqualStrings("hello world", text);

    try sock.?.sendText("{\"op\":1}");
    try sock.?.close();
    sock = null;

    _ = std.os.linux.shutdown(srv.socket.handle, std.os.linux.SHUT.RDWR);
    thread.join();
    if (ctx.err) |e| {
        std.debug.print("mock server failed: {any}\n", .{e});
        return error.MockServerFailed;
    }
}

test "close code parses big-endian u16" {
    var payload = [_]u8{ 0x0F, 0xA0 };
    const close = websockets.Message{ .type = .close, .data = &payload };
    try std.testing.expectEqual(@as(?u16, 4000), websockets.closeCode(close));
    const short = websockets.Message{ .type = .close, .data = &.{} };
    try std.testing.expect(websockets.closeCode(short) == null);
    const text = websockets.Message{ .type = .text, .data = @constCast("hi") };
    try std.testing.expect(websockets.closeCode(text) == null);
}
