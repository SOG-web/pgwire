const std = @import("std");
const Io = std.Io;
const types = @import("../types.zig");

pub const WriteError = error{WriteFailed};

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
    return std.mem.readInt(i16, @ptrCast(payload[offset..].ptr), .big);
}

pub fn readInt32(payload: []const u8, offset: usize) i32 {
    return std.mem.readInt(i32, @ptrCast(payload[offset..].ptr), .big);
}

// ─── Write primitives ──────────────────────────────────────────────

pub fn writeInt32(writer: *Io.Writer, value: i32) WriteError!void {
    var buf: [4]u8 = undefined;
    std.mem.writeInt(i32, &buf, value, .big);
    writer.writeAll(&buf) catch return error.WriteFailed;
}

pub fn writeInt16(writer: *Io.Writer, value: i16) WriteError!void {
    var buf: [2]u8 = undefined;
    std.mem.writeInt(i16, &buf, value, .big);
    writer.writeAll(&buf) catch return error.WriteFailed;
}

pub fn writeByte(writer: *Io.Writer, byte: u8) WriteError!void {
    writer.writeAll(&.{byte}) catch return error.WriteFailed;
}

pub fn writeBytes(writer: *Io.Writer, bytes: []const u8) WriteError!void {
    writer.writeAll(bytes) catch return error.WriteFailed;
}

pub fn writeNull(writer: *Io.Writer) WriteError!void {
    writer.writeAll(&.{0}) catch return error.WriteFailed;
}

pub fn writeCString(writer: *Io.Writer, s: []const u8) WriteError!void {
    try writeBytes(writer, s);
    try writeNull(writer);
}

// ─── Authentication ────────────────────────────────────────────────

pub fn sendAuthOk(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, types.MessageType.authentication);
    try writeInt32(writer, 8);
    try writeInt32(writer, 0);
}

pub fn sendAuthMD5Password(writer: *Io.Writer, salt: [4]u8) WriteError!void {
    try writeByte(writer, types.MessageType.authentication);
    try writeInt32(writer, 12);
    try writeInt32(writer, types.AuthMethod.md5_password);
    try writeBytes(writer, &salt);
}

pub fn sendAuthSASL(writer: *Io.Writer, mechanisms: []const []const u8) WriteError!void {
    var payload_size: i32 = 4;
    for (mechanisms) |m| {
        payload_size += @intCast(m.len + 1);
    }
    payload_size += 1;

    try writeByte(writer, types.MessageType.authentication);
    try writeInt32(writer, 4 + payload_size);
    try writeInt32(writer, types.AuthMethod.sasl);
    for (mechanisms) |m| {
        try writeCString(writer, m);
    }
    try writeNull(writer);
}

pub fn sendAuthSASLContinue(writer: *Io.Writer, server_data: []const u8) WriteError!void {
    try writeByte(writer, types.MessageType.authentication);
    try writeInt32(writer, @intCast(4 + 4 + server_data.len));
    try writeInt32(writer, types.AuthMethod.sasl_continue);
    try writeBytes(writer, server_data);
}

pub fn sendAuthSASLFinal(writer: *Io.Writer, server_data: []const u8) WriteError!void {
    try writeByte(writer, types.MessageType.authentication);
    try writeInt32(writer, @intCast(4 + 4 + server_data.len));
    try writeInt32(writer, types.AuthMethod.sasl_final);
    try writeBytes(writer, server_data);
}

// ─── Connection ────────────────────────────────────────────────────

pub fn sendParameterStatus(writer: *Io.Writer, name: []const u8, value: []const u8) WriteError!void {
    const len: i32 = @intCast(4 + name.len + 1 + value.len + 1);
    try writeByte(writer, types.MessageType.parameter_status);
    try writeInt32(writer, len);
    try writeCString(writer, name);
    try writeCString(writer, value);
}

pub fn sendBackendKeyData(writer: *Io.Writer, process_id: i32, secret_key: i32) WriteError!void {
    try writeByte(writer, types.MessageType.backend_key_data);
    try writeInt32(writer, 12);
    try writeInt32(writer, process_id);
    try writeInt32(writer, secret_key);
}

pub fn sendReadyForQuery(writer: *Io.Writer, status: types.TransactionStatus) WriteError!void {
    try writeByte(writer, types.MessageType.ready_for_query);
    try writeInt32(writer, 5);
    try writeByte(writer, status.toChar());
}

// ─── Query results ─────────────────────────────────────────────────

