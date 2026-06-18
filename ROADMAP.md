# pgwire.zig Roadmap

Tracking remaining work to make the library production-ready.

## Protocol support

### Message format

- [x] Frontend-Backend protocol messages (3.0)
- [ ] Frontend-Backend protocol messages (3.2, PostgreSQL 18)
- [ ] Streaming replication protocol
- [ ] Logical streaming replication protocol messages

### Frontend-Backend interaction

- [x] SSL Request and Response (decline/accept)
- [ ] PostgreSQL 17 direct SSL negotiation
- [ ] GSSAPI Request and Response (no encryption support)
- [ ] GSSAPI/SSPI authentication

#### Startup

- [x] Protocol negotiation (version + key=value params)
- [x] No authentication (AuthOk)
- [x] MD5 password authentication
- [x] SCRAM-SHA-256 authentication
- [ ] SCRAM-SHA-256-PLUS (channel binding)
- [ ] Clear-text password authentication
- [ ] SASL OAUTH (PostgreSQL 18)

#### Simple Query

- [x] Simple Query protocol (Q messages)
- [x] Multi-statement queries (quote-aware splitting)
- [x] RowDescription, DataRow, CommandComplete
- [x] EmptyQueryResponse

#### Extended Query

- [x] Parse (P) + ParseComplete
- [x] Bind (B) + BindComplete
- [ ] Describe (prepared statement) + ParameterDescription
- [ ] Describe (portal) + RowDescription
- [x] Execute (E) + PortalSuspended
- [x] Close (C) + CloseComplete
- [x] Sync (S) + ReadyForQuery
- [x] Flush (H)
- [ ] Portal naming (unnamed portal)
- [ ] Extended Query state machine

#### Termination

- [x] Terminate (X) handling

#### Cancel

- [x] CancelRequest detection
- [ ] Query cancellation execution (BackendKeyData lookup)

#### Error and Notice

- [x] ErrorResponse with SQLSTATE codes
- [x] NoticeResponse
- [x] ErrorFieldType constants (S/C/M/D/H/P/etc.)
- [x] Error/Warning severity levels

#### Copy

- [x] CopyInResponse (server ← client)
- [x] CopyOutResponse (server → client)
- [x] CopyData
- [x] CopyDone
- [x] CopyFail
- [ ] CopyBoth (simultaneous in/out)

#### Notification

- [ ] Notify (server → client async notification)

### Data types

- [x] Text format (null-terminated strings)
- [ ] Binary format (raw bytes)

### APIs

#### Backend/Server (pgwire.zig)

- [x] Startup APIs (readStartupMessage, ParameterStatus, BackendKeyData)
- [x] Simple Query API (sendRowDescription, sendDataRow, sendCommandComplete)
- [x] Extended Query API (sendParseComplete, sendBindComplete, sendExecute, sendClose)
- [ ] Extended Query state machine (session state tracking)
- [ ] QueryParser API (prepared statement transformation)
- [ ] ResultSet builder/encoder API
- [x] Query Cancellation API (CancelRequest detection)
- [x] Error and Notice API (sendErrorResponse, sendNoticeResponse)
- [x] Copy API (CopyIn, CopyOut, CopyData, CopyDone, CopyFail)
- [ ] CopyBoth API
- [x] Transaction state (idle/in_transaction/in_failed_transaction)
- [ ] Streaming replication API
- [ ] Logical streaming replication API
- [ ] AuthSource API (fetching and hashing passwords)
- [ ] Server parameters API (dynamic parameter management)

#### Frontend/Client

- [ ] Client connection API (connect to PostgreSQL server)
- [ ] Simple Query client API
- [ ] Extended Query client API
- [ ] ResultSet decoder API
- [ ] Copy client API
- [ ] Transaction state tracking
- [ ] Query cancellation client API

## In Progress

### SSL/TLS support

Currently declines SSL. Production use requires accepting TLS.

- [ ] Accept SSLRequest and upgrade connection to TLS
- [ ] PostgreSQL 17 direct SSL negotiation
- [ ] Zig std.tls integration
- [ ] Certificate configuration options

### Extended Query state machine

Current approach: message builders only. Needs session-level state tracking.

- [ ] Track prepared statements per connection
- [ ] Track portals per connection
- [ ] Execute against specific portal (not just unnamed)
- [ ] Describe against prepared statement or portal
- [ ] Sync resets portal state

### Portal naming

Most clients use unnamed portal (""). Need to support named portals for full Extended Query.

- [ ] Named portal support (Bind with portal name)
- [ ] Describe on named portal
- [ ] Execute on named portal
- [ ] Close on named portal

## Next

### Integration tests with real PG client

Most important. Unit tests verify message format but not protocol-level behavior.

- [ ] Start server in test, connect with libpq via C interop
- [ ] Test auth flow end-to-end (startup → auth → readyForQuery)
- [ ] Test simple query round-trip (query → rowDescription → dataRow → commandComplete → readyForQuery)
- [ ] Test extended query round-trip (parse → bind → execute → rows)
- [ ] Test COPY IN/OUT flow end-to-end
- [ ] Test error responses (bad query → ErrorResponse → readyForQuery)
- [ ] Test connection termination
- [ ] Test multi-statement queries


### Binary format support

Required by libpq and most ORMs when using Extended Query.

- [ ] Binary format for result columns
- [ ] Format code in RowDescription
- [ ] Format code in Bind message
- [ ] Binary data encoding (integers, floats, text, bytea)

### Pipeline mode (PostgreSQL 14+)

High-throughput clients rely on this for batching.

- [ ] Pipeline request message
- [ ] Pipeline sync handling
- [ ] Pipeline flush handling
- [ ] Pipeline error recovery

### Error path / resilience testing

What happens when clients misbehave.

- [ ] Partial message reads (client disconnects mid-message)
- [ ] Malformed message types
- [ ] Oversized messages
- [ ] Invalid UTF-8 in string fields
- [ ] Invalid SQLSTATE codes
- [ ] Buffer overflow in message writers

### Prepared statement lifecycle

Extended query works but there's no caching. Consumers need this for performance.

- [ ] Statement cache interface (consumer-owned)
- [ ] Statement deallocation on close
- [ ] Parameter type inference from describe results

### Performance benchmarks

- [ ] Message parsing throughput (messages/sec)
- [ ] Message writing throughput (messages/sec)
- [ ] Multi-statement split performance
- [ ] Compare with other PG wire protocol implementations

## Out of Scope (for poolers/implementers)

- Connection pooling / ConnectionManager
- Graceful shutdown / signal handling
- Server lifecycle management
- Query execution / SQL parsing
- TCP/TLS server (consumer owns the server loop, passes streams to library)
