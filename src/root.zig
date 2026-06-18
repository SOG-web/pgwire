const std = @import("std");

pub const types = @import("types.zig");
pub const server = struct {
    pub const message = @import("server/message.zig");
    pub const connection = @import("server/connection.zig");
};
