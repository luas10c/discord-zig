const std = @import("std");

pub const Response = struct {
    status: std.http.Status,
    status_code: u16,
    head_bytes: []u8,
    body: []u8,

    pub fn deinit(self: *Response, allocator: std.mem.Allocator) void {
        allocator.free(self.head_bytes);
        allocator.free(self.body);
    }
};

pub const MultipartFile = struct {
    name: []const u8,
    filename: []const u8,
    content_type: []const u8 = "application/octet-stream",
    data: []const u8,
};

pub const MultipartBody = struct {
    body: []u8,
    content_type: []u8,

    pub fn deinit(self: *MultipartBody, allocator: std.mem.Allocator) void {
        allocator.free(self.body);
        allocator.free(self.content_type);
    }
};

var multipart_seq = std.atomic.Value(u64).init(0);

pub fn multipart(allocator: std.mem.Allocator, payload_json: []const u8, files: []const MultipartFile) !MultipartBody {
    var boundary_buf: [48]u8 = undefined;
    const boundary = try std.fmt.bufPrint(&boundary_buf, "----discord-zig-{x}", .{multipart_seq.fetchAdd(1, .monotonic)});

    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;
    try w.print("--{s}\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n", .{boundary});
    try w.writeAll(payload_json);
    try w.writeAll("\r\n");
    for (files) |f| {
        try w.print("--{s}\r\nContent-Disposition: form-data; name=\"{s}\"; filename=\"{s}\"\r\nContent-Type: {s}\r\n\r\n", .{ boundary, f.name, f.filename, f.content_type });
        try w.writeAll(f.data);
        try w.writeAll("\r\n");
    }
    try w.print("--{s}--\r\n", .{boundary});

    const content_type = try std.fmt.allocPrint(allocator, "multipart/form-data; boundary={s}", .{boundary});
    errdefer allocator.free(content_type);
    return .{ .body = try out.toOwnedSlice(), .content_type = content_type };
}

const builtin = @import("builtin");

pub fn isConnectionDead(conn: *std.http.Client.Connection) bool {
    if (builtin.os.tag == .windows) return false;
    const fd = conn.stream_reader.stream.socket.handle;
    var pfd = [_]std.posix.pollfd{.{
        .fd = fd,
        .events = std.posix.POLL.IN,
        .revents = 0,
    }};
    const rc = std.posix.poll(&pfd, 0) catch return true;
    if (rc != 0) {
        return true;
    }
    return false;
}

pub fn pruneDeadConnections(pool: *std.http.Client.ConnectionPool, io: std.Io) void {
    pool.mutex.lockUncancelable(io);
    defer pool.mutex.unlock(io);

    var it = pool.free.first;
    while (it) |node| {
        const next = node.next;
        const conn: *std.http.Client.Connection = @alignCast(@fieldParentPtr("pool_node", node));
        if (isConnectionDead(conn)) {
            pool.free.remove(node);
            pool.free_len -= 1;
            conn.destroy(io);
        }
        it = next;
    }
}

pub fn pruneAllConnections(pool: *std.http.Client.ConnectionPool, io: std.Io) void {
    pool.mutex.lockUncancelable(io);
    defer pool.mutex.unlock(io);

    var it = pool.free.first;
    while (it) |node| {
        const next = node.next;
        const conn: *std.http.Client.Connection = @alignCast(@fieldParentPtr("pool_node", node));
        pool.free.remove(node);
        pool.free_len -= 1;
        conn.destroy(io);
        it = next;
    }
}

fn configureSocket(fd: std.posix.fd_t) void {
    if (builtin.os.tag == .windows) return;
    const TCP_NODELAY: u32 = 1;
    _ = std.posix.setsockopt(fd, std.posix.IPPROTO.TCP, TCP_NODELAY, &std.mem.toBytes(@as(c_int, 1))) catch {};
    _ = std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.KEEPALIVE, &std.mem.toBytes(@as(c_int, 1))) catch {};
    const timeout = std.posix.timeval{ .sec = 10, .usec = 0 };
    _ = std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.RCVTIMEO, &std.mem.toBytes(timeout)) catch {};
    _ = std.posix.setsockopt(fd, std.posix.SOL.SOCKET, std.posix.SO.SNDTIMEO, &std.mem.toBytes(timeout)) catch {};
}

pub fn fetch(
    http: *std.http.Client,
    allocator: std.mem.Allocator,
    method: std.http.Method,
    url: []const u8,
    extra_headers: []const std.http.Header,
    json_body: ?[]const u8,
) !Response {
    const uri = try std.Uri.parse(url);
    pruneDeadConnections(&http.connection_pool, http.io);
    var req = try http.request(method, uri, .{
        .extra_headers = extra_headers,
        .headers = .{ .accept_encoding = .omit },
        .keep_alive = true,
    });
    defer req.deinit();

    if (req.connection) |conn| {
        configureSocket(conn.stream_reader.stream.socket.handle);
    }

    if (json_body) |body| {
        try req.sendBodyComplete(@constCast(body));
    } else if (method.requestHasBody()) {
        try req.sendBodyComplete(@constCast(@as([]const u8, "")));
    } else {
        try req.sendBodiless();
    }

    var redirect_buffer: [8192]u8 = undefined;
    var head = try req.receiveHead(&redirect_buffer);
    if (head.head.content_encoding != .identity) return error.UnexpectedContentEncoding;
    const head_copy = try allocator.dupe(u8, head.head.bytes);

    var body: []u8 = undefined;
    if (head.head.status != .no_content and head.head.status != .not_modified and method != .HEAD) {
        var transfer_buffer: [8192]u8 = undefined;
        var reader = head.reader(&transfer_buffer);
        var out: std.Io.Writer.Allocating = .init(allocator);
        errdefer out.deinit();
        _ = try reader.streamRemaining(&out.writer);
        body = try out.toOwnedSlice();
    } else {
        req.reader.state = .ready;
        body = try allocator.alloc(u8, 0);
    }

    return .{
        .status = head.head.status,
        .status_code = @intFromEnum(head.head.status),
        .head_bytes = head_copy,
        .body = body,
    };
}
