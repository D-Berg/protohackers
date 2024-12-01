const std = @import("std");
const posix = std.posix;
const log = std.log;
const Reader = @This();

buf: []u8,
pos: usize = 0,
start: usize = 0,
socket: posix.socket_t,


pub fn readMessage(self: *Reader) ![]u8 {

    var buf = self.buf;

    while (true) {

        if (self.bufferedMessage()) |msg| {
            return msg;
        }

        const pos = self.pos;

        const n = try posix.read(self.socket, buf[pos..]);

        if (n == 0) return error.Closed;
    
        self.pos = pos + n;
    }
}

/// Check if message start with { and ends with }
fn bufferedMessage(self: *Reader) ?[]u8 {
    const buf = self.buf;
    const pos = self.pos;
    const start = self.start;

    std.debug.assert(pos >= start);

    for (start..pos) |newline_idx| {

        if (buf[newline_idx] == '\n') {

            self.start = newline_idx + 1;
            return buf[start..newline_idx];

        }
    }

    if (pos == buf.len - 1) log.warn("buffer full", .{});

    return null;

}

