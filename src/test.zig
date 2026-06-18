const std = @import("std");
const testing = std.testing;
const Io = std.Io;
const pgwire = @import("pgwire");
const types = pgwire.types;
const message = pgwire.server.message;
const connection = pgwire.server.connection;
const server = pgwire.server;

// ─── Write tests ───────────────────────────────────────────────────

test "writeInt32 big endian" {
    var buf: [4]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.writeInt32(&writer, 0x01020304);
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3, 4 }, &buf);
}

test "writeInt16 big endian" {
    var buf: [2]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.writeInt16(&writer, 0x0102);
    try testing.expectEqualSlices(u8, &.{ 1, 2 }, &buf);
}

test "writeByte" {
    var buf: [1]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.writeByte(&writer, 'A');
    try testing.expectEqual(@as(u8, 'A'), buf[0]);
}

test "writeBytes" {
    var buf: [5]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.writeBytes(&writer, "hello");
    try testing.expectEqualSlices(u8, "hello", &buf);
}

test "writeCString" {
    var buf: [6]u8 = [_]u8{ 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF };
    var writer = Io.Writer.fixed(&buf);
    try message.writeCString(&writer, "hi");
    try testing.expectEqualSlices(u8, &.{ 'h', 'i', 0, 0xFF, 0xFF, 0xFF }, &buf);
}

test "sendAuthOk" {
    var buf: [9]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendAuthOk(&writer);
    try testing.expectEqual(@as(u8, 'R'), buf[0]);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 8 }, buf[1..5]);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, buf[5..9]);
}

test "sendReadyForQuery idle" {
    var buf: [6]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendReadyForQuery(&writer, .idle);
    try testing.expectEqual(@as(u8, 'Z'), buf[0]);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 5 }, buf[1..5]);
    try testing.expectEqual(@as(u8, 'I'), buf[5]);
}

test "sendReadyForQuery in_transaction" {
    var buf: [6]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendReadyForQuery(&writer, .in_transaction);
    try testing.expectEqual(@as(u8, 'T'), buf[5]);
}

test "sendReadyForQuery in_failed_transaction" {
    var buf: [6]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendReadyForQuery(&writer, .in_failed_transaction);
    try testing.expectEqual(@as(u8, 'E'), buf[5]);
}

test "sendParameterStatus" {
    var buf: [30]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendParameterStatus(&writer, "server_version", "1.0");
    try testing.expectEqual(@as(u8, 'S'), buf[0]);
    // length = 4 + 14 + 1 + 3 + 1 = 23
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 23 }, buf[1..5]);
    try testing.expectEqualSlices(u8, "server_version", buf[5..19]);
    try testing.expectEqual(@as(u8, 0), buf[19]);
    try testing.expectEqualSlices(u8, "1.0", buf[20..23]);
    try testing.expectEqual(@as(u8, 0), buf[23]);
}

test "sendBackendKeyData" {
    var buf: [13]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendBackendKeyData(&writer, 123, 456);
    try testing.expectEqual(@as(u8, 'K'), buf[0]);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 12 }, buf[1..5]);
    try testing.expectEqual(@as(i32, 123), message.readInt32(&buf, 5));
    try testing.expectEqual(@as(i32, 456), message.readInt32(&buf, 9));
}

test "sendCommandComplete" {
    var buf: [16]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendCommandComplete(&writer, "INSERT 0 1");
    try testing.expectEqual(@as(u8, 'C'), buf[0]);
    try testing.expectEqualSlices(u8, "INSERT 0 1", buf[5..15]);
    try testing.expectEqual(@as(u8, 0), buf[15]);
}

test "sendParseComplete" {
    var buf: [5]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendParseComplete(&writer);
    try testing.expectEqual(@as(u8, '1'), buf[0]);
    try testing.expectEqualSlices(u8, &.{ 0, 0, 0, 4 }, buf[1..5]);
}

test "sendBindComplete" {
    var buf: [5]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendBindComplete(&writer);
    try testing.expectEqual(@as(u8, '2'), buf[0]);
}

test "sendCloseComplete" {
    var buf: [5]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendCloseComplete(&writer);
    try testing.expectEqual(@as(u8, '3'), buf[0]);
}

test "sendNoData" {
    var buf: [5]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendNoData(&writer);
    try testing.expectEqual(@as(u8, 'n'), buf[0]);
}

