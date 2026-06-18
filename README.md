# pgwire.zig

A PostgreSQL wire protocol library for Zig. Building blocks for building PostgreSQL-compatible servers.

## Status

Early development. Public API is not yet finalized.

## Building

```sh
zig build
```

## Architecture

The library provides primitives — the consumer owns the server loop, query handling, and auth decisions.

```
src/
├── root.zig              # library entry point
├── types.zig             # protocol constants (message types, OIDs, SQLSTATE codes, auth methods)
├── server/
│   ├── message.zig       # read/write functions for protocol messages
│   └── connection.zig    # ConnectionState tracker (auth, params, transactions)
└── main.zig              # test server harness (consumer example)
```

## Library API

### types.zig
Protocol constants: `MessageType`, `AuthMethod`, `DataType`, `ErrorCode`, `TransactionStatus`, `ColumnDesc`, `Message`, `StartupMessage`.

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
msg.sendCopyInResponse(writer, format, column_formats)
msg.sendCopyOutResponse(writer, format, column_formats)
msg.sendCopyData(writer, data)
msg.sendCopyDone(writer)
msg.sendCopyFail(writer, message)

// SSL
msg.declineSSL(writer)
msg.acceptSSL(writer)
```

### server.connection
Per-connection state tracker:

```zig
const ConnectionState = pgwire.server.connection.ConnectionState;

var state = ConnectionState{};
state.setParameter("user", "postgres");
state.authenticate(196608);
state.detectTransactionCommand("BEGIN");
state.beginTransaction();
state.commitTransaction();
state.incrementQueryCount();
```

## Usage

```zig
const pgwire = @import("pgwire");
const msg = pgwire.server.message;
const types = pgwire.types;
const ConnectionState = pgwire.server.connection.ConnectionState;

// Per-connection handler
fn handleClient(reader: *Io.Reader, writer: *Io.Writer) void {
    var state = ConnectionState{};

    // Startup
    if (msg.readStartupMessage(reader, alloc)) |startup| {
        state.authenticate(types.PROTOCOL_VERSION_3_0);
        msg.sendAuthOk(writer);
        msg.sendParameterStatus(writer, "server_version", "0.0.0");
        msg.sendBackendKeyData(writer, state.backend_pid, state.backend_secret);
        msg.sendReadyForQuery(writer, state.transaction_status);
    }

    // Message loop
    while (msg.readMessage(reader, alloc)) |message| {
        switch (message.type) {
            types.MessageType.query => {
                const query = msg.readQuery(message);
                state.detectTransactionCommand(query);
                // ... handle query ...
                msg.sendReadyForQuery(writer, state.transaction_status);
            },
            types.MessageType.terminate => break,
            else => {},
        }
    }
}
```

## Running the test server

```sh
zig build run
```

Connects on port 6432. Use with psql:

```sh
psql -h 127.0.0.1 -p 6432 -U user -d db
```

## Protocol support

- SSLRequest handshake (decline/accept)
- CancelRequest detection
- Startup message parsing (version + params)
- Simple Query protocol
- Extended Query protocol (Parse/Bind/Describe/Execute/Close/Sync)
- MD5 authentication (send challenge, verify response)
- SCRAM-SHA-256 authentication (SASL flow)
- Transaction status tracking (BEGIN/COMMIT/ROLLBACK)
- COPY protocol (CopyInResponse/CopyOutResponse/CopyData/CopyDone/CopyFail)
- Error responses with SQLSTATE codes
- Notice responses
- EmptyQueryResponse
- PortalSuspended

See [docs/protocol.md](docs/protocol.md) for wire protocol details.
