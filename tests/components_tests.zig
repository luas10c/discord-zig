const std = @import("std");
const components = @import("discord-zig").components;
const schema = @import("discord-zig").schema;
const slash = @import("discord-zig").slash;

test "button builds compact json" {
    var b = components.ButtonBuilder.init(std.testing.allocator);
    defer b.deinit();
    b.setStyle(.primary);
    try b.setLabel("Go");
    try b.setCustomId("b1");
    const built = try b.build();
    const body = try schema.stringify(std.testing.allocator, built);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"type\":2,\"style\":1,\"label\":\"Go\",\"custom_id\":\"b1\",\"disabled\":false}", body);
}

test "link button needs url without custom id" {
    var b = components.ButtonBuilder.init(std.testing.allocator);
    defer b.deinit();
    b.setStyle(.link);
    try b.setLabel("Docs");
    try std.testing.expectError(error.MissingUrl, b.build());

    try b.setUrl("https://example.com");
    try b.setCustomId("x");
    try std.testing.expectError(error.UnexpectedUrl, b.build());
}

test "action row holds buttons and rejects mixes" {
    var b1 = components.ButtonBuilder.init(std.testing.allocator);
    defer b1.deinit();
    try b1.setLabel("A");
    try b1.setCustomId("a");
    const c1 = try b1.build();

    var b2 = components.ButtonBuilder.init(std.testing.allocator);
    defer b2.deinit();
    try b2.setLabel("B");
    try b2.setCustomId("b");
    const c2 = try b2.build();

    var row = components.ActionRowBuilder.init(std.testing.allocator);
    defer row.deinit();
    try row.add(c1);
    try row.add(c2);
    const built = try row.build();
    const body = try schema.stringify(std.testing.allocator, built);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"type\":1,\"components\":[{\"type\":2,\"style\":1,\"label\":\"A\",\"custom_id\":\"a\",\"disabled\":false},{\"type\":2,\"style\":1,\"label\":\"B\",\"custom_id\":\"b\",\"disabled\":false}]}", body);

    var sel = components.StringSelectBuilder.init(std.testing.allocator);
    defer sel.deinit();
    try sel.setCustomId("s");
    try sel.addOption(.{ .label = "x", .value = "x" });
    try row.add(try sel.build());
    try std.testing.expectError(error.MixedRowChildren, row.build());
}

test "string select builds options json" {
    var sel = components.StringSelectBuilder.init(std.testing.allocator);
    defer sel.deinit();
    try sel.setCustomId("pick");
    try sel.setPlaceholder("choose");
    try sel.addOption(.{ .label = "First", .value = "1", .description = "the first" });
    try sel.addOption(.{ .label = "Second", .value = "2" });
    const built = try sel.build();
    const body = try schema.stringify(std.testing.allocator, built);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"type\":3,\"custom_id\":\"pick\",\"options\":[{\"label\":\"First\",\"value\":\"1\",\"description\":\"the first\",\"default\":false},{\"label\":\"Second\",\"value\":\"2\",\"default\":false}],\"placeholder\":\"choose\",\"disabled\":false}", body);

    var empty = components.StringSelectBuilder.init(std.testing.allocator);
    defer empty.deinit();
    try empty.setCustomId("e");
    try std.testing.expectError(error.TooManyOptions, empty.build());
}

test "modal with text input builds type 9 body" {
    var input = components.TextInputBuilder.init(std.testing.allocator);
    defer input.deinit();
    try input.setCustomId("field-a");
    try input.setLabel("Name");
    input.setStyle(.short);
    const field = try input.build();

    var row = components.ActionRowBuilder.init(std.testing.allocator);
    defer row.deinit();
    try row.add(field);
    const row_built = try row.build();

    var modal = components.ModalBuilder.init(std.testing.allocator);
    defer modal.deinit();
    try modal.setCustomId("modal-x");
    try modal.setTitle("Hi");
    try modal.addRow(row_built);
    const built = try modal.build();
    const body = try slash.modalBody(std.testing.allocator, built);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"type\":9,\"data\":{\"title\":\"Hi\",\"custom_id\":\"modal-x\",\"components\":[{\"type\":1,\"components\":[{\"type\":4,\"custom_id\":\"field-a\",\"style\":1,\"label\":\"Name\",\"required\":true}]}]}}", body);
}

