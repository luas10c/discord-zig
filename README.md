# discord-zig

Cliente da API oficial do Discord em Zig puro, sem dependências externas. Fala direto com a [documentação oficial](https://docs.discord.com/developers/reference): REST (`GET`, `POST`, `PUT`, `PATCH`, `DELETE` via `fetch.zig`) e Gateway em tempo real (WebSocket com `std` apenas, sem libs).

Requer Zig `0.16.0` ou superior.

## Instalação

No seu projeto:

```sh
zig fetch --save https://github.com/SEU_USUARIO/discord-zig
```

Troque `SEU_USUARIO` pela conta onde o repositório foi publicado. O comando preenche `url` e `hash` em `build.zig.zon`:

```zig
.dependencies = .{
    .discord_zig = .{
        .url = "https://github.com/SEU_USUARIO/discord-zig/archive/<commit>.tar.gz",
        .hash = "<hash-gerado-pelo-fetch>",
    },
},
```

No `build.zig`:

```zig
const discord = b.dependency("discord_zig", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("discord-zig", discord.module("discord-zig"));
```

E no código:

```zig
const discord = @import("discord-zig");
```

## Bot mínimo (Gateway)

Conecta no Gateway, identifica com intents padrão e mantém heartbeat/resume:

```zig
const std = @import("std");
const discord = @import("discord-zig");
const Client = discord.client.Client;
const Events = discord.events.Events;
const GatewayIntentBits = discord.GatewayIntentBits;

pub fn main(init: std.process.Init) !void {
    const token = init.environ_map.get("DISCORD_TOKEN") orelse return error.MissingToken;

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
```

```sh
DISCORD_TOKEN=seu-token zig build run
```

`client.on` registra um handler persistente e `client.once` um que dispara uma única vez; ambos aceitam o enum `discord.events.Events` (`Events.ClientReady`, igual discord.js), o enum interno (`events.Type.message_create`) ou o nome em string (`"messageCreate"`, `"clientReady"`). `client.off` remove os dois. Nome ou assinatura inválidos viram erro de compilação. Handlers são `fn (*Client, Payload) void` e bloqueiam o heartbeat, então faça o mínimo e devolva.

## Reconexão

`login` nunca desiste sozinho: valida o token, conecta e entra em loop. Quedas transportáveis (`HeartbeatTimeout`, `ConnectionClosed`, op 7 `Reconnect`, op 9 com `d=true`, close com código resumível) disparam backoff exponencial com teto de 30s e reconexão automática — com `resume` (op 6) quando há `session_id`, ou `identify` do zero quando não há. O `READY` sempre salva `session_id`/`resume_gateway_url` para a próxima tentativa (inclusive via `resume_gateway_url` quando o Discord indica outro host).

Erros fatais retornam para o chamador em vez de girar em loop: token inválido (`Unauthorized` na validação), close `4004` (auth) e `4010`–`4014` (shard/intents/config, logados com o nome do código via `gateway.closeCodeName`). Op 9 com `d=false` limpa a sessão e reidentifica.

## Reações

```zig
client.on("messageReactionAdd", onReaction);

fn onReaction(_c: *Client, r: discord.schema.MessageReaction) void {
    _ = _c;
    const name = r.emoji.name orelse "?"; // "🔥" para unicode, nome para custom
    std.debug.print("{s} reagiu com {s} em {s}\n", .{ r.user_id, name, r.message_id });
}
```

Eventos cobertos: `messageReactionAdd`, `messageReactionRemove`, `messageReactionRemoveAll` e `messageReactionRemoveEmoji`. Exigem as intents `guild_message_reactions` (servidores) e/ou `direct_message_reactions` (DMs):

```zig
var client = Client.init(gpa, io, .{
    .intents = .{ GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessageReactions },
});
```

Sem camada de partials por decisão: o evento já traz todos os IDs (`user_id`, `message_id`, `channel_id`, `guild_id`) mais o `emoji` (`id` nulo para unicode), então não há objeto "incompleto" para completar. Se precisar da mensagem ou do usuário inteiro, é uma chamada REST (`GET /channels/{id}/messages/{id}`, `GET /users/{id}`) a partir dos IDs.

## REST

```zig
const std = @import("std");
const discord = @import("discord-zig");

pub fn main(init: std.process.Init) !void {
    var rest = discord.client.Rest.init(init.gpa, init.io, "seu-token");
    defer rest.deinit();

    var me = try rest.getCurrentUser();
    defer me.deinit();
    std.debug.print("logado como {s}\n", .{me.value.username});

    var msg = try rest.createMessage("CHANNEL_ID", "Olá do Zig!");
    defer msg.deinit();
    std.debug.print("mensagem {s} enviada\n", .{msg.value.id});
}
```

`try client.login(token)` valida o token com `GET /users/@me`, conecta no Gateway e roda o loop (heartbeat/resume/dispatch) até falhar; falha cedo com `Unauthorized` se o token for inválido. O `Client` guarda uma cópia própria do token.

Para chamadas de baixo nível (`GET`, `POST`, `PUT`, `PATCH`, `DELETE` com headers customizados), use `discord.fetch.fetch` direto ou `rest.request(.GET, "/users/@me", null)`. Respostas trazem `rate_limit` (`X-RateLimit-*`) e `retry_after` para respeitar o limite de 50 req/s e os buckets por rota.

## Slash commands

```zig
var cmd = discord.slash.Command.init(gpa, "eco", "Ecoa texto");
defer cmd.deinit();

try cmd.addStringOption("texto", "o que ecoar", true);
try cmd.addChoice("texto", "curto", .{ .string = "s" });
try cmd.addIntegerOption("vezes", "repetições", false);
const built = try cmd.build();

const body = try discord.slash.encodeCommands(gpa, &.{built});
defer gpa.free(body);

var registered = try rest.registerGuildCommands("APP_ID", "GUILD_ID", body);
defer registered.deinit();
```

`build()` valida as regras do Discord e falha com erro tipado (`NameInvalid`, `TooManyOptions`, `RequiredAfterOptional`, `BadNesting`, `ChoiceOnWrongType`...): nome 1-32 minúsculo, descrição 1-100, até 25 opções, required antes das opcionais, subcomandos sem `required`. Use comandos de guilda para testar (propagam na hora); os globais levam até 1h. O resultado pega memória da arena do builder, então use antes do `deinit`.

Para responder estilo discord.js, use o handle `slash.Interaction` (ele guarda `id`/`token`/`application_id` emprestados do evento e chama o REST por você):

```zig
fn onInteraction(c: *Client, inter: discord.schema.Interaction) void {
    if (inter.type != 2) return;
    var interaction = discord.slash.Interaction.init(&c.rest, inter);

    const start = discord.util.nowMs(c.io);
    interaction.deferReply(.{ .flags = .{discord.MessageFlags.Ephemeral} }) catch return;
    const end = discord.util.nowMs(c.io);

    const text = std.fmt.allocPrint(c.allocator, "🏓 Pong!\n{d} ms", .{end - start}) catch return;
    defer c.allocator.free(text);
    interaction.editReply(.{ .content = text }) catch return;
}
```

`deferReply`/`reply` aceitam `.{ .flags = ... }` com tupla de `MessageFlags`/`Bits`/`u32` (omitido = sem flags); `reply`/`editReply`/`followUp` levam `.content`, `.embeds`, `.components`, `.attachments` e `.poll` (com arquivos vai multipart sozinho). `followUp` retorna a `Message` criada. Para componentes: `update(...)` (type 7, edita inline) e `deferUpdate()` (type 6). O handle tem ainda `deleteReply` (@original), `deleteFollowUp(id)`, `fetchReply` (retorna a Message com `.poll`), `autocomplete(choices)`, `pong` e `showModal(modal)`. Para o nível baixo, `rest.respondInteraction(id, token, body)` com `slash.reply(gpa, "...", .{discord.MessageFlags.Ephemeral})`, `slash.deferReply(gpa, .{discord.MessageFlags.Ephemeral})`, `slash.autocompleteBody(gpa, choices)` ou `slash.modalBody(gpa, modal)`; `rest` tem também `respondInteractionWithResponse` (`?with_response=true`), `getOriginalInteractionResponse`, `followUp`, `deleteInitialResponse` e `deleteFollowUp`.

Interações de botão/select (type 3) trazem `data.custom_id`, `data.component_type` e `message`; autocomplete (type 4) marca a opção com `focused` (`data.getFocused()`); modal submit (type 5) traz `data.components` (`data.getTextInput("custom-id")`). Guards: `inter.isChatInput()`, `isComponent()`, `isAutocomplete()`, `isModalSubmit()`, `isPing()`.

No registro, `cmd.setDefaultPermissions("8")`, `cmd.setNsfw(true)`, `cmd.setContexts(&.{0, 1})` e `cmd.setIntegrationTypes(&.{0})` (campos omitidos quando não usados). Localizações: `cmd.setNameLocalization("pt-BR", "ping")`; autocomplete: `cmd.addAutocompleteStringOption("q", "termo", true)` (só string/integer/number) + `interaction.autocomplete(&choices)`; limites: `min_value/max_value/min_length/max_length` no `OptionInput`; grupos: `cmd.addSubcommandGroup("user", "d", &.{...})`.

## Components e modais

```zig
var btn = discord.components.ButtonBuilder.init(gpa);
defer btn.deinit();
try btn.setLabel("Confirmar");
try btn.setCustomId("ok");

var row = discord.components.ActionRowBuilder.init(gpa);
defer row.deinit();
try row.add(try btn.build());

// no reply: interaction.reply(.{ .content = "?", .components = &.{row_built} })
```

Builders com validação tipada: `ButtonBuilder` (link exige `setUrl`, premium exige `setSkuId`, resto exige `setCustomId`), `StringSelectBuilder` (+ `EntitySelectBuilder` para user/role/mentionable/channel, com `addDefaultValue`), `TextInputBuilder`, `ActionRowBuilder` (5 botões ou 1 select/texto) e `ModalBuilder` (`interaction.showModal(try modal.build())`). Selects de componente chegam com `data.values` (+ `data.resolved` opaco); o JSON emitido omite nulos (Discord é estrito).

## Components v2

```zig
var text = discord.components.TextDisplayBuilder.init(gpa);
defer text.deinit();
try text.setContent("Hello **world**");

var section = discord.components.SectionBuilder.init(gpa);
defer section.deinit();
try section.addText(try text.build());
try section.setAccessory(try btn.build()); // botão ou thumbnail

var box = discord.components.ContainerBuilder.init(gpa);
defer box.deinit();
box.setAccentColor(0xFF0000);
try box.add(try section.build());

// defer sem flags, depois edit com a flag v2 (content some — v2 desliga content/embeds):
try interaction.deferReply(.{});
try interaction.editReply(.{ .flags = .{discord.message.MessageFlags.IsComponentsV2}, .components = &.{box_built} });
```

Builders: `Container`, `Section` (1-3 textos + acessório), `TextDisplay`, `Thumbnail`, `MediaGallery` (1-10 itens), `File` (URL `attachment://` expõe upload), `Separator`, `Label` (modais modernos no lugar de ActionRow — `getTextInput` lê os dois shapes). Legacy continua suportado (mensagens normais + modais antigos); v2 desliga `content`/`embeds` na mensagem.

## Polls e anexos

```zig
var poll = discord.poll.Builder.init(gpa);
defer poll.deinit();
try poll.setQuestion("Melhor linguagem?");
try poll.addAnswer(.{ .text = "Zig", .emoji_name = "⚡" });
try poll.addAnswer(.{ .text = "Outra", .emoji_id = "123456789", .emoji_name = "pepe" });
poll.setDurationHours(24);
const poll_data = try poll.build();

// Enviar em resposta de slash command:
try interaction.reply(.{ .content = "Votem!", .poll = poll_data });

// Ou via canal / REST:
var created = try chan.sendPoll(poll_data); // ou rest.createPollMessage("C", poll_data)
defer created.deinit();

// Ler dados da enquete na mensagem:
if (created.value.poll) |p| {
    std.debug.print("total votos: {d}\n", .{p.totalVotes()});
}

// Encerrar enquete e listar votantes:
try chan.messages.endPoll(created.value.id); // ou rest.endPoll("C", id)
var voters = try chan.messages.fetchPollAnswerVoters(created.value.id, 1, null, 25);
defer voters.deinit();

var ab = discord.attachment.Builder.init(gpa);
defer ab.deinit();
try ab.setFilename("a.txt");
try ab.setData("hi");
const files = [_]discord.attachment.Attachment{try ab.build()};
var sent = try rest.createMessageWithAttachments("C", "yo", &files);
defer sent.deinit();
```

## Eventos

~70 tipos (`Events.X` estilo discord.js, mais string `"camelCase"`/`"snake_case"` ou o `Type` direto no `on`). Inclui threads, voz (`VoiceState`/`VoiceServerUpdate` structs), presence, typing, invites, bans, roles (`schema.Role`), emojis/stickers, audit log, automod, entitlements, scheduled events, soundboard, stage, polls e webhooks. Divergência consciente: `GUILD_EMOJIS/STICKERS_UPDATE` chega como um evento só (o djs diferencia create/update/delete via cache). Sem partials por decisão. Para listar membros de guild grande: `client.requestGuildMembers(guild_id)` (ou `...Query`) e escute `GuildMembersChunk` (já alimenta o cache).

## REST

`rest.request` expõe `rate_limit`/`retry_after` e **retenta 429 sozinho** (até 3× respeitando `retry_after`, teto 30s). **Timeout padrão de 15s** por request (`rest.timeout_ns = null` desliga; sem keep-alive de propósito — reuso de conexão ociosa travava em retransmissão). `rest.requestFull` aceita content-type custom e `X-Audit-Log-Reason`. Upload: `fetch.multipart` + `rest.createMessageWithFiles`.

## Fachadas estilo discord.js

Camada fina sobre o `Rest` (que continua como transporte de baixo nível), com navegação `guild → channels` e `fetch` cache-first — o gateway alimenta o cache, o `fetch` só vai à rede no miss (e guarda o resultado):

```zig
var guild = try client.guilds.fetch("G");
var chan = try guild.channels.fetch("C"); // hit no cache, sem HTTP
var same = guild.channels.findByName("geral"); // ?Channel, null se fora da guild
var all = try client.guilds.fetchAll(10); // sem id: lista tudo
defer all.deinit();

var sent = try chan.send("hi");
defer sent.deinit();
try chan.messages.react(sent.value.id, "🔥");
try chan.permissionOverwrites.edit("R", .role, permission.view_channel, 0, "mod");

try guild.members.kick("U", "spam");
var r = try guild.roles.create("mod", null);
defer r.deinit();

var m = discord.member.Member.init(&client, "G", "U");
try m.roles.add("R", null);
const bits = try m.permissionsIn(channel, &roles, owner_id);
```

`guild.members` (fetch/fetchMany/kick/ban/unban/prune/bulkBan/search/fetchMe), `guild.roles` (fetchAll/create/edit/delete/setPositions), `guild.channels` (fetch/fetchAll/findByName/create), `guild.bans` (fetch/remove), `guild` (fetch/edit/fetchOwner/fetchAuditLogs/fetchInvites/fetchActiveThreads/fetchTemplates/createTemplate/fetchOnboarding/editOnboarding/fetchWelcomeScreen/editWelcomeScreen/fetchWidget*/editWidgetSettings/fetchVanityUrl/prune/bulkBan/search/fetchMe); `member` (fetch/editNick/kick/ban/timeout/permissions/permissionsIn/presence) + `member.roles` (add/remove/set) + `member.voice` (setMute/setDeaf/move/disconnect); `channel.messages` (fetch/fetchMany/edit/delete/react/pin/reply) + `permissionOverwrites` (set/edit/editOptions/delete) + `channel.invites` (fetch/create/delete) + `channel.threads` (start/join/leave/addMember/removeMember/fetchMembers/fetchArchived*/setArchived); `client.users` (fetch) + `user` (fetch/send); global via `client.channels.fetch(id)`. Retornos `Parsed` são do chamador (`defer deinit`); handles guardam o `id` emprestado (passe literais ou strings vivas — `findByName` empresta do cache).

Regras dos managers (são campos, não objetos): use sempre encadeado (`client.guilds.fetch`, nunca `const mng = client.guilds`) e o dono com `var` (`var guild = ...`, nunca `const`), pois o manager localiza o pai pelo próprio endereço.

CRUD: messages (`get/list/edit/delete/bulk/react/unreact/pin/unpin/typing/crosspost/replyTo/forward/suppress/sendRich/polls/endPoll/voters`), channels (`get/create/edit/delete/list/invites/threads`), guilds (`get/list/edit/leave/audit/onboarding/templates/vanity/widget/prune`), members (`get/list/editNick/editRoles/timeout/voice/addRole/removeRole/kick/ban/unban/getBan/search/bulkBan/fetchMe`), roles (`list/create/edit/delete/positions`), users (`fetch/DM`), app commands (`list/get/edit/delete/permissions`), webhooks (CRUD + execute), emoji/sticker/soundboard/scheduled/automod/stage (CRUD). Coletores: `InteractionCollector` ligado no dispatch + polling (`awaitMessage`, `awaitUserReaction`).

Regra de memória (importante): slices passados inline como `&.{x}` com valores runtime morrem antes do uso em cadeias fundas — os Handles (`reply/editReply/followUp`) copiam embeds/components/attachments na entrada, mas no `Rest` direto amarre arrays em locais (`const arr = [_]T{...};`).

Gaps conhecidos: sem sharding/OAuth2; voz tem codecs+RTP+nacl mas sem join de rede (experimental); sem partials por decisão; handlers rodam no loop do gateway — responda o ack em <3s e faça o resto depois.

## Embeds

```zig
var b = discord.embed.Builder.init(gpa);
defer b.deinit();

try b.setTitle("Novidades");
try b.setDescription("corpo");
try b.setColor(0x5865F2);
try b.addField("Regra 1", "Seja legal", true);

const e = try b.build();
```

`build()` valida os limites do Discord e falha com erro tipado (`TitleTooLong`, `TooManyFields`, `EmbedTooLarge`...): título ≤256, descrição ≤4096, até 25 fields, total ≤6000. Métodos espelham o `EmbedBuilder` (`setUrl/setAuthor/setFooter/setImage/setThumbnail/setTimestamp/setFields`). O resultado pega memória da arena do builder, então use antes do `deinit`.

## Intents e Snowflakes

```zig
const discord = @import("discord-zig");
const GatewayIntentBits = discord.GatewayIntentBits;

// estilo discord.js PascalCase com autocomplete
var client = discord.client.Client.init(gpa, io, .{
    .intents = .{
        GatewayIntentBits.Guilds,
        GatewayIntentBits.GuildMembers,
        GatewayIntentBits.GuildMessages,
        GatewayIntentBits.MessageContent,
        GatewayIntentBits.GuildVoiceStates,
        GatewayIntentBits.GuildMessageReactions,
        GatewayIntentBits.GuildInvites,
    },
});

// helper direto via intents:
const a = discord.intents.of(.{ GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages });

const id = try discord.snowflake.Snowflake.parse("175928847299117063");
std.debug.print("criado em (ms): {d}\n", .{id.timestampMs()});
```

`message_content`, `guild_members` e `guild_presences` são intents privilegiadas: ative no portal do desenvolvedor (aplicação → Bot → Privileged Gateway Intents) e use `discord.intents.requiresApproval` para checar. Sem a `message_content`, o Discord envia `msg.content`, embeds e anexos **vazios** — se o conteúdo chega vazio, é quase sempre isso. Sem a flag correspondente no portal, o gateway derruba a conexão com close `4014`.

## MessageFlags

```zig
const message = @import("discord-zig").message;
const MessageFlags = @import("discord-zig").MessageFlags; // também re-exportado no topo

// estilo discord.js: .{} no lugar de [...] — só com MessageFlags/Bits/u32
const flags = message.of(.{ MessageFlags.Ephemeral, MessageFlags.SuppressNotifications });

// ou com estado, parecido com BitField:
var f = message.Flags.init(.{MessageFlags.Ephemeral});
f.add(.{MessageFlags.SuppressEmbeds});
f.remove(.{MessageFlags.Ephemeral});
if (f.has(MessageFlags.SuppressEmbeds)) { ... }

// lendo mensagem recebida (msg.flags vem do Discord, padrão 0):
if (message.has(msg.flags, message.ephemeral)) { ... }
```

Literais crus (`.{.ephemeral}`) não compilam de propósito — o erro diz para usar `MessageFlags.*`.

## Permissions

```zig
const permission = @import("discord-zig").permission;

// estilo discord.js (u64 — permissões passam de 32 bits):
const bits = permission.of(.{ .kick_members, permission.PermissionFlagsBits.BanMembers });
if (permission.has(bits, .administrator)) { ... }

// resolvendo o bitfield efetivo do membro (dono e Administrator viram all()):
const effective = permission.resolveMember(&roles, member, guild_owner_id);

// overwrites de channel na ordem deny-depois-allow da doc oficial:
bits = permission.applyOverwrite(bits, allow, deny);
```

`Role.permissions` vem da API como string decimal — `permission.parse` converte (`0` se inválida).

Overwrites de channel (`channel.permissionOverwrites` do discord.js):

```zig
const PermissionOverwrite = discord.PermissionOverwrite;
const PermissionsBitField = discord.PermissionsBitField;

// 1. Estilo idêntico ao discord.js passando array de PermissionOverwrite:
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

// 2. Remover overwrite de um alvo (channel.permissionOverwrites.delete):
try channel.permissionOverwrites.delete(user.id, null);

// 3. Obter retorno Parsed(Channel) e passar razão de auditoria (via .set):
var updated = try channel.permissionOverwrites.set(&.{
    .{
        .id = guild.id,
        .deny = PermissionsBitField.Flags.ViewChannel,
    },
    .{
        .id = user.id,
        .kind = .member,
        .allow = PermissionsBitField.Flags.ViewChannel,
    },
}, "privando canal");
defer updated.deinit();

// 4. Editar opções de um alvo individual:
try channel.permissionOverwrites.editOptions(guild.id, .{
    .deny = PermissionsBitField.Flags.ViewChannel,
}, null);

// 5. Lendo e resolvendo bitfield efetivo na ordem oficial do Discord:
const in_channel = permission.resolveChannelPermissions(base, user_id, role_ids, guild.id, channel.permission_overwrites);
```

### Criação de canais (`guild.channels.create` no estilo Discord.js)

Suporte completo a [`ChannelType`](https://discord.js.org/docs/packages/discord.js/14.22.1/ChannelType:Enum) idêntico ao discord.js (`ChannelType.GuildVoice`, `ChannelType.GuildText`, etc.):

```zig
const ChannelType = discord.ChannelType;
const PermissionOverwrite = discord.PermissionOverwrite;
const PermissionsBitField = discord.PermissionsBitField;

var created = try guild.channels.create(.{
    .name = "Sala de Voz",
    .@"type" = ChannelType.GuildVoice,
    .permissionOverwrites = &[_]PermissionOverwrite{
        .{
            .id = guild.id,
            .deny = &[_]u64{ PermissionsBitField.Flags.ViewChannel },
        },
        .{
            .id = user.id,
            .allow = &[_]u64{ PermissionsBitField.Flags.ViewChannel },
        },
    },
});
defer created.deinit();
```

## Cache

Equivalente ao `makeCache: Options.cacheWithLimits(...)` da discord.js: cada evento do Gateway já alimenta o cache sozinho, com limite por recurso. `null` é ilimitado. Stores: guilds, channels, messages, members, users, roles, threads, emojis.

```zig
const cacheWithLimits = discord.cacheWithLimits;

var client = discord.Client.init(gpa, io, .{
    .intents = .{ GatewayIntentBits.Guilds, GatewayIntentBits.GuildMessages },
    .cache = cacheWithLimits(.{
        .GuildMemberManager = 12000,
        .MessageManager = 50,
    }),
});
```

```zig
// leitura: ponteiro emprestado, válido até evicção/remoção/sweep/clear
if (client.cache.messages.get(123)) |msg| {
    std.debug.print("{s}\n", .{msg.content});
}
if (client.cache.members.get(discord.cache.memberKey(guild_id, user_id))) |m| {
    std.debug.print("{?s}\n", .{m.nick});
}
```

| discord.js | aqui | padrão |
|---|---|---|
| `GuildManager` | `cache.guilds` | ilimitado |
| `ChannelManager` | `cache.channels` | ilimitado |
| `MessageManager` | `cache.messages` | 200 |
| `GuildMemberManager` | `cache.members` | ilimitado |
| `UserManager` | `cache.users` | ilimitado |

Troque limites em tempo de execução com `client.cache.setLimits(.{...})` (o excedente é evictado na hora, do mais antigo) e veja `client.cache.counts()`.

Sem threads escondidas: o sweep é explícito, chame no seu próprio timer. Por idade (via timestamp do Snowflake):

```zig
_ = client.cache.sweepMessagesOlderThan(now_ms, 3600_000);
```

Ou por predicado em qualquer store:

```zig
const keep_bots = struct {
    fn f(_: void, msg: *const discord.schema.Message) bool {
        return msg.author.bot;
    }
}.f;
_ = client.cache.messages.sweep({}, keep_bots);
```

## Estrutura

```
src/
  mod.zig         // raiz da lib, reexporta tudo + version
  main.zig        // exemplo: bot com DISCORD_TOKEN via Client/login/on/run
  client.zig      // Client fachada (login/on/once/off/emit) + Rest (https://discord.com/api/v10)
  cache.zig       // Cache com limites por recurso (guilds/channels/messages/members/users) + sweep
  embed.zig       // EmbedBuilder: setters encadeáveis + validação de limites do Discord
  slash.zig       // SlashCommandBuilder: comandos, opções, choices + respostas de interação
  fetch.zig       // abstração HTTP genérica reusável (método, url, headers, body)
  session.zig     // estado de conexão interno: Identify/Resume + Monitor de heartbeat
  heartbeat.zig   // máquina de estado do heartbeat (agenda, ack, timeout), sem socket
  gateway.zig     // opcodes 0-11, encode/decode Hello/Ready/Heartbeat
  events.zig      // Type, nomes estilo discord.js, Payload por evento
  websockets.zig  // cliente WebSocket wss só com std (handshake, frames, ping/pong)
  schema.zig      // structs da API (User, Guild, Channel, Message, Emoji, Reaction...)
  snowflake.zig   // parse Snowflake string<->u64 + timestamp/worker/processo
  intents.zig     // bitflags 1<<0..1<<25
  message.zig     // MessageFlags estilo discord.js (Ephemeral, SuppressEmbeds...)
  util.zig        // helpers genéricos (relógio, backoff, headers)
tests/
  mod.zig         // agrega *_tests.zig
```

## Testes

```sh
zig build test
```

## Licença

MIT License

Copyright (c) 2026 discord-zig contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
