# pgwire.zig

A PostgreSQL wire protocol library for Zig.

## Status

Early development. Public API is not yet finalized.

## Building

```sh
zig build
```

## Usage

```zig
const pgwire = @import("pgwire");

var conn = pgwire.Connection.init(&reader, &writer, allocator);

// Handle startup
if (conn.readStartupMessage()) |startup| {
    conn.sendAuthOk();
    conn.sendParameterStatus("server_version", "0.0.0");
    conn.sendReadyForQuery();
    conn.flush();
}

// Message loop
while (conn.nextMessage()) |msg| {
    switch (msg.type) {
        pgwire.types.MessageType.query => {
            const query = pgwire.Connection.readQuery(msg);
            conn.sendRowDescription(&columns);
            conn.sendDataRow(&row);
            conn.sendCommandComplete("SELECT 1");
            conn.sendReadyForQuery();
            conn.flush();
        },
        pgwire.types.MessageType.terminate => break,
        else => {},
    }
    conn.resetArena();
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

## Protocol

- SSLRequest handshake (declines SSL)
- CancelRequest detection
- Startup message parsing (version + params)
- Simple Query protocol (`Q` messages)
- Extended Query stubs (Parse, Bind, Describe, Execute, Close, Sync, Flush)
- Terminate (`X`) handling

See [docs/protocol.md](docs/protocol.md) for wire protocol details.
