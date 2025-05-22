const std = @import("std");
const posix = std.posix;

const log = std.log.scoped(.Server);

pub const Server = struct {
    socket: posix.socket_t,
    address: std.net.Address,

    pub fn init(address_name: []const u8, port: u16) !Server {
        const address = try std.net.Address.parseIp(address_name, port);

        const tpe: u32 = posix.SOCK.STREAM;
        const protocol: u32 = posix.IPPROTO.TCP;

        const listener = try posix.socket(address.any.family, tpe, protocol);

        try posix.setsockopt(
            listener,
            posix.SOL.SOCKET,
            posix.SO.REUSEADDR,
            &std.mem.toBytes(@as(c_int, 1)),
        );
        try posix.bind(listener, &address.any, address.getOsSockLen());
        try posix.listen(listener, 128);

        return Server{ .socket = listener, .address = address };
    }

    pub fn deinit(server: *const Server) void {
        posix.close(server.socket);
        log.info("Closed server", .{});
    }

    pub fn listen(server: *const Server) !void {
        log.info("Listening on: {any}", .{server.address});
        while (true) {
            var client_address: std.net.Address = undefined;
            var client_address_len: posix.socklen_t = @sizeOf(std.net.Address);

            const socket = posix.accept(
                server.socket,
                &client_address.any,
                &client_address_len,
                0,
            ) catch |err| {
                log.err("Failed to accept: {}", .{err});
                continue;
            };
            defer posix.close(socket);

            log.info("Got connection from: {}", .{client_address});

            write(socket, "Hello and Goodbye\n") catch |err| {
                log.err(
                    "Failed to write to {}, err({s})",
                    .{ client_address, @errorName(err) },
                );
            };
        }
    }
};

fn write(socket: posix.socket_t, msg: []const u8) !void {
    var pos: usize = 0;
    var written: usize = 0;

    while (pos < msg.len) : (pos += written) {
        written = try posix.write(socket, msg[pos..]);
        if (written == 0) {
            return error.ClosedConnection;
        }
    }
}
