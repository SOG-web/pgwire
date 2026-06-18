const std = @import("std");
const Io = std.Io;
const types = @import("../types.zig");

// ─── Read ──────────────────────────────────────────────────────────

pub fn readStartupMessage(reader: *Io.Reader, alloc: std.mem.Allocator) ?types.StartupMessage {
    var len_buf: [4]u8 = undefined;
    reader.readSliceAll(&len_buf) catch return null;
    const length = std.mem.readInt(i32, &len_buf, .big);

    if (length < 8) return null;
    const remaining: usize = @intCast(length - 4);
    const buf = alloc.alloc(u8, remaining) catch return null;
    reader.readSliceAll(buf) catch return null;

    const version = std.mem.readInt(i32, buf[0..4], .big);
    return .{ .version = version, .params = buf[4..remaining] };
}

pub fn readMessage(reader: *Io.Reader, alloc: std.mem.Allocator) ?types.Message {
    var type_buf: [1]u8 = undefined;
    reader.readSliceAll(&type_buf) catch return null;

    var len_buf: [4]u8 = undefined;
    reader.readSliceAll(&len_buf) catch return null;
    const length = std.mem.readInt(i32, &len_buf, .big);

    if (length < 4) return null;
    const remaining: usize = @intCast(length - 4);
    const buf = alloc.alloc(u8, remaining) catch return null;
    reader.readSliceAll(buf) catch return null;

    return .{ .type = type_buf[0], .payload = buf };
}

pub fn readQuery(msg: types.Message) []const u8 {
    return if (std.mem.indexOfScalar(u8, msg.payload, 0)) |pos|
        msg.payload[0..pos]
    else
        msg.payload;
}

pub fn readCString(payload: []const u8, offset: usize) struct { value: []const u8, end: usize } {
    const start = offset;
    var end = start;
    while (end < payload.len and payload[end] != 0) : (end += 1) {}
    return .{ .value = payload[start..end], .end = end + 1 };
}

pub fn readInt16(payload: []const u8, offset: usize) i16 {
    return std.mem.readInt(i16, payload[offset .. offset + 2], .big);
}

pub fn readInt32(payload: []const u8, offset: usize) i32 {
    return std.mem.readInt(i32, payload[offset .. offset + 4], .big);
}

// ─── Write primitives ──────────────────────────────────────────────

pub fn writeInt32(writer: *Io.Writer, value: i32) void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, value, .big);
    writer.writeAll(&buf) catch return;
}

pub fn writeInt16(writer: *Io.Writer, value: i16) void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(i16, &buf, value, .big);
    writer.writeAll(&buf) catch return;
}

pub fn writeByte(writer: *Io.Writer, byte: u8) void {
    writer.writeAll(&.{byte}) catch return;
}

pub fn writeBytes(writer: *Io.Writer, bytes: []const u8) void {
    writer.writeAll(bytes) catch return;
}

pub fn writeNull(writer: *Io.Writer) void {
    writer.writeAll(&.{0}) catch return;
}

pub fn writeCString(writer: *Io.Writer, s: []const u8) void {
    writeBytes(writer, s);
    writeNull(writer);
}

// ─── Authentication ────────────────────────────────────────────────

pub fn sendAuthOk(writer: *Io.Writer) void {
    writeByte(writer, types.MessageType.authentication);
    writeInt32(writer, 8);
    writeInt32(writer, 0);
}

pub fn sendAuthMD5Password(writer: *Io.Writer, salt: [4]u8) void {
    writeByte(writer, types.MessageType.authentication);
    writeInt32(writer, 12); // 4(self) + 4(auth_type) + 4(salt)
    writeInt32(writer, types.AuthMethod.md5_password);
    writeBytes(writer, &salt);
}

pub fn sendAuthSASL(writer: *Io.Writer, mechanisms: []const []const u8) void {
    var payload_size: i32 = 4; // auth type
    for (mechanisms) |m| {
        payload_size += @intCast(m.len + 1); // mechanism + null
    }
    payload_size += 1; // final null terminator

    writeByte(writer, types.MessageType.authentication);
    writeInt32(writer, 4 + payload_size);
    writeInt32(writer, types.AuthMethod.sasl);
    for (mechanisms) |m| {
        writeCString(writer, m);
    }
    writeNull(writer); // list terminator
}

pub fn sendAuthSASLContinue(writer: *Io.Writer, server_data: []const u8) void {
    writeByte(writer, types.MessageType.authentication);
    writeInt32(writer, @intCast(4 + 4 + server_data.len));
    writeInt32(writer, types.AuthMethod.sasl_continue);
    writeBytes(writer, server_data);
}