test "modal rows must hold a single text input" {
    var b = components.ButtonBuilder.init(std.testing.allocator);
    defer b.deinit();
    try b.setLabel("A");
    try b.setCustomId("a");
    const btn = try b.build();

    var row = components.ActionRowBuilder.init(std.testing.allocator);
    defer row.deinit();
    try row.add(btn);
    const row_built = try row.build();

    var modal = components.ModalBuilder.init(std.testing.allocator);
    defer modal.deinit();
    try modal.setCustomId("m");
    try modal.setTitle("T");
    try modal.addRow(row_built);
    try std.testing.expectError(error.ModalRowMustBeTextInput, modal.build());
}

test "container with section and text builds v2 json" {
    var btn = components.ButtonBuilder.init(std.testing.allocator);
    defer btn.deinit();
    try btn.setLabel("Ok");
    try btn.setCustomId("ok");
    const button = try btn.build();

    var text = components.TextDisplayBuilder.init(std.testing.allocator);
    defer text.deinit();
    try text.setContent("Hello **world**");
    const display = try text.build();

    var section = components.SectionBuilder.init(std.testing.allocator);
    defer section.deinit();
    try section.addText(display);
    try section.setAccessory(button);
    const section_built = try section.build();

    var sep = components.SeparatorBuilder.init();
    sep.setDivider(true);
    sep.setSpacing(2);
    const sep_built = try sep.build();

    var container = components.ContainerBuilder.init(std.testing.allocator);
    defer container.deinit();
    container.setAccentColor(0xFF0000);
    try container.add(section_built);
    try container.add(sep_built);
    const built = try container.build();
    const body = try schema.stringify(std.testing.allocator, built);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"type\":17,\"accent_color\":16711680,\"components\":[{\"type\":9,\"components\":[{\"type\":10,\"content\":\"Hello **world**\"}],\"accessory\":{\"type\":2,\"style\":1,\"label\":\"Ok\",\"custom_id\":\"ok\",\"disabled\":false}},{\"type\":14,\"divider\":true,\"spacing\":2}]}", body);
}

test "gallery file thumbnail json" {
    var gallery = components.MediaGalleryBuilder.init(std.testing.allocator);
    defer gallery.deinit();
    try gallery.addItem(.{ .media_url = "https://example.com/a.png", .description = "a" });
    const g = try gallery.build();
    const gbody = try schema.stringify(std.testing.allocator, g);
    defer std.testing.allocator.free(gbody);
    try std.testing.expectEqualStrings("{\"type\":12,\"items\":[{\"media\":{\"url\":\"https://example.com/a.png\"},\"description\":\"a\"}]}", gbody);

    var file = components.FileBuilder.init(std.testing.allocator);
    defer file.deinit();
    try file.setFileUrl("attachment://a.txt");
    try file.setName("a.txt");
    const f = try file.build();
    const fbody = try schema.stringify(std.testing.allocator, f);
    defer std.testing.allocator.free(fbody);
    try std.testing.expectEqualStrings("{\"type\":13,\"name\":\"a.txt\",\"file\":{\"url\":\"attachment://a.txt\"}}", fbody);

    var thumb = components.ThumbnailBuilder.init(std.testing.allocator);
    defer thumb.deinit();
    try thumb.setMediaUrl("https://example.com/t.png");
    const t = try thumb.build();
    const tbody = try schema.stringify(std.testing.allocator, t);
    defer std.testing.allocator.free(tbody);
    try std.testing.expectEqualStrings("{\"type\":11,\"media\":{\"url\":\"https://example.com/t.png\"}}", tbody);
}