pub fn sendRowDescription(writer: *Io.Writer, columns: []const types.ColumnDesc) WriteError!void {
    var payload_size: i32 = 2;
    for (columns) |col| {
        payload_size += @intCast(col.name.len + 1);
        payload_size += 4;
        payload_size += 2;
        payload_size += 4;
        payload_size += 2;
        payload_size += 4;
        payload_size += 2;
    }

    try writeByte(writer, types.MessageType.row_description);
    try writeInt32(writer, 4 + payload_size);
    try writeInt16(writer, @intCast(columns.len));

    for (columns) |col| {
        try writeCString(writer, col.name);
        try writeInt32(writer, 0);
        try writeInt16(writer, 0);
        try writeInt32(writer, col.type_oid);
        try writeInt16(writer, col.type_len);
        try writeInt32(writer, -1);
        try writeInt16(writer, 0);
    }
}

pub fn sendDataRow(writer: *Io.Writer, values: []const ?[]const u8) WriteError!void {
    var payload_size: i32 = 2;
    for (values) |val| {
        if (val) |v| {
            payload_size += 4 + @as(i32, @intCast(v.len));
        } else {
            payload_size += 4;
        }
    }

    try writeByte(writer, types.MessageType.data_row);
    try writeInt32(writer, 4 + payload_size);
    try writeInt16(writer, @intCast(values.len));

    for (values) |val| {
        if (val) |v| {
            try writeInt32(writer, @intCast(v.len));
            try writeBytes(writer, v);
        } else {
            try writeInt32(writer, -1);
        }
    }
}

pub fn sendCommandComplete(writer: *Io.Writer, tag: []const u8) WriteError!void {
    const len: i32 = @intCast(4 + tag.len + 1);
    try writeByte(writer, types.MessageType.command_complete);
    try writeInt32(writer, len);
    try writeCString(writer, tag);
}

pub fn sendEmptyQueryResponse(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, types.MessageType.empty_query_response);
    try writeInt32(writer, 4);
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

pub fn sendErrorResponse(writer: *Io.Writer, fields: ErrorFields) WriteError!void {
    var payload_size: i32 = 0;
    payload_size += 1 + @as(i32, @intCast(fields.severity.len)) + 1;
    payload_size += 1 + @as(i32, @intCast(fields.sqlstate.len)) + 1;
    payload_size += 1 + @as(i32, @intCast(fields.message.len)) + 1;
    if (fields.detail) |d| {
        payload_size += 1 + @as(i32, @intCast(d.len)) + 1;
    }
    if (fields.hint) |h| {
        payload_size += 1 + @as(i32, @intCast(h.len)) + 1;
    }
    if (fields.position) |p| {
        const pos_str = std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{p}) catch "";
        payload_size += 1 + @as(i32, @intCast(pos_str.len)) + 1;
    }
    payload_size += 1;

    try writeByte(writer, types.MessageType.error_response);
    try writeInt32(writer, 4 + payload_size);
    try writeErrorField(writer, types.ErrorFieldType.severity, fields.severity);
    try writeErrorField(writer, types.ErrorFieldType.sqlstate, fields.sqlstate);
    try writeErrorField(writer, types.ErrorFieldType.message, fields.message);
    if (fields.detail) |d| try writeErrorField(writer, types.ErrorFieldType.detail, d);
    if (fields.hint) |h| try writeErrorField(writer, types.ErrorFieldType.hint, h);
    if (fields.position) |p| {
        const pos_str = std.fmt.allocPrint(std.heap.page_allocator, "{d}", .{p}) catch "";
        try writeErrorField(writer, types.ErrorFieldType.position, pos_str);
    }
    try writeNull(writer);
}

pub fn sendErrorResponseSimple(writer: *Io.Writer, sqlstate: []const u8, message: []const u8) WriteError!void {
    try sendErrorResponse(writer, .{ .sqlstate = sqlstate, .message = message });
}

fn writeErrorField(writer: *Io.Writer, field_type: u8, value: []const u8) WriteError!void {
    try writeByte(writer, field_type);
    try writeCString(writer, value);
}

pub fn sendNoticeResponse(writer: *Io.Writer, fields: ErrorFields) WriteError!void {
    var payload_size: i32 = 0;
    payload_size += 1 + @as(i32, @intCast(fields.severity.len)) + 1;
    payload_size += 1 + @as(i32, @intCast(fields.message.len)) + 1;
    payload_size += 1;

    try writeByte(writer, types.MessageType.notice_response);
    try writeInt32(writer, 4 + payload_size);
    try writeErrorField(writer, types.ErrorFieldType.severity, fields.severity);
    try writeErrorField(writer, types.ErrorFieldType.message, fields.message);
    try writeNull(writer);
}

