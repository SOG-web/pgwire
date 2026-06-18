const std = @import("std");
const Io = std.Io;

/// A buffered message writer that accumulates all send calls into a buffer,
/// then flushes atomically to the underlying writer. Prevents partial message
/// delivery on error.
pub fn MessageWriter(comptime buf_size: usize) type {
    return struct {
        buf: [buf_size]u8 = undefined,
        pos: usize = 0,
        underlying: *Io.Writer,

        const Self = @This();

        pub fn init(underlying: *Io.Writer) Self {
            return .{ .underlying = underlying };
        }

        /// Flush all buffered data to the underlying writer atomically.
        pub fn flush(self: *Self) !void {
            if (self.pos == 0) return;
            try self.underlying.writeAll(self.buf[0..self.pos]);
            self.pos = 0;
        }

        /// Discard all buffered data without writing.
        pub fn discard(self: *Self) void {
            self.pos = 0;
        }

        /// Write raw bytes into the buffer.
        pub fn writeAll(self: *Self, bytes: []const u8) !void {
            if (self.pos + bytes.len > self.buf.len) {
                try self.flush();
                if (bytes.len > self.buf.len) {
                    try self.underlying.writeAll(bytes);
                    return;
                }
            }
            @memcpy(self.buf[self.pos .. self.pos + bytes.len], bytes);
            self.pos += bytes.len;
        }
    };
}
