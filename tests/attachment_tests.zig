const std = @import("std");
const attachment = @import("discord-zig").attachment;

test "attachment builder validation" {
    var b = attachment.Builder.init(std.testing.allocator);
    defer b.deinit();
    try std.testing.expectError(error.MissingFilename, b.build());

    try b.setFilename("a.txt");
    try std.testing.expectError(error.MissingData, b.build());

    try b.setData("hi");
    try b.setContentType("text/plain");
    try b.setDescription("greeting");
    const built = try b.build();
    try std.testing.expectEqualStrings("a.txt", built.filename);
    try std.testing.expectEqualStrings("hi", built.data);
    try std.testing.expectEqualStrings("text/plain", built.content_type);
    try std.testing.expectEqualStrings("greeting", built.description.?);

    const part = built.toMultipart("files[0]");
    try std.testing.expectEqualStrings("files[0]", part.name);
    try std.testing.expectEqualStrings("a.txt", part.filename);
}

test "attachment builder rejects empty" {
    var b = attachment.Builder.init(std.testing.allocator);
    defer b.deinit();
    try b.setFilename("a.txt");
    try b.setData("");
    try std.testing.expectError(error.MissingData, b.build());
}
