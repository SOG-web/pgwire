# pgwire.zig

A PostgreSQL wire protocol library for Zig. Building blocks for building PostgreSQL-compatible servers.

## Status

Early development. Public API is not yet finalized. 75 unit tests passing.

## Building

```sh
zig build
```

## Running tests

```sh
zig build test
```

## Architecture

The library provides primitives — the consumer owns the server loop, query handling, and auth decisions.

```
src/
├── root.zig              # library entry point
├── types.zig             # protocol constants (message types, OIDs, SQLSTATE codes, auth methods)
├── server/
│   ├── message.zig       # read/write functions for protocol messages
│   ├── connection.zig    # ConnectionState tracker + extended query parsing
│   ├── auth.zig          # MD5 and SCRAM-SHA-256 crypto
│   └── buffered.zig      # MessageWriter for atomic buffered output
├── test.zig              # unit tests
└── main.zig              # test server harness (consumer example)
```

## Protocol support

### Message format

- ✅ Frontend-Backend protocol messages (3.0)
- ❌ Frontend-Backend protocol messages (3.2, PostgreSQL 18)
- ❌ Streaming replication protocol
- ❌ Logical streaming replication protocol messages

### Frontend-Backend interaction

- ✅ SSL Request and Response (decline/accept)
- ❌ PostgreSQL 17 direct SSL negotiation
- ❌ GSSAPI Request and Response (no encryption support)
- ❌ GSSAPI/SSPI authentication

#### Startup

- ✅ Protocol negotiation (version + key=value params)
- ✅ No authentication (AuthOk)
- ✅ MD5 password authentication
- ✅ SCRAM-SHA-256 authentication
- ❌ SCRAM-SHA-256-PLUS (channel binding)
- ❌ Clear-text password authentication
- ❌ SASL OAUTH (PostgreSQL 18)

#### Simple Query

- ✅ Simple Query protocol (Q messages)
- ✅ Multi-statement queries (quote-aware splitting)
- ✅ RowDescription, DataRow, CommandComplete
- ✅ EmptyQueryResponse

#### Extended Query

- ✅ Parse (P) + ParseComplete
- ✅ Bind (B) + BindComplete
- ❌ Describe (prepared statement) + ParameterDescription
- ❌ Describe (portal) + RowDescription
- ✅ Execute (E) + PortalSuspended
- ✅ Close (C) + CloseComplete
- ✅ Sync (S) + ReadyForQuery
- ✅ Flush (H)
- ❌ Portal naming (unnamed portal)
- ❌ Extended Query state machine

#### Termination

- ✅ Terminate (X) handling

#### Cancel

- ✅ CancelRequest detection
- ❌ Query cancellation execution (BackendKeyData lookup)

#### Error and Notice

- ✅ ErrorResponse with SQLSTATE codes
- ✅ NoticeResponse
- ✅ ErrorFieldType constants (S/C/M/D/H/P/etc.)
- ✅ Error/Warning severity levels

#### Copy

- ✅ CopyInResponse (server ← client)
- ✅ CopyOutResponse (server → client)
- ✅ CopyData
- ✅ CopyDone
- ✅ CopyFail
- ❌ CopyBoth (simultaneous in/out)

#### Notification

- ❌ Notify (server → client async notification)

### Data types

- ✅ Text format (null-terminated strings)
- ❌ Binary format (raw bytes)

### APIs

- ✅ message.zig — standalone read/write functions for all protocol messages
- ✅ connection.zig — ConnectionState + extended query parsing
- ✅ auth.zig — MD5 and SCRAM-SHA-256 crypto
- ✅ buffered.zig — MessageWriter for atomic buffered output
- ✅ All write/send functions return `WriteError!void`
- ❌ Extended Query state machine (session state tracking)
- ❌ QueryParser API (prepared statement transformation)
- ❌ ResultSet builder/encoder API
- ❌ AuthSource API (fetching and hashing passwords)
- ❌ Server parameters API (dynamic parameter management)
- ❌ Streaming replication API
- ❌ Logical streaming replication API
- ❌ SSL/TLS connection upgrade
- ❌ Client/frontend API (planned for future)
- ❌ TCP/TLS server (consumer owns the server loop)

### Testing

- ✅ 75 unit tests (message building, parsing, auth, buffered writer)
- ❌ Integration tests with real PG client
- ❌ End-to-end tests with libpq / psql

## Library API

### types.zig

Protocol constants: `MessageType`, `AuthMethod`, `DataType`, `ErrorCode`, `TransactionStatus`, `ErrorFieldType`, `ErrorSeverity`, `ColumnDesc`, `Message`, `StartupMessage`.

