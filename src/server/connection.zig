const std = @import("std");
const types = @import("../types.zig");
const message = @import("message.zig");

pub const ConnectionState = struct {
    // Authentication
    authenticated: bool = false,
    protocol_version: i32 = 0,

    // MD5 auth
    md5_salt: [4]u8 = undefined,

    // SCRAM auth
    scram_state: types.ScramState = .initial,
    scram_mechanism: []const u8 = "",
    scram_client_nonce: []const u8 = "",
    scram_server_nonce: []const u8 = "",
    scram_client_initial_bare: []const u8 = "",
    scram_server_first: []const u8 = "",
    scram_auth_message: []const u8 = "",

    // Connection parameters
    user: []const u8 = "",
    database: []const u8 = "",
    application_name: []const u8 = "",

    // Transaction state
    transaction_status: types.TransactionStatus = .idle,

    // Backend identification
    backend_pid: i32 = 0,
    backend_secret: i32 = 0,

    // Statistics
    queries_executed: u32 = 0,

    pub fn authenticate(self: *ConnectionState, version: i32) void {
        self.authenticated = true;
        self.protocol_version = version;
    }

    pub fn setParameter(self: *ConnectionState, key: []const u8, value: []const u8) void {
        if (std.mem.eql(u8, key, "user")) {
            self.user = value;
        } else if (std.mem.eql(u8, key, "database")) {
            self.database = value;
        } else if (std.mem.eql(u8, key, "application_name")) {
            self.application_name = value;
        }
    }

    pub fn getCurrentUser(self: *const ConnectionState) []const u8 {
        return if (self.user.len > 0) self.user else "postgres";
    }

    pub fn getCurrentDatabase(self: *const ConnectionState) []const u8 {
        return if (self.database.len > 0) self.database else "postgres";
    }

    pub fn setTransactionStatus(self: *ConnectionState, status: types.TransactionStatus) void {
        self.transaction_status = status;
    }

    pub fn beginTransaction(self: *ConnectionState) void {
        self.transaction_status = .in_transaction;
    }

    pub fn commitTransaction(self: *ConnectionState) void {
        self.transaction_status = .idle;
    }

    pub fn rollbackTransaction(self: *ConnectionState) void {
        self.transaction_status = .idle;
    }

    pub fn failTransaction(self: *ConnectionState) void {
        self.transaction_status = .in_failed_transaction;
    }

    pub fn incrementQueryCount(self: *ConnectionState) void {
        self.queries_executed += 1;
    }

    pub fn detectTransactionCommand(self: *ConnectionState, query: []const u8) void {
        const q = trimLeadingSpaces(query);
        if (q.len == 0) return;

        if (startsWithIgnoreCase(q, "begin")) {
            self.beginTransaction();
        } else if (startsWithIgnoreCase(q, "commit")) {
            self.commitTransaction();
        } else if (startsWithIgnoreCase(q, "rollback")) {
            self.rollbackTransaction();
        }
    }

    pub fn isInTransaction(self: *const ConnectionState) bool {
        return self.transaction_status == .in_transaction;
    }

    pub fn isInFailedTransaction(self: *const ConnectionState) bool {
        return self.transaction_status == .in_failed_transaction;
    }
};

// ─── Extended Query helpers ────────────────────────────────────────

pub const ParseResult = struct {
    statement_name: []const u8,
    query: []const u8,
    param_types: []const i32,
};

/// Parse a Parse message payload (after type byte + length).
/// Format: stmt_name\0 query\0 num_params(int16) param_types(int32 * num_params)
pub fn parseStatement(payload: []const u8, alloc: std.mem.Allocator) ?ParseResult {
    var offset: usize = 0;

    const name_result = message.readCString(payload, offset);
    const statement_name = name_result.value;
    offset = name_result.end;

    const query_result = message.readCString(payload, offset);
    const query = query_result.value;
    offset = query_result.end;

    if (offset + 2 > payload.len) return null;
    const num_params = @as(usize, @intCast(message.readInt16(payload, offset)));
    offset += 2;

    var param_types = alloc.alloc(i32, num_params) catch return null;
    for (0..num_params) |i| {
        if (offset + 4 > payload.len) {
            alloc.free(param_types);
            return null;
        }
        param_types[i] = message.readInt32(payload, offset);
        offset += 4;
    }

    return .{
        .statement_name = statement_name,
        .query = query,
        .param_types = param_types,
    };
}

pub const BindResult = struct {
    portal_name: []const u8,
    statement_name: []const u8,
    param_formats: []const i16,
    params: []const BindParam,
    result_formats: []const i16,
};

pub const BindParam = struct {
    data: ?[]const u8,
    format: i16,
};

