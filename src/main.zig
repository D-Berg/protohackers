const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const log = std.log;
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;

const Args = enum {
    smoke_test,
};

var stdout_buffer: [1024]u8 = undefined;
var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
const stdout = &stdout_writer.interface;

pub fn main() !void {
    const gpa, const is_debug = blk: {
        break :blk switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ debug_allocator.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = debug_allocator.deinit();
    };

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len == 1) {
        try stdout.print("Pass one of the following as args:\n", .{});
        inline for (@typeInfo(Args).@"enum".fields) |field| {
            try stdout.print("   {s}\n", .{field.name});
        }
        try stdout.flush();
    } else if (args.len == 2) {
        if (std.meta.stringToEnum(Args, args[1])) |handler| {
            switch (handler) {
                .smoke_test => try Server.listen(gpa, smoke_test_handler),
            }
        }
    }
}

fn smoke_test_handler(
    arena: Allocator,
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
) !void {
    _ = arena;

    var message_buffer: [4096]u8 = undefined;
    var message_writer = std.Io.Writer.fixed(&message_buffer);

    while (true) {
        const n = reader.stream(&message_writer, .limited(message_buffer.len)) catch |err| {
            log.info("Failed to read: {t}", .{err});
            try writer.flush();
            return;
        };

        log.debug("read {d} bytes", .{n});

        const message = message_writer.buffered();
        log.debug("recieved: {s}", .{message});
        try writer.writeAll(message);
        try writer.flush();

        _ = message_writer.consume(message.len);
    }
}

/// General purpose TCP Server
const Server = struct {
    const HandleFn = *const fn (arena: Allocator, reader: *std.Io.Reader, writer: *std.Io.Writer) anyerror!void;

    fn listen(gpa: Allocator, handle_fn: HandleFn) !void {
        const addr = try std.net.Address.parseIp("0.0.0.0", 6969);

        const listener = try std.posix.socket(addr.any.family, std.posix.SOCK.STREAM, std.posix.IPPROTO.TCP);
        defer std.posix.close(listener);

        try std.posix.setsockopt(
            listener,
            std.posix.SOL.SOCKET,
            std.posix.SO.REUSEADDR,
            &std.mem.toBytes(@as(c_int, 1)),
        );
        try std.posix.bind(listener, &addr.any, addr.getOsSockLen());
        try std.posix.listen(listener, 128);

        log.info("listening on {f}", .{addr});

        while (true) {
            var client_addr: std.net.Address = undefined;
            var client_addr_size: std.posix.socklen_t = @sizeOf(std.net.Address);
            const client_sock = try std.posix.accept(listener, &client_addr.any, &client_addr_size, 0);

            const thread = try std.Thread.spawn(.{}, handleConnection, .{
                gpa,
                Client{
                    .addr = client_addr,
                    .socket = client_sock,
                },
                handle_fn,
            });

            thread.detach();

            log.debug("client connected", .{});
        }

        std.debug.print("hello", .{});
    }

    fn handleConnection(gpa: Allocator, client: Client, handle_fn: HandleFn) !void {
        defer {
            std.posix.close(client.socket);
            log.info("connection closed", .{});
        }
        var read_buf: [256]u8 = undefined;
        var write_buf: [256]u8 = undefined;

        var stream = std.net.Stream{ .handle = client.socket };
        var stream_reader = stream.reader(read_buf[0..]);
        var stream_writer = stream.writer(write_buf[0..]);

        const reader = stream_reader.interface();
        const writer = &stream_writer.interface;

        try handle_fn(gpa, reader, writer);
    }
};

const Client = struct {
    socket: std.posix.socket_t,
    addr: std.net.Address,
};
