const std = @import("std");
const crypto = std.crypto;

/// Compute MD5 password hash for PostgreSQL MD5 authentication.
/// Returns "md5" + md5(md5(password + username) + salt) as a hex string.
pub fn computeMD5Password(username: []const u8, password: []const u8, salt: [4]u8) [35]u8 {
    // First hash: md5(password + username)
    var first_hash: [16]u8 = undefined;
    var first_md5 = crypto.hash.Md5.init(.{});
    first_md5.update(password);
    first_md5.update(username);
    first_md5.final(&first_hash);

    // Second hash: md5(first_hash + salt)
    var second_md5 = crypto.hash.Md5.init(.{});
    second_md5.update(&first_hash);
    second_md5.update(&salt);
    var result: [16]u8 = undefined;
    second_md5.final(&result);

    // Format as "md5" + hex
    var output: [35]u8 = undefined;
    output[0..3].* = "md5".*;
    const hex = std.fmt.bytesToHex(&result, .lower);
    @memcpy(output[3..], &hex);
    return output;
}

/// Verify an MD5 password response from the client.
pub fn verifyMD5Password(username: []const u8, password: []const u8, salt: [4]u8, client_hash: []const u8) bool {
    const expected = computeMD5Password(username, password, salt);
    if (client_hash.len != expected.len) return false;
    return std.mem.eql(u8, &expected, client_hash);
}

/// Generate a random 4-byte salt for MD5 authentication.
pub fn generateSalt(io: std.Io) [4]u8 {
    var salt: [4]u8 = undefined;
    io.random(&salt);
    return salt;
}

// ─── SCRAM-SHA-256 ─────────────────────────────────────────────────

/// SCRAM credentials stored for a user.
pub const ScramServerCredentials = struct {
    salted_password: [32]u8,
    stored_key: [32]u8,
    server_key: [32]u8,
};

/// Generate SCRAM credentials from a password and salt.
/// Used server-side to store/verify user credentials.
pub fn generateScramCredentials(password: []const u8, salt: []const u8, iterations: u32) ScramServerCredentials {
    const salted_password = pbkdf2Sha256(password, salt, iterations);
    const stored_key = hmacSha256(&salted_password, "Server Key");
    const server_key = hmacSha256(&stored_key, "Client Key");
    return .{
        .salted_password = salted_password,
        .stored_key = stored_key,
        .server_key = server_key,
    };
}

/// Verify a SCRAM client proof.
/// client_final_without_proof is the client-final-message without the ",p=..." part.
pub fn verifyScramClientProof(
    stored_key: [32]u8,
    auth_message: []const u8,
    client_proof: []const u8,
) bool {
    // ClientKey = HMAC(StoredKey, AuthMessage)
    const client_key = hmacSha256(&stored_key, auth_message);
    // ClientSignature = HMAC(ClientKey, AuthMessage)
    const client_signature = hmacSha256(&client_key, auth_message);
    // ClientProof = ClientKey XOR ClientSignature
    var computed_proof: [32]u8 = undefined;
    for (0..32) |i| {
        computed_proof[i] = client_key[i] ^ client_signature[i];
    }
    // Decode hex proof from client
    var decoded_proof: [32]u8 = undefined;
    hexToBytes(&decoded_proof, client_proof) catch return false;
    return std.mem.eql(u8, &computed_proof, &decoded_proof);
}

/// Generate server signature for SCRAM-SHA-256 final message.
pub fn generateScramServerSignature(server_key: [32]u8, auth_message: []const u8) [32]u8 {
    return hmacSha256(&server_key, auth_message);
}

