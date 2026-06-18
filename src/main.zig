const std = @import("std");
const Io = std.Io;
const zio = @import("zio");

pub const std_options_debug_io = zio.debug_io;

const pgwire = @import("pgwire");

pub fn main(init: std.process.Init) !void {
    const arena: std.mem.Allocator = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);
    for (args) |arg| {
        std.log.info("arg: {s}", .{arg});
    }

    var rt = try zio.Runtime.init(std.heap.page_allocator, .{});
    defer rt.deinit();
    const io = rt.io();

    const addr = try Io.net.IpAddress.parseIp4("0.0.0.0", 6432);

    var server = try addr.listen(io, .{});
    defer server.deinit(io);

    var group: Io.Group = .init;
    defer group.cancel(io);

    std.log.info("listening on 0.0.0.0:6432", .{});

    while (true) {
        const stream = try server.accept(io);
        errdefer stream.close(io);

        try group.concurrent(io, handleClient, .{ io, stream });
    }
}

fn handleClient(io: Io, stream: Io.net.Stream) Io.Cancelable!void {
    defer stream.close(io);
    std.log.info("accepted new connection from {}", .{stream.socket.address.getPort()});

    var read_buffer: [8192]u8 = undefined;
    var reader = stream.reader(io, &read_buffer);

    var write_buffer: [8192]u8 = undefined;
    var writer = stream.writer(io, &write_buffer);

    var conn = pgwire.Connection.init(&reader, &writer, std.heap.page_allocator);
    defer conn.deinit();

    // ─── Startup ───────────────────────────────────────────────────

    while (true) {
        const startup = conn.readStartupMessage() orelse return;

        if (startup.version == pgwire.types.SSL_REQUEST_CODE) {
            std.log.info("SSLRequest received, declining", .{});
            conn.declineSSL();
            continue;
        }

        if (startup.version == pgwire.types.CANCEL_REQUEST_CODE) {
            std.log.info("CancelRequest received, closing", .{});
            return;
        }

        logStartupMessage(startup.version, startup.params);
        conn.sendAuthOk();
        conn.sendParameterStatus("server_version", "0.0.0");
        conn.sendParameterStatus("server_encoding", "UTF8");
        conn.sendParameterStatus("client_encoding", "UTF8");
        conn.sendParameterStatus("datestyle", "ISO");
        conn.sendBackendKeyData(1, 12345);
        conn.sendReadyForQuery();
        conn.flush();
        break;
    }

    // ─── Message loop ──────────────────────────────────────────────

    while (conn.nextMessage()) |message| {
        switch (message.type) {
            pgwire.types.MessageType.query => {
                const query = pgwire.Connection.readQuery(message);
                std.log.info("query: {s}", .{query});
                handleQuery(&conn, query);
            },
            pgwire.types.MessageType.terminate => {
                std.log.info("client terminated", .{});
                return;
            },
            pgwire.types.MessageType.sync => {
                conn.sendReadyForQuery();
            },
            pgwire.types.MessageType.flush => {
                conn.flush();
            },
            else => {},
        }

        conn.resetArena();
    }

    std.log.info("client disconnected", .{});
}

fn handleQuery(conn: *pgwire.Connection, query: []const u8) void {
    const first = if (query.len > 0) std.ascii.toLower(query[0]) else 0;

    if (first == 's') {
        const columns = [_]pgwire.types.ColumnDesc{
            .{ .name = "id", .type_oid = 23, .type_len = 4 },
            .{ .name = "name", .type_oid = 25, .type_len = -1 },
        };

        const row1 = [_]?[]const u8{ "1", "alice" };
        const row2 = [_]?[]const u8{ "2", "bob" };

        conn.sendRowDescription(&columns);
        conn.sendDataRow(&row1);
        conn.sendDataRow(&row2);
        conn.sendCommandComplete("SELECT 2");
    } else if (first == 'i' or first == 'u' or first == 'd') {
        conn.sendCommandComplete("INSERT 0 1");
    } else if (first == 'c') {
        conn.sendCommandComplete("CREATE TABLE");
    } else {
        conn.sendCommandComplete("INSERT 0 1");
    }

    conn.sendReadyForQuery();
    conn.flush();
}

fn logStartupMessage(version: i32, params: []const u8) void {
    std.log.info("protocol version: {d}.{d}", .{ @divTrunc(version, 65536), @rem(version, 65536) });
    var pos: usize = 0;
    while (pos < params.len and params[pos] != 0) {
        const key_start = pos;
        while (pos < params.len and params[pos] != 0) : (pos += 1) {}
        const key = params[key_start..pos];
        pos += 1;
        const val_start = pos;
        while (pos < params.len and params[pos] != 0) : (pos += 1) {}
        const val = params[val_start..pos];
        std.log.info("  {s}: {s}", .{ key, val });
    }
}