test "sendEmptyQueryResponse" {
    var buf: [5]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendEmptyQueryResponse(&writer);
    try testing.expectEqual(@as(u8, 'I'), buf[0]);
}

test "sendPortalSuspended" {
    var buf: [5]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendPortalSuspended(&writer);
    try testing.expectEqual(@as(u8, 's'), buf[0]);
}

test "declineSSL" {
    var buf: [1]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.declineSSL(&writer);
    try testing.expectEqual(@as(u8, 'N'), buf[0]);
}

test "acceptSSL" {
    var buf: [1]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.acceptSSL(&writer);
    try testing.expectEqual(@as(u8, 'S'), buf[0]);
}

// ─── Error response ────────────────────────────────────────────────

test "sendErrorResponse includes sqlstate" {
    var buf: [100]u8 = [_]u8{0} ** 100;
    var writer = Io.Writer.fixed(&buf);
    try message.sendErrorResponse(&writer, .{
        .sqlstate = "42P01",
        .message = "relation does not exist",
    });
    // Verify header: 'E' + length
    try testing.expectEqual(@as(u8, 'E'), buf[0]);
    // Verify S field: 'S' + "ERROR" + \0 at offset 5
    try testing.expectEqual(types.ErrorFieldType.severity, buf[5]);
    try testing.expectEqualSlices(u8, "ERROR", buf[6..11]);
    try testing.expectEqual(@as(u8, 0), buf[11]);
    // Verify C field: 'C' + "42P01" + \0 at offset 12
    try testing.expectEqual(types.ErrorFieldType.sqlstate, buf[12]);
    try testing.expectEqualSlices(u8, "42P01", buf[13..18]);
    try testing.expectEqual(@as(u8, 0), buf[18]);
    // Verify M field: 'M' + message + \0 at offset 19
    try testing.expectEqual(types.ErrorFieldType.message, buf[19]);
    try testing.expectEqualSlices(u8, "relation does not exist", buf[20..43]);
    try testing.expectEqual(@as(u8, 0), buf[43]);
    // Verify terminator
    try testing.expectEqual(@as(u8, 0), buf[44]);
}

test "sendErrorResponseSimple" {
    var buf: [100]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendErrorResponseSimple(&writer, "42P01", "not found");
    try testing.expectEqual(@as(u8, 'E'), buf[0]);
}

test "sendNoticeResponse" {
    var buf: [50]u8 = undefined;
    var writer = Io.Writer.fixed(&buf);
    try message.sendNoticeResponse(&writer, .{ .message = "warning" });
    try testing.expectEqual(@as(u8, 'N'), buf[0]);
}

// ─── Read helpers ──────────────────────────────────────────────────

test "readCString" {
    const payload = "hello\x00world\x00";
    const result = message.readCString(payload, 0);
    try testing.expectEqualStrings("hello", result.value);
    try testing.expectEqual(@as(usize, 6), result.end);

    const result2 = message.readCString(payload, result.end);
    try testing.expectEqualStrings("world", result2.value);
}

test "readInt16" {
    const payload = [_]u8{ 0, 42 };
    try testing.expectEqual(@as(i16, 42), message.readInt16(&payload, 0));
}

test "readInt32" {
    const payload = [_]u8{ 0, 0, 0, 100 };
    try testing.expectEqual(@as(i32, 100), message.readInt32(&payload, 0));
}

test "readQuery extracts null-terminated string" {
    const payload = "SELECT 1\x00";
    const msg_instance = types.Message{ .type = 'Q', .payload = payload };
    try testing.expectEqualStrings("SELECT 1", message.readQuery(msg_instance));
}

test "readQuery without null terminator" {
    const payload = "SELECT 1";
    const msg_instance = types.Message{ .type = 'Q', .payload = payload };
    try testing.expectEqualStrings("SELECT 1", message.readQuery(msg_instance));
}

// ─── Statement splitting ───────────────────────────────────────────

test "splitStatements single" {
    const result = try message.splitStatements("SELECT 1", testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqualStrings("SELECT 1", result[0].query);
}

test "splitStatements multiple" {
    const result = try message.splitStatements("SELECT 1; SELECT 2; SELECT 3", testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 3), result.len);
    try testing.expectEqualStrings("SELECT 1", result[0].query);
    try testing.expectEqualStrings("SELECT 2", result[1].query);
    try testing.expectEqualStrings("SELECT 3", result[2].query);
}