/// Build the ServerFirst message: "r=<nonce>,s=<salt_hex>,i=<iterations>"
pub fn buildScramServerFirst(
    client_nonce: []const u8,
    server_nonce: []const u8,
    salt: []const u8,
    iterations: u32,
    buf: []u8,
) ?[]const u8 {
    var pos: usize = 0;

    const needed = 2 + client_nonce.len + server_nonce.len + 3 + salt.len * 2 + 4 + 10;
    if (buf.len < needed) return null;

    buf[pos..][0..2].* = "r=".*;
    pos += 2;
    @memcpy(buf[pos..][0..client_nonce.len], client_nonce);
    pos += client_nonce.len;
    @memcpy(buf[pos..][0..server_nonce.len], server_nonce);
    pos += server_nonce.len;
    buf[pos] = ',';
    pos += 1;
    buf[pos..][0..2].* = "s=".*;
    pos += 2;
    for (salt) |b| {
        buf[pos] = hexChar(b >> 4);
        pos += 1;
        buf[pos] = hexChar(b & 0x0f);
        pos += 1;
    }
    buf[pos] = ',';
    pos += 1;
    buf[pos..][0..2].* = "i=".*;
    pos += 2;
    const int_str = std.fmt.bufPrint(buf[pos..], "{d}", .{iterations}) catch return null;
    pos += int_str.len;

    return buf[0..pos];
}

/// Build the ServerFinal message: "v=<server_signature_hex>"
pub fn buildScramServerFinal(server_signature: [32]u8, buf: []u8) ?[]const u8 {
    if (buf.len < 66) return null;
    buf[0..2].* = "v=".*;
    for (server_signature, 0..) |b, i| {
        buf[2 + i * 2] = hexChar(b >> 4);
        buf[2 + i * 2 + 1] = hexChar(b & 0x0f);
    }
    return buf[0..66];
}

/// Build the auth message for SCRAM verification.
/// auth_message = client-first-bare + "," + server-first + "," + client-final-without-proof
pub fn buildScramAuthMessage(
    client_first_bare: []const u8,
    server_first: []const u8,
    client_final_without_proof: []const u8,
    buf: []u8,
) ?[]const u8 {
    return std.fmt.bufPrint(buf, "{s},{s},{s}", .{
        client_first_bare,
        server_first,
        client_final_without_proof,
    }) catch null;
}

/// Generate a random nonce for SCRAM authentication.
pub fn generateScramNonce(io: std.Io, buf: []u8) void {
    io.random(buf);
}

// ─── Internal crypto helpers ───────────────────────────────────────

fn pbkdf2Sha256(password: []const u8, salt: []const u8, iterations: u32) [32]u8 {
    var result: [32]u8 = undefined;
    crypto.pwhash.pbkdf2(&result, password, salt, iterations, crypto.auth.hmac.sha2.HmacSha256) catch unreachable;
    return result;
}

fn hmacSha256(key: []const u8, data: []const u8) [32]u8 {
    var h = crypto.auth.hmac.sha2.HmacSha256.init(key);
    h.update(data);
    var result: [32]u8 = undefined;
    h.final(&result);
    return result;
}

fn hexToBytes(out: []u8, hex: []const u8) !void {
    if (hex.len != out.len * 2) return error.InvalidLength;
    for (0..out.len) |i| {
        const hi = hexToNibble(hex[i * 2]) catch return error.InvalidHex;
        const lo = hexToNibble(hex[i * 2 + 1]) catch return error.InvalidHex;
        out[i] = (@as(u8, hi) << 4) | @as(u8, lo);
    }
}

fn hexToNibble(c: u8) !u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => return error.InvalidHex,
    };
}

fn hexChar(nibble: u8) u8 {
    return "0123456789abcdef"[nibble];
}

// ─── Tests ─────────────────────────────────────────────────────────

test "computeMD5Password" {
    const username = "postgres";
    const password = "password";
    const salt = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const result = computeMD5Password(username, password, salt);
    try std.testing.expectEqual(@as(usize, 35), result.len);
    try std.testing.expectEqualStrings("md5", result[0..3]);
}

test "verifyMD5Password" {
    const username = "postgres";
    const password = "password";
    const salt = [_]u8{ 0xAA, 0xBB, 0xCC, 0xDD };
    const hash = computeMD5Password(username, password, salt);
    try std.testing.expect(verifyMD5Password(username, password, salt, &hash));
    try std.testing.expect(!verifyMD5Password(username, "wrong", salt, &hash));
    try std.testing.expect(!verifyMD5Password(username, password, salt, "short"));
    try std.testing.expect(!verifyMD5Password(username, password, salt, ""));
}