### server.message

Standalone functions for reading/writing protocol messages:

```zig
const msg = pgwire.server.message;

// Read
msg.readStartupMessage(reader, alloc) -> ?StartupMessage
msg.readMessage(reader, alloc) -> ?Message
msg.readQuery(message) -> []const u8
msg.readInt16(payload, offset) -> i16
msg.readInt32(payload, offset) -> i32
msg.readCString(payload, offset) -> { value, end }

// Auth
msg.sendAuthOk(writer)
msg.sendAuthMD5Password(writer, salt)
msg.sendAuthSASL(writer, mechanisms)
msg.sendAuthSASLContinue(writer, server_data)
msg.sendAuthSASLFinal(writer, server_data)

// Connection
msg.sendParameterStatus(writer, name, value)
msg.sendBackendKeyData(writer, pid, secret)
msg.sendReadyForQuery(writer, status)

// Query results
msg.sendRowDescription(writer, columns)
msg.sendDataRow(writer, values)
msg.sendCommandComplete(writer, tag)
msg.sendEmptyQueryResponse(writer)

// Errors
msg.sendErrorResponse(writer, .{ .sqlstate = "42P01", .message = "relation not found" })
msg.sendErrorResponseSimple(writer, "42P01", "relation not found")
msg.sendNoticeResponse(writer, .{ .message = "warning" })

// Extended Query
msg.sendParseComplete(writer)
msg.sendBindComplete(writer)
msg.sendCloseComplete(writer)
msg.sendParameterDescription(writer, param_types)
msg.sendNoData(writer)
msg.sendPortalSuspended(writer)

// COPY
msg.sendCopyInResponse(writer, format)
msg.sendCopyOutResponse(writer, format)
msg.sendCopyData(writer, data)
msg.sendCopyDone(writer)
msg.sendCopyFail(writer, error_message)

// Statement splitting
msg.splitStatements("SELECT 1; SELECT 2", alloc) -> []Statement

// All write/send functions return WriteError!void
```

### server.connection

Per-connection state tracker and extended query parsing:

```zig
const conn = pgwire.server.connection;

// State
var state = conn.ConnectionState{};
state.setParameter("user", "postgres");
state.authenticate(196608);
state.detectTransactionCommand("BEGIN");
state.beginTransaction();
state.commitTransaction();

// Extended Query parsing
conn.parseStatement(payload, alloc) -> ?ParseResult
conn.parseBind(payload, alloc) -> ?BindResult
conn.parseDescribe(payload) -> ?DescribeResult
conn.parseExecute(payload) -> ?ExecuteResult
conn.parseClose(payload) -> ?CloseResult
```

### server.auth

MD5 and SCRAM-SHA-256 cryptography. Functions that need randomness take a `std.Io` parameter.

```zig
const auth = pgwire.server.auth;

// MD5
const salt = auth.generateSalt(io);                       // requires Io
const hash = auth.computeMD5Password(username, password, salt);  // returns [35]u8
const ok = auth.verifyMD5Password(username, password, salt, client_hash);

// SCRAM-SHA-256
const creds = auth.generateScramCredentials(password, salt, 4096);
const valid = auth.verifyScramClientProof(creds.stored_key, auth_message, client_proof);
const sig = auth.generateScramServerSignature(creds.server_key, auth_message);

// SCRAM message builders
var buf: [256]u8 = undefined;
const server_first = auth.buildScramServerFirst(client_nonce, server_nonce, salt, 4096, &buf);
const server_final = auth.buildScramServerFinal(server_sig, &buf);
const auth_msg = auth.buildScramAuthMessage(client_first_bare, server_first, client_final, &buf);
auth.generateScramNonce(io, &buf);                        // requires Io
```

### server.buffered

Atomic buffered writer:

```zig
const MsgWriter = pgwire.server.buffered.MessageWriter(8192);
var mw = MsgWriter.init(&writer);
try msg.sendRowDescription(&mw.buf_writer, &columns);
try msg.sendDataRow(&mw.buf_writer, &row);
try msg.sendCommandComplete(&mw.buf_writer, "SELECT 1");
try mw.flush(); // sends everything atomically
```

## Running the test server

```sh
zig build run
```

Connects on port 6432. Use with psql:

```sh
psql -h 127.0.0.1 -p 6432 -U user -d db
```

See [ROADMAP.md](ROADMAP.md) for planned work and integration test status.
See [docs/protocol.md](docs/protocol.md) for wire protocol details.
