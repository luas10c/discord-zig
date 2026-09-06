const std = @import("std");
const fetch_mod = @import("discord-zig").fetch;

test "response deinit frees owned slices" {
    var res = fetch_mod.Response{
        .status = .ok,
        .status_code = 200,
        .head_bytes = try std.testing.allocator.dupe(u8, "HTTP/1.1 200 OK"),
        .body = try std.testing.allocator.dupe(u8, "{}"),
    };
    res.deinit(std.testing.allocator);
}

const HttpMockMode = enum { identity, forced_gzip };

const HttpMockCtx = struct {
    server: *std.Io.net.Server,
    mode: HttpMockMode,
    err: ?anyerror = null,
};

fn httpReadFull(io: std.Io, stream: *std.Io.net.Stream, buf: []u8) !void {
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

fn httpWriteAll(io: std.Io, stream: *std.Io.net.Stream, data: []const u8) !void {
    var wbuf: [4096]u8 = undefined;
    var w = stream.writer(io, &wbuf);
    try w.interface.writeAll(data);
    try w.interface.flush();
}

fn httpServerMain(ctx: *HttpMockCtx) void {
    httpServerRun(ctx) catch |err| {
        ctx.err = err;
        return;
    };
    ctx.err = null;
}

fn httpServerRun(ctx: *HttpMockCtx) !void {
    const io = std.testing.io;
    var stream = try ctx.server.accept(io);
    defer stream.close(io);

    var req_buf: [16384]u8 = undefined;
    var req_len: usize = 0;
    while (true) {
        if (req_len >= req_buf.len) return error.RequestTooLarge;
        var byte: [1]u8 = undefined;
        try httpReadFull(io, &stream, &byte);
        req_buf[req_len] = byte[0];
        req_len += 1;
        if (req_len >= 4 and std.mem.eql(u8, req_buf[req_len - 4 .. req_len], "\r\n\r\n")) break;
    }
    const head = req_buf[0..req_len];

    var lines = std.mem.splitSequence(u8, head, "\r\n");
    _ = lines.first();
    while (lines.next()) |line| {
        if (line.len == 0) break;
        const colon = std.mem.indexOfScalar(u8, line, ':') orelse continue;
        const name = std.mem.trim(u8, line[0..colon], " \t");
        const value = std.mem.trim(u8, line[colon + 1 ..], " \t");
        if (std.ascii.eqlIgnoreCase(name, "accept-encoding")) {
            if (std.ascii.indexOfIgnoreCase(value, "gzip") != null) return error.ClientAdvertisedGzip;
            if (std.ascii.indexOfIgnoreCase(value, "deflate") != null) return error.ClientAdvertisedDeflate;
        }
    }

    switch (ctx.mode) {
        .identity => {
            const body = "{\"id\":\"1\",\"username\":\"bot\"}";
            var resp_buf: [256]u8 = undefined;
            const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n{s}", .{ body.len, body });
            try httpWriteAll(io, &stream, resp);
        },
        .forced_gzip => {
            const garbage = "\x1f\x8b\x08\x00" ++ "not-really-gzip-but-binary-garbage.............";
            var resp_buf: [256]u8 = undefined;
            const resp = try std.fmt.bufPrint(&resp_buf, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Encoding: gzip\r\nContent-Length: {d}\r\nConnection: close\r\n\r\n", .{garbage.len});
            try httpWriteAll(io, &stream, resp);
            try httpWriteAll(io, &stream, garbage);
        },
    }
}

const MockSetup = struct {
    port: u16,
    server: std.Io.net.Server,
    thread: std.Thread,
    ctx: HttpMockCtx,
};

fn withMockServer(mode: HttpMockMode) !*MockSetup {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const setup = try allocator.create(MockSetup);
    errdefer allocator.destroy(setup);

    var bound = false;
    for ([_]u16{ 18551, 18552, 18553 }) |p| {
        var addr = std.Io.net.IpAddress{ .ip4 = .loopback(p) };
        if (std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true })) |s| {
            setup.* = .{
                .port = p,
                .server = s,
                .thread = undefined,
                .ctx = .{ .server = undefined, .mode = mode },
            };
            bound = true;
            break;
        } else |_| continue;
    }
    if (!bound) return error.CannotBindTestServer;
    errdefer setup.server.deinit(io);

    setup.ctx.server = &setup.server;
    setup.thread = try std.Thread.spawn(.{}, httpServerMain, .{&setup.ctx});
    return setup;
}

fn destroyMockServer(setup: *MockSetup) void {
    const io = std.testing.io;
    _ = std.os.linux.shutdown(setup.server.socket.handle, std.os.linux.SHUT.RDWR);
    setup.thread.join();
    setup.server.deinit(io);
    std.testing.allocator.destroy(setup);
}

test "omits gzip accept-encoding and reads identity body" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const setup = try withMockServer(.identity);
    defer destroyMockServer(setup);

    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/users/@me", .{setup.port});
    defer allocator.free(url);
    var http = std.http.Client{ .allocator = allocator, .io = io };
    defer http.deinit();
    var res = try fetch_mod.fetch(&http, allocator, .GET, url, &.{}, null);
    defer res.deinit(allocator);
    try std.testing.expectEqual(std.http.Status.ok, res.status);
    try std.testing.expectEqualStrings("{\"id\":\"1\",\"username\":\"bot\"}", res.body);
    try std.testing.expect(setup.ctx.err == null);
}

