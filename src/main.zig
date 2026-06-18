const std = @import("std");
const Io = std.Io;
const zio = @import("zio");

pub const std_options_debug_io = zio.debug_io;

const pgwire = @import("pgwire");
const msg = pgwire.server.message;
const types = pgwire.types;
const ConnectionState = pgwire.server.connection.ConnectionState;

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

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var conn_state = ConnectionState{};
    conn_state.backend_pid = @intCast(std.os.linux.getpid());
    conn_state.backend_secret = 12345;

    // ─── Startup ───────────────────────────────────────────────────

    while (true) {
        const startup = msg.readStartupMessage(&reader.interface, alloc) orelse return;

        if (startup.version == types.SSL_REQUEST_CODE) {
            std.log.info("SSLRequest received, declining", .{});
            msg.declineSSL(&writer.interface);
            writer.interface.flush() catch return;
            continue;
        }

        if (startup.version == types.CANCEL_REQUEST_CODE) {
            std.log.info("CancelRequest received, closing", .{});
            return;
        }

        // Parse startup parameters
        var pos: usize = 0;
        while (pos < startup.params.len) {
            const key_end = std.mem.indexOfScalar(u8, startup.params[pos..], 0) orelse break;
            const key = startup.params[pos .. pos + key_end];
            pos += key_end + 1;
            const val_end = std.mem.indexOfScalar(u8, startup.params[pos..], 0) orelse break;
            const val = startup.params[pos .. pos + val_end];
            pos += val_end + 1;
            conn_state.setParameter(key, val);
        }

        std.log.info("user: {s}, database: {s}", .{ conn_state.getCurrentUser(), conn_state.getCurrentDatabase() });
        conn_state.authenticate(types.PROTOCOL_VERSION_3_0);

        msg.sendAuthOk(&writer.interface);
        msg.sendParameterStatus(&writer.interface, "server_version", "0.0.0");
        msg.sendParameterStatus(&writer.interface, "server_encoding", "UTF8");
        msg.sendParameterStatus(&writer.interface, "client_encoding", "UTF8");
        msg.sendParameterStatus(&writer.interface, "datestyle", "ISO");
        msg.sendBackendKeyData(&writer.interface, conn_state.backend_pid, conn_state.backend_secret);
        msg.sendReadyForQuery(&writer.interface, conn_state.transaction_status);
        writer.interface.flush() catch return;
        break;
    }

    // ─── Message loop ──────────────────────────────────────────────

    while (true) {
        const message = msg.readMessage(&reader.interface, alloc) orelse break;

        switch (message.type) {
            types.MessageType.query => {
                const query = msg.readQuery(message);
                std.log.info("query: {s}", .{query});
                conn_state.incrementQueryCount();
                conn_state.detectTransactionCommand(query);
                handleQuery(&writer.interface, &conn_state, query);
            },
            types.MessageType.terminate => {
                std.log.info("client terminated", .{});
                return;
            },
            types.MessageType.sync => {
                msg.sendReadyForQuery(&writer.interface, conn_state.transaction_status);
            },
            types.MessageType.flush => {
                writer.interface.flush() catch return;
            },
            else => {},
        }

        arena.deinit();
        arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    }

    std.log.info("client disconnected", .{});
}

fn handleQuery(writer: *Io.Writer, conn_state: *ConnectionState, query: []const u8) void {
    const first = if (query.len > 0) std.ascii.toLower(query[0]) else 0;

    if (first == 's') {
        const columns = [_]types.ColumnDesc{
            .{ .name = "id", .type_oid = 23, .type_len = 4 },
            .{ .name = "name", .type_oid = 25, .type_len = -1 },
        };

        const row1 = [_]?[]const u8{ "1", "alice" };
        const row2 = [_]?[]const u8{ "2", "bob" };

        msg.sendRowDescription(writer, &columns);
        msg.sendDataRow(writer, &row1);
        msg.sendDataRow(writer, &row2);
        msg.sendCommandComplete(writer, "SELECT 2");
    } else if (first == 'i' or first == 'u' or first == 'd') {
        msg.sendCommandComplete(writer, "INSERT 0 1");
    } else if (first == 'c') {
        msg.sendCommandComplete(writer, "CREATE TABLE");
    } else {
        msg.sendCommandComplete(writer, "INSERT 0 1");
    }

    msg.sendReadyForQuery(writer, conn_state.transaction_status);
    writer.flush() catch return;
}
