const std = @import("std");
const Io = std.Io;

pub const types = @import("types.zig");

pub const Connection = struct {
    reader: *Io.net.Stream.Reader,
    writer: *Io.net.Stream.Writer,
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,

    pub fn init(
        reader: *Io.net.Stream.Reader,
        writer: *Io.net.Stream.Writer,
        allocator: std.mem.Allocator,
    ) Connection {
        return .{
            .reader = reader,
            .writer = writer,
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
        };
    }

    pub fn deinit(self: *Connection) void {
        self.arena.deinit();
    }

    pub fn resetArena(self: *Connection) void {
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.allocator);
    }

    pub fn arenaAllocator(self: *Connection) std.mem.Allocator {
        return self.arena.allocator();
    }

    // ─── Read ──────────────────────────────────────────────────────

    pub fn readStartupMessage(self: *Connection) ?types.StartupMessage {
        const alloc = self.arenaAllocator();

        var len_buf: [4]u8 = undefined;
        self.reader.interface.readSliceAll(&len_buf) catch return null;
        const length = std.mem.readInt(i32, &len_buf, .big);

        if (length < 8) return null;
        const remaining: usize = @intCast(length - 4);
        const buf = alloc.alloc(u8, remaining) catch return null;
        self.reader.interface.readSliceAll(buf) catch return null;

        const version = std.mem.readInt(i32, buf[0..4], .big);
        return .{ .version = version, .params = buf[4..remaining] };
    }

    pub fn nextMessage(self: *Connection) ?types.Message {
        const alloc = self.arenaAllocator();

        var type_buf: [1]u8 = undefined;
        self.reader.interface.readSliceAll(&type_buf) catch return null;

        var len_buf: [4]u8 = undefined;
        self.reader.interface.readSliceAll(&len_buf) catch return null;
        const length = std.mem.readInt(i32, &len_buf, .big);

        if (length < 4) return null;
        const remaining: usize = @intCast(length - 4);
        const buf = alloc.alloc(u8, remaining) catch return null;
        self.reader.interface.readSliceAll(buf) catch return null;

        return .{ .type = type_buf[0], .payload = buf };
    }

    pub fn readQuery(msg: types.Message) []const u8 {
        return if (std.mem.indexOfScalar(u8, msg.payload, 0)) |pos|
            msg.payload[0..pos]
        else
            msg.payload;
    }

    // ─── Write helpers ─────────────────────────────────────────────

    fn writeInt32(self: *Connection, value: i32) void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(i32, &buf, value, .big);
        self.writer.interface.writeAll(&buf) catch return;
    }

    fn writeInt16(self: *Connection, value: i16) void {
        var buf: [2]u8 = undefined;
        std.mem.writeInt(i16, &buf, value, .big);
        self.writer.interface.writeAll(&buf) catch return;
    }

    fn writeByte(self: *Connection, byte: u8) void {
        self.writer.interface.writeAll(&.{byte}) catch return;
    }

    fn writeBytes(self: *Connection, bytes: []const u8) void {
        self.writer.interface.writeAll(bytes) catch return;
    }

    fn writeNull(self: *Connection) void {
        self.writer.interface.writeAll(&.{0}) catch return;
    }

    pub fn flush(self: *Connection) void {
        self.writer.interface.flush() catch return;
    }

    // ─── Send messages ─────────────────────────────────────────────

    pub fn sendAuthOk(self: *Connection) void {
        self.writeByte(types.MessageType.authentication);
        self.writeInt32(8); // length: 4 (self) + 4 (auth type)
        self.writeInt32(0); // auth type: OK
    }

    pub fn sendParameterStatus(self: *Connection, name: []const u8, value: []const u8) void {
        const len: i32 = @intCast(4 + name.len + 1 + value.len + 1);
        self.writeByte(types.MessageType.parameter_status);
        self.writeInt32(len);
        self.writeBytes(name);
        self.writeNull();
        self.writeBytes(value);
        self.writeNull();
    }

    pub fn sendBackendKeyData(self: *Connection, process_id: i32, secret_key: i32) void {
        self.writeByte(types.MessageType.backend_key_data);
        self.writeInt32(12); // length: 4 (self) + 4 (pid) + 4 (key)
        self.writeInt32(process_id);
        self.writeInt32(secret_key);
    }

    pub fn sendReadyForQuery(self: *Connection) void {
        self.writeByte(types.MessageType.ready_for_query);
        self.writeInt32(5); // length: 4 (self) + 1 (status)
        self.writeByte(types.TransactionStatus.idle);
    }

    pub fn sendRowDescription(self: *Connection, columns: []const types.ColumnDesc) void {
        var payload_size: i32 = 2; // field_count (int16)
        for (columns) |col| {
            payload_size += @intCast(col.name.len + 1); // name + null
            payload_size += 4; // table_oid
            payload_size += 2; // column_attr
            payload_size += 4; // type_oid
            payload_size += 2; // type_len
            payload_size += 4; // type_mod
            payload_size += 2; // format
        }

        self.writeByte(types.MessageType.row_description);
        self.writeInt32(4 + payload_size);
        self.writeInt16(@intCast(columns.len));

        for (columns) |col| {
            self.writeBytes(col.name);
            self.writeNull();
            self.writeInt32(0); // table_oid
            self.writeInt16(@as(i16, 0)); // column_attr
            self.writeInt32(col.type_oid);
            self.writeInt16(col.type_len);
            self.writeInt32(-1); // type_mod
            self.writeInt16(@as(i16, 0)); // format = text
        }
    }

    pub fn sendDataRow(self: *Connection, values: []const ?[]const u8) void {
        var payload_size: i32 = 2; // col_count (int16)
        for (values) |val| {
            if (val) |v| {
                payload_size += 4 + @as(i32, @intCast(v.len));
            } else {
                payload_size += 4; // -1 for null
            }
        }

        self.writeByte(types.MessageType.data_row);
        self.writeInt32(4 + payload_size);
        self.writeInt16(@intCast(values.len));

        for (values) |val| {
            if (val) |v| {
                self.writeInt32(@intCast(v.len));
                self.writeBytes(v);
            } else {
                self.writeInt32(-1);
            }
        }
    }

    pub fn sendCommandComplete(self: *Connection, tag: []const u8) void {
        const len: i32 = @intCast(4 + tag.len + 1);
        self.writeByte(types.MessageType.command_complete);
        self.writeInt32(len);
        self.writeBytes(tag);
        self.writeNull();
    }

    pub fn sendErrorResponse(self: *Connection, message: []const u8) void {
        // 'S' + severity + null + 'M' + message + null + terminator null
        var payload_size: i32 = 0;
        payload_size += 7; // "ERROR" + null
        payload_size += 1; // 'M' field type
        payload_size += @intCast(message.len + 1); // message + null
        payload_size += 1; // terminator null

        self.writeByte(types.MessageType.error_response);
        self.writeInt32(4 + payload_size);
        self.writeBytes("ERROR");
        self.writeNull();
        self.writeByte('M');
        self.writeBytes(message);
        self.writeNull();
        self.writeNull(); // terminator
    }

    pub fn declineSSL(self: *Connection) void {
        self.writeByte('N');
        self.flush();
    }
};