test "premium button and select default values" {
    var premium = components.ButtonBuilder.init(std.testing.allocator);
    defer premium.deinit();
    premium.setStyle(.premium);
    try premium.setSkuId("123");
    const p = try premium.build();
    const pbody = try schema.stringify(std.testing.allocator, p);
    defer std.testing.allocator.free(pbody);
    try std.testing.expectEqualStrings("{\"type\":2,\"style\":6,\"sku_id\":\"123\",\"disabled\":false}", pbody);

    var no_sku = components.ButtonBuilder.init(std.testing.allocator);
    defer no_sku.deinit();
    no_sku.setStyle(.premium);
    try std.testing.expectError(error.MissingSkuId, no_sku.build());

    var sel = components.EntitySelectBuilder.init(std.testing.allocator, .user_select);
    defer sel.deinit();
    try sel.setCustomId("u");
    try sel.addDefaultValue("9", "user");
    const s = try sel.build();
    const sbody = try schema.stringify(std.testing.allocator, s);
    defer std.testing.allocator.free(sbody);
    try std.testing.expectEqualStrings("{\"type\":5,\"custom_id\":\"u\",\"default_values\":[{\"id\":\"9\",\"type\":\"user\"}],\"disabled\":false}", sbody);
}

test "label modal builds and submits" {
    var input = components.TextInputBuilder.init(std.testing.allocator);
    defer input.deinit();
    try input.setCustomId("field-a");
    try input.setLabel("Name");
    const field = try input.build();

    var label = components.LabelBuilder.init(std.testing.allocator);
    defer label.deinit();
    try label.setLabel("Your name");
    try label.setDescription("First and last");
    try label.setChild(field);
    const label_built = try label.build();

    var modal = components.ModalBuilder.init(std.testing.allocator);
    defer modal.deinit();
    try modal.setCustomId("modal-x");
    try modal.setTitle("Hi");
    try modal.addRow(label_built);
    const built = try modal.build();
    const body = try slash.modalBody(std.testing.allocator, built);
    defer std.testing.allocator.free(body);
    try std.testing.expectEqualStrings("{\"type\":9,\"data\":{\"title\":\"Hi\",\"custom_id\":\"modal-x\",\"components\":[{\"type\":18,\"label\":\"Your name\",\"description\":\"First and last\",\"component\":{\"type\":4,\"custom_id\":\"field-a\",\"style\":1,\"label\":\"Name\",\"required\":true}}]}}", body);

    const submit =
        \\{"id":"12","application_id":"2","type":5,"token":"t","data":{"custom_id":"modal-x","components":[{"type":18,"id":1,"component":{"type":4,"id":2,"custom_id":"field-a","value":"hello"}}]}}
    ;
    var parsed = try schema.parse(schema.Interaction, std.testing.allocator, submit);
    defer parsed.deinit();
    try std.testing.expectEqualStrings("hello", parsed.value.data.?.getTextInput("field-a").?);
}

test "modal select menu with min_values 0 serializes required false" {
    var sel = components.ChannelSelectMenuBuilder.init(std.testing.allocator);
    defer sel.deinit();
    try sel.setCustomId("log_channel");
    try sel.setPlaceholder("#mod-log");
    sel.setMinValues(0);
    sel.setMaxValues(1);
    const child = try sel.build();

    try std.testing.expectEqual(false, child.required.?);

    var label = components.LabelBuilder.init(std.testing.allocator);
    defer label.deinit();
    try label.setLabel("Log Channel");
    try label.setDescription("Logs");
    try label.setChild(child);
    const row = try label.build();

    var modal = components.ModalBuilder.init(std.testing.allocator);
    defer modal.deinit();
    try modal.setCustomId("modal-test");
    try modal.setTitle("Test");
    try modal.addRow(row);
    const built = try modal.build();

    const body = try slash.modalBody(std.testing.allocator, built);
    defer std.testing.allocator.free(body);

    try std.testing.expectEqualStrings("{\"type\":9,\"data\":{\"title\":\"Test\",\"custom_id\":\"modal-test\",\"components\":[{\"type\":18,\"label\":\"Log Channel\",\"description\":\"Logs\",\"component\":{\"type\":8,\"custom_id\":\"log_channel\",\"placeholder\":\"#mod-log\",\"min_values\":0,\"max_values\":1,\"required\":false,\"disabled\":false}}]}}", body);
}

test "select menu with required true and min_values 0 returns error" {
    var sel = components.StringSelectBuilder.init(std.testing.allocator);
    defer sel.deinit();
    try sel.setCustomId("s");
    sel.setMinValues(0);
    sel.setMaxValues(2);
    sel.setRequired(true);
    try sel.addOption(.{ .label = "A", .value = "a" });
    try std.testing.expectError(error.RequiredZeroMinValues, sel.build());
}

