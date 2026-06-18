# pgwire.zig Roadmap

Tracking remaining work to make the library production-ready.

## Done

- [x] SSLRequest/SSL decline handshake
- [x] CancelRequest detection
- [x] Startup message parsing (version + key=value params)
- [x] AuthOk + ParameterStatus + BackendKeyData + ReadyForQuery
- [x] Simple Query protocol (Q messages)
- [x] Extended Query message builders (Parse/Bind/Describe/Execute/Close/Sync)
- [x] Terminate (X) handling
- [x] ConnectionState (auth, params, transactions, query count)
- [x] Error responses with SQLSTATE C field
- [x] Notice responses
- [x] MD5 auth message builders (challenge + response)
- [x] SCRAM-SHA-256 auth message builders (SASL/SASLContinue/SASLFinal)
- [x] COPY protocol message builders (CopyIn/Out/Data/Done/Fail)
- [x] EmptyQueryResponse, PortalSuspended, NoData
- [x] Transaction status tracking (detectTransactionCommand)
- [x] Library API designed for consumer ownership

## To Do

### 1. Error propagation on writes
All `writeInt32`, `writeByte`, `writeBytes`, `sendXxx` functions silently `catch return`. A real consumer needs to know when writes fail.

**Plan:**
- Change write primitives to return `error{WriteFailed}`
- Add `sendXxx` variants that return errors
- Add a `MessageWriter` that buffers and flushes atomically (optional)

### 2. Test suite
Zero tests currently. Need unit tests for message building and parsing.

**Plan:**
- Test message building: build a message, verify bytes match expected format
- Test readCString, readInt16, readInt32
- Test ConnectionState: setParameter, detectTransactionCommand, transaction transitions
- Test readStartupMessage / readMessage with synthetic buffers
- Integration test: connect with psql in CI (if possible)

### 3. Full Extended Query state management
We have message builders but no state for prepared statements/portals.

**Plan:**
- Add `PreparedStatements` and `Portals` maps to ConnectionState
- Add `parseStatement()` to extract statement name + query + param types from Parse payload
- Add `bindPortal()` to extract portal name + statement + params from Bind payload
- Add `executePortal()` to execute a bound portal and send results
- Consumer calls these from their message loop

### 4. Real MD5/SCRAM crypto
Message builders exist but no actual hashing. Consumers would need crypto themselves.

**Plan:**
- Implement MD5: `md5(md5(password + username) + salt)` using Zig's std.crypto
- Implement SCRAM-SHA-256: HMAC-SHA256, PBKDF2, SaltedPassword generation
- Add to `server/auth.zig` as standalone functions
- Consumer calls `auth.computeMD5Hash(...)` or `auth.verifyScramProof(...)`

### 5. Multi-statement Simple Query
`SELECT 1; SELECT 2;` should produce two result sets. Currently not handled.

**Plan:**
- Add `splitStatements(query) -> [][]const u8` that splits on `;` (respecting quotes)
- Consumer iterates statements and handles each one
- Each statement gets its own RowDescription/DataRow/CommandComplete cycle

### 6. Atomic writes (buffered output)
Multiple send calls write directly to stream. Could buffer and flush as one unit.

**Plan:**
- Add `BufferedWriter` that wraps an Io.Writer
- All `sendXxx` functions write to buffer
- Consumer calls `flush()` to send everything at once
- Prevents partial message delivery on error

## Out of Scope (for poolers/implementers)

- Connection pooling / ConnectionManager
- Graceful shutdown / signal handling
- Server lifecycle management
- Query execution / SQL parsing
