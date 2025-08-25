/// yayayaya
const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log;
const assert = std.debug.assert;

pub fn handle(
    arena: Allocator,
    in: *std.Io.Reader,
    out: *std.Io.Writer,
) !void {
    while (true) {
        var message_buf: [4096]u8 = undefined;
        var message_writer = std.Io.Writer.fixed(&message_buf);
        log.info("waiting for req...", .{});
        defer log.info("finished handling req", .{});

        const n = in.streamDelimiter(&message_writer, '\n') catch |err| {
            switch (err) {
                error.EndOfStream => log.info("stream finished", .{}),
                else => |reason| {
                    log.err("failed to read: {t}", .{reason});
                    // return err;
                },
            }
            std.log.info("stopped reading, flusshing", .{});
            try out.flush();
            return;
        };
        log.info("read {d} bytes", .{n});
        const delim = try in.takeByte();
        assert(delim == '\n');
        const msg = message_buf[0..n];

        log.info("recieved req: {s}", .{msg});

        const req = Request.fromJSON(arena, msg) catch |err| {
            log.err("invalid req: '{s}', reason: {t}", .{ msg, err });
            try out.print("Invalid request", .{});
            try out.flush();
            return;
        };

        if (!std.mem.eql(u8, "isPrime", req.method)) {
            log.err("invalid req: '{s}', wrong method: {s}", .{ msg, req.method });
            try out.print("INVALIIDD\n", .{});
            try out.flush();
            return;
        }

        // log.info("req = {f}", .{req});
        log.info("checking if {f} is prime...", .{req.number});

        const is_prime = req.isReqPrime();
        log.info("finished calculating {f}, isPrime: {}", .{ req.number, is_prime });

        const response = Response{ .method = "isPrime", .prime = is_prime };

        const resp_str = try response.toJSONAlloc(arena);

        log.info("responding with: '{s}'", .{resp_str});

        try out.print("{s}\n", .{resp_str});
        try out.flush();
    }
}

const Request = struct {
    method: []const u8,
    number: union(enum) {
        int: i64,
        float: f64,
        big: std.math.big.int.Managed,

        pub fn format(
            self: @This(),
            writer: *std.Io.Writer,
        ) std.Io.Writer.Error!void {
            switch (self) {
                inline .int, .float => |val| try writer.print("{d}", .{val}),
                .big => |big| try writer.print("{f}", .{big}),
            }
        }
    },

    pub fn format(
        self: @This(),
        writer: *std.Io.Writer,
    ) std.Io.Writer.Error!void {
        try writer.writeAll("{");
        try writer.print(" .method = \"{s}\", .number = {d:2} ", .{ self.method, self.number });
        try writer.writeAll("}");
        try writer.flush();
    }

    fn fromJSON(arena: Allocator, json_slice: []const u8) !Request {
        const parsed: std.json.Parsed(std.json.Value) = std.json.parseFromSlice(
            std.json.Value,
            arena,
            json_slice,
            .{ .ignore_unknown_fields = true },
        ) catch |err| {
            log.err("Failed to parse json: {t}", .{err});
            return err;
        };

        var req: Request = undefined;
        if (parsed.value.object.get("method")) |method_obj| {
            switch (method_obj) {
                .string => |method| req.method = method,
                else => {
                    return error.IncorrectMethodType;
                },
            }
        } else {
            return error.MissingMethodField;
        }

        if (parsed.value.object.get("number")) |number_obj| {
            switch (number_obj) {
                .integer => |int| req.number = .{ .int = int },
                .float => |float| req.number = .{ .float = float },
                .number_string => |big_str| {
                    var big_num = try std.math.big.int.Managed.init(arena);
                    try big_num.setString(10, big_str);
                    req.number = .{ .big = big_num };
                },
                else => {
                    return error.IncorrectNumberType;
                },
            }
        } else {
            return error.MissingNumberFiled;
        }

        return req;
    }

    fn isReqPrime(self: *const Request) bool {
        switch (self.number) {
            .float => return false,
            .int => |int| return isPrime(int),
            .big => |big| {
                _ = big;
                return false;
            },
        }
    }
};

fn isPrime(num: i64) bool {
    if (num <= 1) return false;

    const u_num: u64 = @intCast(num);

    if (u_num == 2) return true;
    if (u_num == 3) return true;
    if (u_num == 5) return true;

    if (u_num == 2) return true;
    if (u_num % 2 == 0) return false;
    if (u_num % 3 == 0) return false;

    var i: u64 = 5;
    while (i * i <= u_num) : (i += 2) {
        if (u_num % i == 0) return false;
    }

    return true;
}

const Response = struct {
    method: []const u8,
    prime: bool,

    fn toJSONAlloc(self: *const Response, gpa: Allocator) ![]const u8 {
        var allo_writer: std.Io.Writer.Allocating = .init(gpa);
        errdefer allo_writer.deinit();

        const w = &allo_writer.writer;

        try w.writeAll("{");
        try w.print("\"method\":\"{s}\",\"prime\":{}", .{ self.method, self.prime });
        try w.writeAll("}");

        return try allo_writer.toOwnedSlice();
    }
};

test "jsoon" {
    std.testing.log_level = .debug;
    const gpa = std.testing.allocator;
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const msg =
        \\{"method":"isPrime","number":40958683}
        \\{"method":"isPrime","number":79696290}
        \\
    ;
    var out_buf: [512]u8 = undefined;

    var in = std.Io.Reader.fixed(msg[0..]);
    var out = std.Io.Writer.fixed(&out_buf);

    try handle(arena, &in, &out);

    std.debug.print("{s}\n", .{out.buffered()});
}

test "malformed" {
    std.testing.log_level = .debug;
    const gpa = std.testing.allocator;
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const msg =
        \\{"method":"isPrime","number":"6377774"}
        \\
    ;
    var out_buf: [512]u8 = undefined;

    var in = std.Io.Reader.fixed(msg[0..]);
    var out = std.Io.Writer.fixed(&out_buf);

    try handle(arena, &in, &out);

    std.debug.print("{s}\n", .{out.buffered()});
}

test "big num" {
    std.testing.log_level = .debug;
    const gpa = std.testing.allocator;
    var arena_impl = std.heap.ArenaAllocator.init(gpa);
    defer arena_impl.deinit();

    const arena = arena_impl.allocator();

    const msg =
        \\{"method":"isPrime","number":90998271523853722729328814612620302406299353286017553178,"bignumber":true}
        \\
    ;
    var out_buf: [512]u8 = undefined;

    var in = std.Io.Reader.fixed(msg[0..]);
    var out = std.Io.Writer.fixed(&out_buf);

    try handle(arena, &in, &out);

    std.debug.print("{s}\n", .{out.buffered()});
}

test "calc prime" {
    try std.testing.expectEqual(true, isPrime(166631));
    try std.testing.expectEqual(false, isPrime(79696290.0));
    try std.testing.expectEqual(true, isPrime(40958683.0));
}
