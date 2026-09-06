const std = @import("std");
const fetch_mod = @import("./fetch.zig");

pub const max_filename_len = 256;
pub const max_description_len = 1024;

pub const BuildError = error{
    MissingFilename,
    MissingData,
    FilenameTooLong,
    DescriptionTooLong,
} || std.mem.Allocator.Error;

pub const Attachment = struct {
    filename: []const u8,
    data: []const u8,
    content_type: []const u8 = "application/octet-stream",
    description: ?[]const u8 = null,

    pub fn toMultipart(self: Attachment, name: []const u8) fetch_mod.MultipartFile {
        return .{
            .name = name,
            .filename = self.filename,
            .content_type = self.content_type,
            .data = self.data,
        };
    }
};

pub const Builder = struct {
    arena: std.heap.ArenaAllocator,
    filename: ?[]const u8 = null,
    data: ?[]const u8 = null,
    content_type: []const u8 = "application/octet-stream",
    description: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .arena = std.heap.ArenaAllocator.init(allocator) };
    }

    pub fn deinit(self: *Builder) void {
        self.arena.deinit();
        self.* = undefined;
    }

    pub fn setFilename(self: *Builder, filename: []const u8) !void {
        self.filename = try self.arena.allocator().dupe(u8, filename);
    }

    pub fn setData(self: *Builder, data: []const u8) !void {
        self.data = try self.arena.allocator().dupe(u8, data);
    }

    pub fn setContentType(self: *Builder, content_type: []const u8) !void {
        self.content_type = try self.arena.allocator().dupe(u8, content_type);
    }

    pub fn setDescription(self: *Builder, description: []const u8) !void {
        self.description = try self.arena.allocator().dupe(u8, description);
    }

    pub fn build(self: *Builder) BuildError!Attachment {
        const filename = self.filename orelse return error.MissingFilename;
        if (filename.len == 0 or filename.len > max_filename_len) return error.FilenameTooLong;
        const data = self.data orelse return error.MissingData;
        if (data.len == 0) return error.MissingData;
        if (self.description) |d| {
            if (d.len > max_description_len) return error.DescriptionTooLong;
        }
        return .{
            .filename = filename,
            .data = data,
            .content_type = self.content_type,
            .description = self.description,
        };
    }
};
