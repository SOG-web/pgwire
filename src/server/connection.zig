const std = @import("std");
const types = @import("../types.zig");

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

    /// Detect BEGIN/COMMIT/ROLLBACK from query text and update transaction status.
    /// Consumer can call this before executing a query.
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

pub const PreparedStatement = struct {
    name: []const u8,
    query: []const u8,
    param_types: []const i32,
};

pub const Portal = struct {
    name: []const u8,
    statement_name: []const u8,
    query: []const u8,
    parameters: []const []const u8,
};

pub const ScramCredentials = struct {
    salt: []const u8,
    iterations: u32,
    stored_key: []const u8,
    server_key: []const u8,
};
