const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = @import("Reader.zig");
const Request = @import("Reqeust.zig");
const eql = std.mem.eql;
const log = std.log;
const posix = std.posix;
const net = std.net;

const Client = @This();


const MAX_BYTES = 10 * 1024;
const response_isprime_true = "{\"method\":\"isPrime\",\"prime\":true}\n";
const response_isprime_false = "{\"method\":\"isPrime\",\"prime\":false}\n";

socket: posix.socket_t,
address: net.Address,
idx: u32,

pub fn handle(client: Client, allocator: Allocator) void {
    const socket = client.socket;

    var req_idx: u64 = 0;

    defer {
        log.info("closing connection to client {}, handled {} requests", .{client.idx, req_idx});
        posix.close(socket);
    }


    log.info("client {} connected", .{client.address});

    var buffer: [MAX_BYTES]u8 = .{0} ** MAX_BYTES;
    var reader = Reader{.buf = &buffer, .socket = socket};

    while (true) : (req_idx += 1) {
        

        // log.info("waiting for request...", .{});
        const request = reader.readMessage() catch |err| {
            if (err != error.Closed) log.err("error reading: {}", .{err}); 
            return;
        };

        const maybe_parsed = std.json.parseFromSlice(Request, allocator, request, .{
            .ignore_unknown_fields = true
        });

        if (maybe_parsed) |parsed| {
            defer parsed.deinit();


            if (!eql(u8, "isPrime", parsed.value.method)) {

                log.debug("c{}, r{}, sending malformed request {s}, does not contain isPrime", .{
                    client.idx, req_idx, request
                });
                write(socket, request) catch |err| {
                    log.err("failed to send malformed response: {s}, err: {}", .{request, err});
                    return;
                };

                return;
            }

            switch (parsed.value.number) {
                .integer => |number| {

                    if (isPrime(@intCast(number))) {

                        const response = response_isprime_true;

                        log.debug("c{}, r{}: request = {s}, response = {s}", .{
                            client.idx, req_idx, request, response
                        });

                        write(socket, response) catch |err| {
                            log.err("c{}, r{}: error writing correct response: {s}, request: {s}, err: {}", .{
                                client.idx, req_idx, response, request, err
                            });
                            return;
                        };

                    } else {

                        const response = response_isprime_false;

                        log.debug("c{}, r{}: request = {s}, response = {s}", .{
                            client.idx, req_idx, request, response
                        });

                        write(socket, response) catch |err| {
                            log.err("c{}, r{}: error writing correct response: {s}, request: {s}, err: {}", .{
                                client.idx, req_idx, response, request, err
                            });
                            return;
                        };
                    }

                },
                .float => {
                    
                    const response = response_isprime_false;

                    log.debug("c{}, r{}: request = {s}, response = {s}", .{
                        client.idx, req_idx, request, response
                    });
                    write(socket, response) catch |err| {
                        log.err("c{}, r{}: error writing correct response: {s}, request: {s}, err: {}", .{
                            client.idx, req_idx, response, request, err
                        });
                        return;
                    };

                }, 

                // TODO: send back malformed request
                else => {
                    log.err("FUUUUUUCK", .{});
                    return;
                },
            }



        } else |_| {
            log.info("sending malformed request: {s}", .{request});
            write(socket, request) catch |err| {
                log.err("failed to send malformed response: {}", .{err});
                return;
            };

            return;
        }

    
    }

}

fn write(socket: posix.socket_t, msg: []const u8) !void {
    var pos: usize = 0;

    while (pos < msg.len) {
        const written = try posix.write(socket, msg);

        if (written == 0) return error.Closed;

        pos += written;
    }
}

fn isPrime(n: i32) bool {

    if (n <= 1) return false;

    const max_check: usize = @intFromFloat(@floor(@sqrt(@as(f32, @floatFromInt(n)))));

    const x: usize = @intCast(n);

    for (2..(max_check + 1)) |d| {

        if (x % d == 0) return false;
    }

    return true;

}
