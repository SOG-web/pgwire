# PostgreSQL Wire Protocol

## TCP Connection Basics

- TCP stays connected like WebSocket — once `accept()` succeeds, you have one persistent socket
- The reader and writer are views into that same socket — reader for incoming bytes, writer for outgoing bytes
- They don't go away until the connection closes

## Blocking Reads

Each `read` call blocks — the program sits on that line until bytes arrive on the socket.

Example flow:

```
Server code                           Client (psql)
─────────────                         ──────────────
                                      connects via TCP
readStartupMessage() ← blocks until   sends SSLRequest (8 bytes)
  it reads 8 bytes
                                      waiting for response...
write "N" + flush() ──────────────→   receives 'N'
readStartupMessage() ← blocks until   sends StartupMessage
  it reads the bytes
while(readMessage()) ← blocks until   waiting for query...
```

The server's code flow is linear — it reads messages in the order it expects them. The client's behavior (what it sends next) is determined by the protocol, not by the server's code structure.

## Message Formats

### Startup Message (no type byte)

```
int32 length    (includes itself)
int32 version   (e.g., 3.0 = 196608)
params...       (null-terminated key=value pairs)
```

Special versions:
- `1234.5679` (80877103) = SSLRequest
- `1234.5680` (80877104) = GSSENCRequest

### Regular Messages (after startup)

```
char type       (message type identifier)
int32 length    (includes itself, excludes type byte)
payload...
```

## Protocol Flow

```
Client                              Server
  |                                    |
  |--- TCP Connect ------------------->|
  |                                    |
  |--- SSLRequest (80877103) -------->|  (optional, only if SSL requested)
  |<-- 'N' (no SSL) ------------------|
  |                                    |
  |--- StartupMessage (version 3.0) ->|  (length + version + key=value params)
  |<-- AuthenticationOk ('R') --------|  (server sends THIS)
  |<-- ParameterStatus ('S') ---------|  (server sends these)
  |<-- BackendKeyData ('K') ----------|
  |<-- ReadyForQuery ('Z') -----------|  (server sends THIS)
  |                                    |
  |--- Query: "SELECT 1" ('Q') ------>|  (now queries can flow)
  |<-- RowDescription ('T') ----------|
  |<-- DataRow ('D') ------------------|
  |<-- CommandComplete ('C') ---------|
  |<-- ReadyForQuery ('Z') -----------|
```

Key points:
- ReadyForQuery is sent by the **server**, not the client
- After the startup handshake, the server sends responses first
- Then the client can send queries

## State Machine

The server tracks connection state:

```
State: STARTUP
  └─ message arrives → is it SSLRequest?
       ├─ yes → send 'N', stay in STARTUP
       └─ no  → process startup, transition to READY

State: READY
  └─ message arrives → parse SQL, send results, send ReadyForQuery
```

## Message Type Constants

From `src/types.zig`:

```zig
pub const Authentication = 'R';
pub const Query = 'Q';
pub const Terminate = 'X';
pub const ReadyForQuery = 'Z';
pub const Parse = 'P';
pub const Bind = 'B';
pub const Error = 'E';
pub const CommandComplete = 'C';
pub const DataRow = 'D';
pub const RowDescription = 'T';
pub const SSL_RESPONSE = 'N';
pub const SSLRequest = 80877103;
```