pub fn sendAuthSASLFinal(writer: *Io.Writer, server_data: []const u8) void {
    writeByte(writer, types.MessageType.authentication);
    writeInt32(writer, @intCast(4 + 4 + server_data.len));
    writeInt32(writer, types.AuthMethod.sasl_final);
    writeBytes(writer, server_data);
}

// ─── Connection ────────────────────────────────────────────────────

pub fn sendParameterStatus(writer: *Io.Writer, name: []const u8, value: []const u8) void {
    const len: i32 = @intCast(4 + name.len + 1 + value.len + 1);
    writeByte(writer, types.MessageType.parameter_status);
    writeInt32(writer, len);
    writeCString(writer, name);
    writeCString(writer, value);
}

pub fn sendBackendKeyData(writer: *Io.Writer, process_id: i32, secret_key: i32) void {
    writeByte(writer, types.MessageType.backend_key_data);
    writeInt32(writer, 12);
    writeInt32(writer, process_id);
    writeInt32(writer, secret_key);
}

pub fn sendReadyForQuery(writer: *Io.Writer, status: types.TransactionStatus) void {
    writeByte(writer, types.MessageType.ready_for_query);
    writeInt32(writer, 5);
    writeByte(writer, status.toChar());
}

// ─── Query results ─────────────────────────────────────────────────

pub fn sendRowDescription(writer: *Io.Writer, columns: []const types.ColumnDesc) void {
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

    writeByte(writer, types.MessageType.row_description);
    writeInt32(writer, 4 + payload_size);
    writeInt16(writer, @intCast(columns.len));

    for (columns) |col| {
        writeCString(writer, col.name);
        writeInt32(writer, 0); // table_oid
        writeInt16(writer, 0); // column_attr
        writeInt32(writer, col.type_oid);
        writeInt16(writer, col.type_len);
        writeInt32(writer, -1); // type_mod
        writeInt16(writer, 0); // format = text
    }
}

pub fn sendDataRow(writer: *Io.Writer, values: []const ?[]const u8) void {
    var payload_size: i32 = 2; // col_count (int16)
    for (values) |val| {
        if (val) |v| {
            payload_size += 4 + @as(i32, @intCast(v.len));
        } else {
            payload_size += 4; // -1 for null
        }
    }

    writeByte(writer, types.MessageType.data_row);
    writeInt32(writer, 4 + payload_size);
    writeInt16(writer, @intCast(values.len));

    for (values) |val| {
        if (val) |v| {
            writeInt32(writer, @intCast(v.len));
            writeBytes(writer, v);
        } else {
            writeInt32(writer, -1);
        }
    }
}

pub fn sendCommandComplete(writer: *Io.Writer, tag: []const u8) void {
    const len: i32 = @intCast(4 + tag.len + 1);
    writeByte(writer, types.MessageType.command_complete);
    writeInt32(writer, len);
    writeCString(writer, tag);
}

pub fn sendEmptyQueryResponse(writer: *Io.Writer) void {
    writeByte(writer, types.MessageType.empty_query_response);
    writeInt32(writer, 4);
}

// ─── Errors and notices ────────────────────────────────────────────

pub const ErrorFields = struct {
    severity: []const u8 = "ERROR",
    sqlstate: []const u8 = "XX000",
    message: []const u8 = "",
    detail: ?[]const u8 = null,
    hint: ?[]const u8 = null,
    position: ?i32 = null,
};

pub fn sendErrorResponse(writer: *Io.Writer, fields: ErrorFields) void {
    var payload_size: i32 = 0;
    // S (severity)
    payload_size += 1 + @as(i32, @intCast(fields.severity.len)) + 1;
    // C (sqlstate)
    payload_size += 1 + @as(i32, @intCast(fields.sqlstate.len)) + 1;
    // M (message)
    payload_size += 1 + @as(i32, @intCast(fields.message.len)) + 1;
    // D (detail)
    if (fields.detail) |d| {
        payload_size += 1 + @as(i32, @intCast(d.len)) + 1;
    }
    // H (hint)
    if (fields.hint) |h| {
        payload_size += 1 + @as(i32, @intCast(h.len)) + 1;
    }
    // P (position)
    if (fields.position) |p| {
        const pos_str = std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{p}) catch "";
        payload_size += 1 + @as(i32, @intCast(pos_str.len)) + 1;
    }
    // terminator
    payload_size += 1;

    writeByte(writer, types.MessageType.error_response);
    writeInt32(writer, 4 + payload_size);
    writeErrorField(writer, 'S', fields.severity);
    writeErrorField(writer, 'C', fields.sqlstate);
    writeErrorField(writer, 'M', fields.message);
    if (fields.detail) |d| writeErrorField(writer, 'D', d);
    if (fields.hint) |h| writeErrorField(writer, 'H', h);
    if (fields.position) |p| {
        const pos_str = std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{p}) catch "";
        writeErrorField(writer, 'P', pos_str);
    }
    writeNull(writer); // terminator
}