test "generateScramCredentials determinism" {
    const password = "password";
    const salt = "0102030405060708";
    const creds1 = generateScramCredentials(password, salt, 4096);
    const creds2 = generateScramCredentials(password, salt, 4096);
    try std.testing.expectEqual(creds1.salted_password, creds2.salted_password);
    try std.testing.expectEqual(creds1.stored_key, creds2.stored_key);
    try std.testing.expectEqual(creds1.server_key, creds2.server_key);
}

test "pbkdf2Sha256 basic" {
    const result = pbkdf2Sha256("password", "salt", 1);
    try std.testing.expectEqual(@as(usize, 32), result.len);
}

test "pbkdf2Sha256 determinism" {
    const r1 = pbkdf2Sha256("test", "salt", 1000);
    const r2 = pbkdf2Sha256("test", "salt", 1000);
    try std.testing.expectEqual(r1, r2);
}

test "hmacSha256 basic" {
    const result = hmacSha256("key", "message");
    try std.testing.expectEqual(@as(usize, 32), result.len);
}

test "hmacSha256 determinism" {
    const r1 = hmacSha256("key", "data");
    const r2 = hmacSha256("key", "data");
    try std.testing.expectEqual(r1, r2);
}

test "hmacSha256 different keys produce different results" {
    const r1 = hmacSha256("key1", "data");
    const r2 = hmacSha256("key2", "data");
    try std.testing.expect(!std.mem.eql(u8, &r1, &r2));
}

test "hexToBytes valid" {
    var out: [4]u8 = undefined;
    try hexToBytes(&out, "01020304");
    try std.testing.expectEqualSlices(u8, &[_]u8{ 1, 2, 3, 4 }, &out);
}

test "hexToBytes uppercase" {
    var out: [2]u8 = undefined;
    try hexToBytes(&out, "FFAA");
    try std.testing.expectEqualSlices(u8, &[_]u8{ 0xFF, 0xAA }, &out);
}

test "hexToBytes invalid length" {
    var out: [2]u8 = undefined;
    try std.testing.expectError(error.InvalidLength, hexToBytes(&out, "01"));
}

test "hexToBytes invalid hex" {
    var out: [1]u8 = undefined;
    try std.testing.expectError(error.InvalidHex, hexToBytes(&out, "ZZ"));
}

test "generateScramCredentials different salts produce different results" {
    const creds1 = generateScramCredentials("password", "salt1", 4096);
    const creds2 = generateScramCredentials("password", "salt2", 4096);
    try std.testing.expect(!std.mem.eql(u8, &creds1.salted_password, &creds2.salted_password));
    try std.testing.expect(!std.mem.eql(u8, &creds1.stored_key, &creds2.stored_key));
    try std.testing.expect(!std.mem.eql(u8, &creds1.server_key, &creds2.server_key));
}

test "verifyScramClientProof valid" {
    const password = "password";
    const salt = "0102030405060708";
    const iterations: u32 = 4096;
    const creds = generateScramCredentials(password, salt, iterations);

    const client_first_bare = "n=user,r=clientnonce";
    const server_first = "r=clientnonce123,s=0102030405060708,i=4096";
    const client_final_without_proof = "c=biws,r=clientnonce123";

    var auth_msg_buf: [256]u8 = undefined;
    const auth_msg = buildScramAuthMessage(client_first_bare, server_first, client_final_without_proof, &auth_msg_buf).?;

    // Compute client proof matching verifyScramClientProof's algorithm
    const client_key = hmacSha256(&creds.stored_key, auth_msg);
    const client_signature = hmacSha256(&client_key, auth_msg);
    var proof: [32]u8 = undefined;
    for (0..32) |i| {
        proof[i] = client_key[i] ^ client_signature[i];
    }

    // Convert to hex
    const proof_hex = std.fmt.bytesToHex(&proof, .lower);

    try std.testing.expect(verifyScramClientProof(creds.stored_key, auth_msg, &proof_hex));
}