/// Parse a Bind message payload (after type byte + length).
pub fn parseBind(payload: []const u8, alloc: std.mem.Allocator) ?BindResult {
    var offset: usize = 0;

    const portal_result = message.readCString(payload, offset);
    const portal_name = portal_result.value;
    offset = portal_result.end;

    const stmt_result = message.readCString(payload, offset);
    const statement_name = stmt_result.value;
    offset = stmt_result.end;

    // Parameter format codes
    if (offset + 2 > payload.len) return null;
    const num_formats = @as(usize, @intCast(message.readInt16(payload, offset)));
    offset += 2;

    var param_formats = alloc.alloc(i16, num_formats) catch return null;
    for (0..num_formats) |i| {
        if (offset + 2 > payload.len) {
            alloc.free(param_formats);
            return null;
        }
        param_formats[i] = message.readInt16(payload, offset);
        offset += 2;
    }

    // Parameters
    if (offset + 2 > payload.len) {
        alloc.free(param_formats);
        return null;
    }
    const num_params = @as(usize, @intCast(message.readInt16(payload, offset)));
    offset += 2;

    var params = alloc.alloc(BindParam, num_params) catch {
        alloc.free(param_formats);
        return null;
    };

    for (0..num_params) |i| {
        if (offset + 4 > payload.len) {
            alloc.free(param_formats);
            alloc.free(params);
            return null;
        }
        const param_len = message.readInt32(payload, offset);
        offset += 4;

        if (param_len == -1) {
            params[i] = .{ .data = null, .format = if (num_formats > 0) param_formats[0] else 0 };
        } else {
            const len: usize = @intCast(param_len);
            if (offset + len > payload.len) {
                alloc.free(param_formats);
                alloc.free(params);
                return null;
            }
            const data = alloc.alloc(u8, len) catch {
                alloc.free(param_formats);
                alloc.free(params);
                return null;
            };
            @memcpy(data, payload[offset .. offset + len]);
            offset += len;
            const fmt = if (i < num_formats) param_formats[i] else if (num_formats > 0) param_formats[0] else 0;
            params[i] = .{ .data = data, .format = fmt };
        }
    }

    // Result format codes
    if (offset + 2 > payload.len) {
        alloc.free(param_formats);
        alloc.free(params);
        return null;
    }
    const num_result_formats = @as(usize, @intCast(message.readInt16(payload, offset)));
    offset += 2;

    var result_formats = alloc.alloc(i16, num_result_formats) catch {
        alloc.free(param_formats);
        alloc.free(params);
        return null;
    };
    for (0..num_result_formats) |i| {
        if (offset + 2 > payload.len) {
            alloc.free(param_formats);
            alloc.free(params);
            alloc.free(result_formats);
            return null;
        }
        result_formats[i] = message.readInt16(payload, offset);
        offset += 2;
    }

    return .{
        .portal_name = portal_name,
        .statement_name = statement_name,
        .param_formats = param_formats,
        .params = params,
        .result_formats = result_formats,
    };
}

/// Parse a Describe message payload (after type byte + length).
pub const DescribeResult = struct {
    kind: u8, // 'S' for statement, 'P' for portal
    name: []const u8,
};

pub fn parseDescribe(payload: []const u8) ?DescribeResult {
    if (payload.len < 2) return null;
    const kind = payload[0];
    const name_result = message.readCString(payload, 1);
    return .{ .kind = kind, .name = name_result.value };
}

/// Parse an Execute message payload (after type byte + length).
pub const ExecuteResult = struct {
    portal_name: []const u8,
    max_rows: i32,
};

pub fn parseExecute(payload: []const u8) ?ExecuteResult {
    const name_result = message.readCString(payload, 0);
    const offset = name_result.end;
    if (offset + 4 > payload.len) return null;
    return .{
        .portal_name = name_result.value,
        .max_rows = message.readInt32(payload, offset),
    };
}

/// Parse a Close message payload (after type byte + length).
pub const CloseResult = struct {
    kind: u8, // 'S' for statement, 'P' for portal
    name: []const u8,
};

pub fn parseClose(payload: []const u8) ?CloseResult {
    if (payload.len < 2) return null;
    const kind = payload[0];
    const name_result = message.readCString(payload, 1);
    return .{ .kind = kind, .name = name_result.value };
}

// ─── Utility ───────────────────────────────────────────────────────

fn trimLeadingSpaces(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and s[i] == ' ') : (i += 1) {}
    return s[i..];
}

fn startsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (haystack.len < needle.len) return false;
    for (needle, 0..) |c, i| {
        if (std.ascii.toLower(haystack[i]) != c) return false;
    }
    return true;
}

pub const ScramCredentials = struct {
    salt: []const u8,
    iterations: u32,
    stored_key: []const u8,
    server_key: []const u8,
};