// ─── Extended Query Protocol ───────────────────────────────────────

pub fn sendParseComplete(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, types.MessageType.parse_complete);
    try writeInt32(writer, 4);
}

pub fn sendBindComplete(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, types.MessageType.bind_complete);
    try writeInt32(writer, 4);
}

pub fn sendCloseComplete(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, types.MessageType.close_complete);
    try writeInt32(writer, 4);
}

pub fn sendParameterDescription(writer: *Io.Writer, param_types: []const i32) WriteError!void {
    var payload_size: i32 = 2;
    payload_size += @as(i32, @intCast(param_types.len)) * 4;

    try writeByte(writer, types.MessageType.parameter_description);
    try writeInt32(writer, 4 + payload_size);
    try writeInt16(writer, @intCast(param_types.len));
    for (param_types) |oid| {
        try writeInt32(writer, oid);
    }
}

pub fn sendNoData(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, types.MessageType.no_data);
    try writeInt32(writer, 4);
}

pub fn sendPortalSuspended(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, types.MessageType.portal_suspended);
    try writeInt32(writer, 4);
}

// ─── SSL ───────────────────────────────────────────────────────────

pub fn declineSSL(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, 'N');
}

pub fn acceptSSL(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, 'S');
}

// ─── COPY protocol ─────────────────────────────────────────────────

pub fn sendCopyInResponse(writer: *Io.Writer, format: i16, column_formats: []const i16) WriteError!void {
    var payload_size: i32 = 3;
    payload_size += @as(i32, @intCast(column_formats.len)) * 2;

    try writeByte(writer, types.MessageType.copy_in_response);
    try writeInt32(writer, 4 + payload_size);
    try writeInt16(writer, format);
    try writeInt16(writer, @intCast(column_formats.len));
    for (column_formats) |f| {
        try writeInt16(writer, f);
    }
}

pub fn sendCopyOutResponse(writer: *Io.Writer, format: i16, column_formats: []const i16) WriteError!void {
    var payload_size: i32 = 3;
    payload_size += @as(i32, @intCast(column_formats.len)) * 2;

    try writeByte(writer, types.MessageType.copy_out_response);
    try writeInt32(writer, 4 + payload_size);
    try writeInt16(writer, format);
    try writeInt16(writer, @intCast(column_formats.len));
    for (column_formats) |f| {
        try writeInt16(writer, f);
    }
}

pub fn sendCopyData(writer: *Io.Writer, data: []const u8) WriteError!void {
    try writeByte(writer, types.MessageType.copy_data);
    try writeInt32(writer, @intCast(4 + data.len));
    try writeBytes(writer, data);
}

pub fn sendCopyDone(writer: *Io.Writer) WriteError!void {
    try writeByte(writer, types.MessageType.copy_done);
    try writeInt32(writer, 4);
}

pub fn sendCopyFail(writer: *Io.Writer, message: []const u8) WriteError!void {
    try writeByte(writer, types.MessageType.copy_fail);
    try writeInt32(writer, @intCast(4 + message.len + 1));
    try writeCString(writer, message);
}

// ─── Statement splitting ───────────────────────────────────────────

pub const Statement = struct {
    query: []const u8,
};

pub fn splitStatements(query: []const u8, alloc: std.mem.Allocator) ![]Statement {
    var result: std.ArrayListUnmanaged(Statement) = .empty;
    errdefer result.deinit(alloc);

    var start: usize = 0;
    var i: usize = 0;
    var in_single_quote = false;
    var in_double_quote = false;

    while (i < query.len) : (i += 1) {
        const c = query[i];

        if (in_single_quote) {
            if (c == '\'') {
                if (i + 1 < query.len and query[i + 1] == '\'') {
                    i += 1;
                } else {
                    in_single_quote = false;
                }
            }
        } else if (in_double_quote) {
            if (c == '"') {
                if (i + 1 < query.len and query[i + 1] == '"') {
                    i += 1;
                } else {
                    in_double_quote = false;
                }
            }
        } else {
            if (c == '\'') {
                in_single_quote = true;
            } else if (c == '"') {
                in_double_quote = true;
            } else if (c == ';') {
                const stmt = std.mem.trim(u8, query[start..i], " \t\n\r");
                if (stmt.len > 0) {
                    try result.append(alloc, .{ .query = stmt });
                }
                start = i + 1;
            }
        }
    }

    const remaining = std.mem.trim(u8, query[start..], " \t\n\r");
    if (remaining.len > 0) {
        try result.append(alloc, .{ .query = remaining });
    }

    return try result.toOwnedSlice(alloc);
}
