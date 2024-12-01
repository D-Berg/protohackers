const std = @import("std");
const print = std.debug.print;
const net = std.net;
const posix = std.posix;
const eql = std.mem.eql;
const Allocator = std.mem.Allocator;
const Reader = @import("Reader.zig");
const Client = @import("Client.zig");
const Request = @import("Reqeust.zig");


const log = std.log;

pub const std_options = .{
    .log_level = .debug
};

pub fn main() !void {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

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

    var n_clients: u32 = 0;

    while (true) : (n_clients += 1){

        var client_addr: net.Address = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = posix.accept(listener, &client_addr.any, &client_addr_len, 0) catch |err| {
            log.err("error accept: {}", .{err});
            continue;
        };

        const client = Client{ .socket = socket, .address = client_addr, .idx = n_clients};
        const thread = try std.Thread.spawn(.{}, Client.handle, .{client, allocator});
        thread.detach();

    }

}

test "parse json" {

    const allocator = std.testing.allocator;
    const req = 
        \\{"method":"isPrime","number":"2134071"}\n
    ;

    const parsed = try std.json.parseFromSlice(Request, allocator, req, .{
        .ignore_unknown_fields = true
    });
    defer parsed.deinit();

    print("number = {}", .{parsed.value.number});

}