test "splitStatements with quotes" {
    const result = try message.splitStatements("SELECT ';' as x; SELECT 1", testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 2), result.len);
    try testing.expectEqualStrings("SELECT ';' as x", result[0].query);
    try testing.expectEqualStrings("SELECT 1", result[1].query);
}

test "splitStatements trims whitespace" {
    const result = try message.splitStatements("  SELECT 1  ;  SELECT 2  ", testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 2), result.len);
    try testing.expectEqualStrings("SELECT 1", result[0].query);
    try testing.expectEqualStrings("SELECT 2", result[1].query);
}

test "splitStatements empty" {
    const result = try message.splitStatements("", testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 0), result.len);
}

test "splitStatements trailing semicolon" {
    const result = try message.splitStatements("SELECT 1;", testing.allocator);
    defer testing.allocator.free(result);
    try testing.expectEqual(@as(usize, 1), result.len);
    try testing.expectEqualStrings("SELECT 1", result[0].query);
}

// ─── ConnectionState ───────────────────────────────────────────────

test "ConnectionState setParameter" {
    var state = connection.ConnectionState{};
    state.setParameter("user", "alice");
    state.setParameter("database", "mydb");
    try testing.expectEqualStrings("alice", state.getCurrentUser());
    try testing.expectEqualStrings("mydb", state.getCurrentDatabase());
}

test "ConnectionState defaults" {
    const state = connection.ConnectionState{};
    try testing.expectEqualStrings("postgres", state.getCurrentUser());
    try testing.expectEqualStrings("postgres", state.getCurrentDatabase());
    try testing.expectEqual(false, state.authenticated);
    try testing.expectEqual(types.TransactionStatus.idle, state.transaction_status);
}

test "ConnectionState authenticate" {
    var state = connection.ConnectionState{};
    state.authenticate(196608);
    try testing.expectEqual(true, state.authenticated);
    try testing.expectEqual(@as(i32, 196608), state.protocol_version);
}

test "ConnectionState transaction tracking" {
    var state = connection.ConnectionState{};
    try testing.expectEqual(types.TransactionStatus.idle, state.transaction_status);

    state.beginTransaction();
    try testing.expectEqual(types.TransactionStatus.in_transaction, state.transaction_status);

    state.commitTransaction();
    try testing.expectEqual(types.TransactionStatus.idle, state.transaction_status);

    state.beginTransaction();
    state.failTransaction();
    try testing.expectEqual(types.TransactionStatus.in_failed_transaction, state.transaction_status);

    state.rollbackTransaction();
    try testing.expectEqual(types.TransactionStatus.idle, state.transaction_status);
}

test "ConnectionState detectTransactionCommand" {
    var state = connection.ConnectionState{};

    state.detectTransactionCommand("BEGIN");
    try testing.expectEqual(types.TransactionStatus.in_transaction, state.transaction_status);

    state.detectTransactionCommand("COMMIT");
    try testing.expectEqual(types.TransactionStatus.idle, state.transaction_status);

    state.detectTransactionCommand("begin");
    try testing.expectEqual(types.TransactionStatus.in_transaction, state.transaction_status);

    state.detectTransactionCommand("rollback");
    try testing.expectEqual(types.TransactionStatus.idle, state.transaction_status);
}

test "ConnectionState incrementQueryCount" {
    var state = connection.ConnectionState{};
    try testing.expectEqual(@as(u32, 0), state.queries_executed);
    state.incrementQueryCount();
    try testing.expectEqual(@as(u32, 1), state.queries_executed);
    state.incrementQueryCount();
    try testing.expectEqual(@as(u32, 2), state.queries_executed);
}

// ─── Extended Query parsing ────────────────────────────────────────

test "parseStatement" {
    // stmt_name\0 query\0 num_params(0) — no param types
    const payload = "my_stmt\x00SELECT $1\x00\x00\x00";
    const result = connection.parseStatement(payload, testing.allocator) orelse return error.TestExpectedNonZero;
    defer testing.allocator.free(result.param_types);
    try testing.expectEqualStrings("my_stmt", result.statement_name);
    try testing.expectEqualStrings("SELECT $1", result.query);
    try testing.expectEqual(@as(usize, 0), result.param_types.len);
}

