const std = @import("std");
const net = std.net;
const log = std.log;
const Connection = std.net.Server.Connection;

const MAX_BYTES = 2000;
var shutdown: bool = false;

pub fn main() !void {
    const host = [4]u8{ 0, 0, 0, 0 };
    const port = 8000;
    const addr = net.Address.initIp4(host, port);

    const socket = try std.posix.socket(
        addr.any.family, 
        std.posix.SOCK.STREAM, 
        std.posix.IPPROTO.TCP
    );

    const stream = net.Stream{ .handle = socket };
    defer stream.close(); // closes socket for us

    var server = try addr.listen(.{ .reuse_address = true });
    defer server.deinit();

    log.info("Server listening on {}", .{addr});


    while (true) {

        const connection = try server.accept();

        const handler = try std.Thread.spawn(.{}, run, .{connection});
        handler.detach();


    }

}

fn run(conn: Connection) !void {

    log.info("got connection from: {}", .{conn.address});

    defer {
        log.info("closing connection stream to {}", .{conn.address});
        conn.stream.close();
    }

    var buffer: [MAX_BYTES]u8 = [_]u8{0} ** MAX_BYTES;

    const reader = conn.stream.reader();
    const writer = conn.stream.writer();

    while (true) {
        const n_read_bytes = reader.read(&buffer) catch {
            log.info("lost connection to {}", .{conn.address});
            return;
        };

        if (n_read_bytes == 0) {
            log.info("recieved 0 bytes", .{});
            shutdown = true;
            return;
        }


        log.info("recieved {} bytes\n{s}", .{n_read_bytes, buffer});

        const n_sent_bytes = try writer.write(buffer[0..n_read_bytes]);
        log.info("sent back {} bytes", .{n_sent_bytes});
    }
}