test "multipart body shape" {
    var mp = try fetch_mod.multipart(std.testing.allocator, "{\"content\":\"hi\"}", &.{
        .{ .name = "files[0]", .filename = "a.txt", .content_type = "text/plain", .data = "hello" },
    });
    defer mp.deinit(std.testing.allocator);
    try std.testing.expect(std.mem.startsWith(u8, mp.content_type, "multipart/form-data; boundary=----discord-zig-"));
    const boundary = mp.content_type["multipart/form-data; boundary=".len..];
    try std.testing.expect(std.mem.indexOf(u8, mp.body, boundary) != null);
    try std.testing.expect(std.mem.indexOf(u8, mp.body, "name=\"payload_json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, mp.body, "{\"content\":\"hi\"}") != null);
    try std.testing.expect(std.mem.indexOf(u8, mp.body, "name=\"files[0]\"; filename=\"a.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, mp.body, "Content-Type: text/plain") != null);
    try std.testing.expect(std.mem.indexOf(u8, mp.body, "hello") != null);
    try std.testing.expect(std.mem.endsWith(u8, mp.body, "--\r\n"));
}

test "forced gzip response fails loudly" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;
    const setup = try withMockServer(.forced_gzip);
    defer destroyMockServer(setup);

    const url = try std.fmt.allocPrint(allocator, "http://127.0.0.1:{d}/users/@me", .{setup.port});
    defer allocator.free(url);
    var http = std.http.Client{ .allocator = allocator, .io = io };
    defer http.deinit();
    try std.testing.expectError(
        error.UnexpectedContentEncoding,
        fetch_mod.fetch(&http, allocator, .GET, url, &.{}, null),
    );
    try std.testing.expect(setup.ctx.err == null);
}

test "keep-alive preserves connection and handles 204 No Content" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const Mock204 = struct {
        fn run(server: *std.Io.net.Server, s_io: std.Io) !void {
            var stream = try server.accept(s_io);
            defer stream.close(s_io);

            for (0..2) |_| {
                var line_buf: [1024]u8 = undefined;
                var line_len: usize = 0;
                while (true) {
                    var byte: [1]u8 = undefined;
                    try httpReadFull(s_io, &stream, &byte);
                    line_buf[line_len] = byte[0];
                    line_len += 1;
                    if (line_len >= 4 and std.mem.eql(u8, line_buf[line_len - 4 .. line_len], "\r\n\r\n")) break;
                }

                var wbuf: [1024]u8 = undefined;
                var w = stream.writer(s_io, &wbuf);
                const resp = "HTTP/1.1 204 No Content\r\nConnection: keep-alive\r\n\r\n";
                try w.interface.writeAll(resp);
                try w.interface.flush();
            }
        }
    };

    var addr = std.Io.net.IpAddress{ .ip4 = .loopback(19890) };
    var server = try std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true });
    defer server.deinit(io);

    const thread = try std.Thread.spawn(.{}, Mock204.run, .{ &server, io });

    var http = std.http.Client{ .allocator = allocator, .io = io };
    defer http.deinit();

    const url = "http://127.0.0.1:19890/interactions/123/callback";
    for (0..2) |i| {
        var res = try fetch_mod.fetch(&http, allocator, .POST, url, &.{}, "{}");
        defer res.deinit(allocator);
        try std.testing.expectEqual(std.http.Status.no_content, res.status);
        try std.testing.expectEqual(@as(usize, 0), res.body.len);
        if (i == 0) {
            try std.testing.expectEqual(@as(usize, 1), http.connection_pool.free_len);
        }
    }

    thread.join();
}

test "pruneDeadConnections removes closed connections from pool" {
    const io = std.testing.io;
    const allocator = std.testing.allocator;

    const MockClose = struct {
        fn run(server: *std.Io.net.Server, s_io: std.Io) !void {
            var stream = try server.accept(s_io);
            defer stream.close(s_io);

            var line_buf: [1024]u8 = undefined;
            var line_len: usize = 0;
            while (true) {
                var byte: [1]u8 = undefined;
                try httpReadFull(s_io, &stream, &byte);
                line_buf[line_len] = byte[0];
                line_len += 1;
                if (line_len >= 4 and std.mem.eql(u8, line_buf[line_len - 4 .. line_len], "\r\n\r\n")) break;
            }

            var wbuf: [1024]u8 = undefined;
            var w = stream.writer(s_io, &wbuf);
            const resp = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\n{}";
            try w.interface.writeAll(resp);
            try w.interface.flush();
        }
    };

    var addr = std.Io.net.IpAddress{ .ip4 = .loopback(19891) };
    var server = try std.Io.net.IpAddress.listen(&addr, io, .{ .reuse_address = true });
    defer server.deinit(io);

    const thread = try std.Thread.spawn(.{}, MockClose.run, .{ &server, io });

    var http = std.http.Client{ .allocator = allocator, .io = io };
    defer http.deinit();

    const url = "http://127.0.0.1:19891/test";
    var res = try fetch_mod.fetch(&http, allocator, .GET, url, &.{}, null);
    res.deinit(allocator);

    thread.join();

    // Server closed the connection after response, so the connection in the pool is now dead
    try std.testing.expectEqual(@as(usize, 1), http.connection_pool.free_len);
    fetch_mod.pruneDeadConnections(&http.connection_pool, io);
    try std.testing.expectEqual(@as(usize, 0), http.connection_pool.free_len);
}
