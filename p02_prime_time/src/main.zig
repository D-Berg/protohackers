const std = @import("std");
const print = std.debug.print;
const net = std.net;
const posix = std.posix;
const eql = std.mem.eql;
const Allocator = std.mem.Allocator;


const log = std.log;

pub const std_options = .{
    .log_level = .debug
};

const MAX_BYTES = 1638400;


const response_isprime_true = "{\"method\":\"isPrime\",\"prime\":true}\n";
const response_isprime_false = "{\"method\":\"isPrime\",\"prime\":false}\n";

// {"number":90248357,"method":"isPrime"}\n{"method":"isPrime","number":38784983}

const Client = struct {
    socket: posix.socket_t,
    address: net.Address,

    fn handle(client: Client, allocator: Allocator) void {
        const socket = client.socket;
        var buffer: [MAX_BYTES]u8 = [_]u8{0} ** MAX_BYTES;

        defer {
            log.info("closing connection to client {}", .{client.address});
            posix.close(socket);
        }


        log.info("client {} connected", .{client.address});

        while (true) {

            log.info("waiting for request...", .{});
            const read_len = posix.read(socket, &buffer) catch |err| {
                log.err("error reading: {}", .{err});
                return;
            };

            log.debug("read {} bytes", .{read_len});
            if (read_len == 0) return;

            // log.debug("{s}", .{buffer[0..read_len]});

            var iterator = std.mem.splitSequence(u8, buffer[0..read_len], "\n");

            while (iterator.next()) |request| {

                if (request.len == 0) continue;

                log.debug("processing: {s}", .{request});

                const maybe_parsed = std.json.parseFromSlice(Request, allocator, request, .{});
                if (maybe_parsed) |parsed| {
                    defer parsed.deinit();

                    const number: i32 = blk: {
                        switch (parsed.value.number) {
                            .integer => |num| break :blk @intCast(num),
                            else => return,
                        }
                    };

                    if (!eql(u8, "isPrime", parsed.value.method)) {
                        
                        // log.debug("request {s} does not contain isPrime", .{request});

                        write(socket, request) catch |err| {
                            log.err("failed to sent malformed response: {}", .{err});
                            return;
                        };

                        return;
                    }

                    log.info("correct request", .{});

                    if (isPrime(number)) {

                        // log.debug("isprime = true", .{});
                        write(socket, response_isprime_true) catch |err| {
                            log.err("error writing correct response: {}", .{err});
                            return;
                        };

                    } else {

                        // log.debug("isprime = false", .{});
                        write(socket, response_isprime_false) catch |err| {
                            log.err("error writing correct response: {}", .{err});
                            return;
                        };
                    }


                } else |_| {
                    log.info("Malformed request: {s}", .{request});

                    write(socket, request) catch |err| {
                        log.err("failed to sent malformed response: {}", .{err});
                        return;
                    };

                    return;
                }


            }



        
        }

    }

};

fn isPrime(n: i32) bool {

    log.info("calculating if its a prime...", .{});

    if (n <= 1) return false;

    const max_check: usize = @intFromFloat(@floor(@sqrt(@as(f32, @floatFromInt(n)))));

    const x: usize = @intCast(n);

    for (2..(max_check + 1)) |d| {

        if (x % d == 0) return false;
    }

    return true;

}

fn write(socket: posix.socket_t, msg: []const u8) !void {
    var pos: usize = 0;

    while (pos < msg.len) {
        const written = try posix.write(socket, msg);

        if (written == 0) return error.Closed;

        pos += written;
    }
}

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


    while (true) {

        var client_addr: net.Address = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(net.Address);

        const socket = posix.accept(listener, &client_addr.any, &client_addr_len, 0) catch |err| {
            log.err("error accept: {}", .{err});
            continue;
        };

        const client = Client{ .socket = socket, .address = client_addr};
        const thread = try std.Thread.spawn(.{}, Client.handle, .{client, allocator});
        thread.detach();

    }

}


const Request = struct {
    method: []const u8,
    number: std.json.Value,
};

test "parse json" {

    const allocator = std.testing.allocator;
    const req = 
        \\{"method":"isPrime","number":"2134071"}
    ;

    const parsed = try std.json.parseFromSlice(Request, allocator, req, .{});
    defer parsed.deinit();

    print("number = {}", .{parsed.value.number});

}
