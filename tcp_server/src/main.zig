const Server = @import("root.zig").Server;

pub fn main() !void {
    const server = try Server.init("127.0.0.1", 8000);
    defer server.deinit();

    try server.listen();
}