test "verifyScramClientProof invalid proof" {
    const stored_key = [_]u8{0xaa} ** 32;
    const auth_msg = "some auth message";
    const proof_hex = "0000000000000000000000000000000000000000000000000000000000000000";
    try std.testing.expect(!verifyScramClientProof(stored_key, auth_msg, proof_hex));
}

test "generateScramServerSignature" {
    const server_key = [_]u8{0xbb} ** 32;
    const auth_msg = "test auth message";
    const sig = generateScramServerSignature(server_key, auth_msg);
    try std.testing.expectEqual(@as(usize, 32), sig.len);

    // Verify it's deterministic
    const sig2 = generateScramServerSignature(server_key, auth_msg);
    try std.testing.expectEqual(sig, sig2);
}

test "buildScramServerFirst" {
    var buf: [128]u8 = undefined;
    const salt = [_]u8{ 0x01, 0x02, 0x03, 0x04 };
    const result = buildScramServerFirst("client123", "server456", &salt, 4096, &buf);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("r=client123server456,s=01020304,i=4096", result.?);
}

test "buildScramServerFirst buffer too small" {
    var buf: [10]u8 = undefined;
    const salt = [_]u8{ 0x01, 0x02 };
    const result = buildScramServerFirst("verylongclientnonce", "server", &salt, 4096, &buf);
    try std.testing.expect(result == null);
}

test "buildScramServerFinal" {
    var buf: [72]u8 = undefined;
    const sig = [_]u8{0xcc} ** 32;
    const result = buildScramServerFinal(sig, &buf);
    try std.testing.expect(result != null);
    try std.testing.expect(result.?.len == 66); // "v=" + 64 hex chars
}

test "buildScramAuthMessage" {
    var buf: [256]u8 = undefined;
    const result = buildScramAuthMessage("client_bare", "server_first", "client_final", &buf);
    try std.testing.expect(result != null);
    try std.testing.expectEqualStrings("client_bare,server_first,client_final", result.?);
}

test "hexChar" {
    try std.testing.expectEqual(@as(u8, '0'), hexChar(0));
    try std.testing.expectEqual(@as(u8, '9'), hexChar(9));
    try std.testing.expectEqual(@as(u8, 'a'), hexChar(10));
    try std.testing.expectEqual(@as(u8, 'f'), hexChar(15));
}

test "generateSalt fills buffer with random bytes" {
    const zio = @import("zio");
    const rt = try zio.Runtime.init(std.testing.allocator, .{});
    defer rt.deinit();
    const io = rt.io();

    const salt1 = generateSalt(io);
    const salt2 = generateSalt(io);
    try std.testing.expectEqual(@as(usize, 4), salt1.len);
    // Two random salts should differ (probabilistically)
    try std.testing.expect(!std.mem.eql(u8, &salt1, &salt2));
}

test "generateScramNonce fills buffer" {
    const zio = @import("zio");
    const rt = try zio.Runtime.init(std.testing.allocator, .{});
    defer rt.deinit();
    const io = rt.io();

    var buf1: [32]u8 = @splat(0);
    var buf2: [32]u8 = @splat(0);
    generateScramNonce(io, &buf1);
    generateScramNonce(io, &buf2);
    // Should not be all zeros
    var nonzero1: usize = 0;
    var nonzero2: usize = 0;
    for (buf1) |b| {
        if (b != 0) nonzero1 += 1;
    }
    for (buf2) |b| {
        if (b != 0) nonzero2 += 1;
    }
    try std.testing.expect(nonzero1 > 16);
    try std.testing.expect(nonzero2 > 16);
    // Two random nonces should differ
    try std.testing.expect(!std.mem.eql(u8, &buf1, &buf2));
}

test "buildScramAuthMessage buffer too small" {
    var buf: [10]u8 = undefined;
    const result = buildScramAuthMessage("long_client_bare", "server", "final", &buf);
    try std.testing.expect(result == null);
}