pub fn sendErrorResponseSimple(writer: *Io.Writer, sqlstate: []const u8, message: []const u8) void {
    sendErrorResponse(writer, .{ .sqlstate = sqlstate, .message = message });
}

fn writeErrorField(writer: *Io.Writer, field_type: u8, value: []const u8) void {
    writeByte(writer, field_type);
    writeCString(writer, value);
}

pub fn sendNoticeResponse(writer: *Io.Writer, fields: ErrorFields) void {
    var payload_size: i32 = 0;
    payload_size += 1 + @as(i32, @intCast(fields.severity.len)) + 1;
    payload_size += 1 + @as(i32, @intCast(fields.message.len)) + 1;
    payload_size += 1; // terminator

    writeByte(writer, types.MessageType.notice_response);
    writeInt32(writer, 4 + payload_size);
    writeErrorField(writer, 'S', fields.severity);
    writeErrorField(writer, 'M', fields.message);
    writeNull(writer);
}

// ─── Extended Query Protocol ───────────────────────────────────────

pub fn sendParseComplete(writer: *Io.Writer) void {
    writeByte(writer, types.MessageType.parse_complete);
    writeInt32(writer, 4);
}

pub fn sendBindComplete(writer: *Io.Writer) void {
    writeByte(writer, types.MessageType.bind_complete);
    writeInt32(writer, 4);
}

pub fn sendCloseComplete(writer: *Io.Writer) void {
    writeByte(writer, types.MessageType.close_complete);
    writeInt32(writer, 4);
}

pub fn sendParameterDescription(writer: *Io.Writer, param_types: []const i32) void {
    var payload_size: i32 = 2; // count (int16)
    payload_size += @as(i32, @intCast(param_types.len)) * 4;

    writeByte(writer, types.MessageType.parameter_description);
    writeInt32(writer, 4 + payload_size);
    writeInt16(writer, @intCast(param_types.len));
    for (param_types) |oid| {
        writeInt32(writer, oid);
    }
}

pub fn sendNoData(writer: *Io.Writer) void {
    writeByte(writer, types.MessageType.no_data);
    writeInt32(writer, 4);
}

pub fn sendPortalSuspended(writer: *Io.Writer) void {
    writeByte(writer, types.MessageType.portal_suspended);
    writeInt32(writer, 4);
}

// ─── SSL ───────────────────────────────────────────────────────────

pub fn declineSSL(writer: *Io.Writer) void {
    writeByte(writer, 'N');
}

pub fn acceptSSL(writer: *Io.Writer) void {
    writeByte(writer, 'S');
}

// ─── COPY protocol ─────────────────────────────────────────────────

pub fn sendCopyInResponse(writer: *Io.Writer, format: i16, column_formats: []const i16) void {
    var payload_size: i32 = 3; // overall_format(1) + col_count(2)
    payload_size += @as(i32, @intCast(column_formats.len)) * 2;

    writeByte(writer, types.MessageType.copy_in_response);
    writeInt32(writer, 4 + payload_size);
    writeInt16(writer, format);
    writeInt16(writer, @intCast(column_formats.len));
    for (column_formats) |f| {
        writeInt16(writer, f);
    }
}

pub fn sendCopyOutResponse(writer: *Io.Writer, format: i16, column_formats: []const i16) void {
    var payload_size: i32 = 3;
    payload_size += @as(i32, @intCast(column_formats.len)) * 2;

    writeByte(writer, types.MessageType.copy_out_response);
    writeInt32(writer, 4 + payload_size);
    writeInt16(writer, format);
    writeInt16(writer, @intCast(column_formats.len));
    for (column_formats) |f| {
        writeInt16(writer, f);
    }
}

pub fn sendCopyData(writer: *Io.Writer, data: []const u8) void {
    writeByte(writer, types.MessageType.copy_data);
    writeInt32(writer, @intCast(4 + data.len));
    writeBytes(writer, data);
}

pub fn sendCopyDone(writer: *Io.Writer) void {
    writeByte(writer, types.MessageType.copy_done);
    writeInt32(writer, 4);
}

pub fn sendCopyFail(writer: *Io.Writer, message: []const u8) void {
    writeByte(writer, types.MessageType.copy_fail);
    writeInt32(writer, @intCast(4 + message.len + 1));
    writeCString(writer, message);
}