test "parseStatement with params" {
    // stmt_name\0 query\0 num_params(2) param_types(23, 25)
    var buf: [50]u8 = undefined;
    var offset: usize = 0;
    // stmt_name
    @memcpy(buf[offset..][0..3], "ab\x00");
    offset += 3;
    // query
    @memcpy(buf[offset..][0..10], "SELECT $1\x00");
    offset += 10;
    // num_params = 2
    buf[offset] = 0;
    buf[offset + 1] = 2;
    offset += 2;
    // param_types: 23 (INT4), 25 (TEXT)
    std.mem.writeInt(i32, buf[offset..][0..4], 23, .big);
    offset += 4;
    std.mem.writeInt(i32, buf[offset..][0..4], 25, .big);
    offset += 4;

    const result = connection.parseStatement(buf[0..offset], testing.allocator) orelse return error.TestExpectedNonZero;
    defer testing.allocator.free(result.param_types);
    try testing.expectEqualStrings("ab", result.statement_name);
    try testing.expectEqualStrings("SELECT $1", result.query);
    try testing.expectEqual(@as(usize, 2), result.param_types.len);
    try testing.expectEqual(@as(i32, 23), result.param_types[0]);
    try testing.expectEqual(@as(i32, 25), result.param_types[1]);
}

test "parseDescribe statement" {
    const payload = "Smy_stmt\x00";
    const result = connection.parseDescribe(payload) orelse return error.TestExpectedNonZero;
    try testing.expectEqual(@as(u8, 'S'), result.kind);
    try testing.expectEqualStrings("my_stmt", result.name);
}

test "parseDescribe portal" {
    const payload = "Pmy_portal\x00";
    const result = connection.parseDescribe(payload) orelse return error.TestExpectedNonZero;
    try testing.expectEqual(@as(u8, 'P'), result.kind);
    try testing.expectEqualStrings("my_portal", result.name);
}

test "parseExecute" {
    // portal_name\0 max_rows(int32)
    var buf: [20]u8 = undefined;
    @memcpy(buf[0..7], "portal\x00");
    std.mem.writeInt(i32, buf[7..][0..4], 100, .big);
    const result = connection.parseExecute(buf[0..11]) orelse return error.TestExpectedNonZero;
    try testing.expectEqualStrings("portal", result.portal_name);
    try testing.expectEqual(@as(i32, 100), result.max_rows);
}

test "parseClose statement" {
    const payload = "Smy_stmt\x00";
    const result = connection.parseClose(payload) orelse return error.TestExpectedNonZero;
    try testing.expectEqual(@as(u8, 'S'), result.kind);
    try testing.expectEqualStrings("my_stmt", result.name);
}

test "parseClose portal" {
    const payload = "P\x00";
    const result = connection.parseClose(payload) orelse return error.TestExpectedNonZero;
    try testing.expectEqual(@as(u8, 'P'), result.kind);
    try testing.expectEqualStrings("", result.name);
}

// ─── Buffered writer ───────────────────────────────────────────────

test "MessageWriter buffers writes" {
    var target_buf: [1024]u8 = undefined;
    var writer = Io.Writer.fixed(&target_buf);

    const MsgWriter = server.buffered.MessageWriter(1024);
    var mw = MsgWriter.init(&writer);

    try mw.writeAll("hello");
    try mw.writeAll(" world");
    try testing.expectEqual(@as(usize, 0), writer.end);

    try mw.flush();
    try testing.expectEqual(@as(usize, 11), writer.end);
    try testing.expectEqualSlices(u8, "hello world", target_buf[0..11]);
}

test "MessageWriter auto-flushes when buffer full" {
    var target_buf: [20]u8 = undefined;
    var writer = Io.Writer.fixed(&target_buf);

    const MsgWriter = server.buffered.MessageWriter(8);
    var mw = MsgWriter.init(&writer);

    try mw.writeAll("12345678");
    try mw.writeAll("9");
    try mw.flush();
    try testing.expectEqualSlices(u8, "123456789", target_buf[0..9]);
}

test "MessageWriter discard" {
    var target_buf: [100]u8 = undefined;
    var writer = Io.Writer.fixed(&target_buf);

    const MsgWriter = server.buffered.MessageWriter(1024);
    var mw = MsgWriter.init(&writer);

    try mw.writeAll("hello");
    mw.discard();
    try mw.flush();
    try testing.expectEqual(@as(usize, 0), writer.end);
}
