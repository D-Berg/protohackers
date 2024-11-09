const std = @import("std");
const net = std.net;
const posix = std.posix;


const log = std.log;

pub const std_options = .{
    .log_level = .debug
};

const MAX_BYTES = 2048;

const Client = struct {
    socket: posix.socket_t,
    address: net.Address,

    fn handle(client: Client) void {
        const socket = client.socket;
        var buffer: [MAX_BYTES]u8 = [_]u8{0} ** MAX_BYTES;

        defer {
            log.info("closing connection to client {}", .{client.address});
            posix.close(socket);
        }


        log.info("client {} connected", .{client.address});

        while (true) {

            const read_len = posix.read(socket, &buffer) catch |err| {
                log.err("error reading: {}", .{err});
                return;
            };

            log.debug("read {} bytes", .{read_len});
            if (read_len == 0) return;

            log.debug("{s}", .{buffer[0..read_len]});

            write(socket, buffer[0..read_len]) catch |err| {
                log.err("error writing: {}", .{err});
            };
        }

    }

};


fn write(socket: posix.socket_t, msg: []const u8) !void {
    var pos: usize = 0;

    while (pos < msg.len) {
        const written = try posix.write(socket, msg);

        if (written == 0) return error.Closed;

        pos += written;
    }
}

pub fn main() !void {

    const host = [4]u8{ 0, 0, 0, 0 };
    const port = 8000;
    const addr = net.Address.initIp4(host, port);

    const listener = try std.posix.socket(
        addr.any.family, 
        std.posix.SOCK.STREAM,
        std.posix.IPPROTO.TCP
    );
    defer posix.close(listener);

    try posix.setsockopt(listener, posix.SOL.SOCKET, posix.SO.REUSEADDR, &std.mem.toBytes(@as(c_int, 1)));
    try posix.bind(listener, &addr.any, addr.getOsSockLen());
    try posix.listen(listener, 128);

    log.info("Listening on {}", .{addr});


    while (true) {

        var client_addr: net.Address = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = posix.accept(listener, &client_addr.any, &client_addr_len, 0) catch |err| {
            log.err("error accept: {}", .{err});
            continue;
        };

        const client = Client{ .socket = socket, .address = client_addr};
        const thread = try std.Thread.spawn(.{}, Client.handle, .{client});
        thread.detach();

    }

}


