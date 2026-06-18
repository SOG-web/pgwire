const std = @import("std");

pub const types = @import("types.zig");
pub const server = struct {
    pub const message = @import("server/message.zig");
    pub const connection = @import("server/connection.zig");
    pub const auth = @import("server/auth.zig");
    pub const buffered = @import("server/buffered.zig");
};

test {
    _ = std.testing.refAllDecls(server);
}
