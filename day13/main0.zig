const std = @import("std");

const Allocator = std.mem.Allocator;

const Patterns = std.StringHashMap(void);

const CheckerTag = enum(u2) {
    Unknown,
    Pass,
    Fail,
};

/// Returns a hash map that holds parsed
/// patterns and a buffer offset where designs start.
/// Free the returned hash map by calling deinit on it.
fn read_patterns(ally: Allocator, buff: []u8) !struct { ps: Patterns, seek: usize } {
    var ps = Patterns.init(ally);

    const seek = std.mem.indexOfScalar(u8, buff, '\n').?;
    var it = std.mem.tokenizeSequence(u8, buff[0..seek], ", ");
    while (it.next()) |token| {
        try ps.put(token, void{});
    }

    return .{ .ps = ps, .seek = seek + 2 };
}

fn displayable(design: []const u8, ps: *Patterns, ch: []CheckerTag, i: usize) !bool {
    switch (ch[i]) {
        .Fail => return false,
        .Pass => return true,
        .Unknown => {},
    }

    var r: usize = design.len;
    while (r > 0) : (r -= 1) {
        if (ps.get(design[0..r]) == null) continue;

        if ((r == design.len) or (try displayable(design[r..], ps, ch, i + r))) {
            try ps.put(design, void{});
            ch[i] = .Pass;
            return true;
        }
    }

    ch[i] = .Fail;
    return false;
}

fn process(ally: Allocator, buff: []u8) !usize {
    // Read patterns and seek the buffer to where designs start.
    const rp = try read_patterns(ally, buff);
    var ps: Patterns = rp.ps;
    const designs = buff[rp.seek..];

    // {
    //     std.debug.print("Patterns:\n", .{});
    //     var kit = ps.keyIterator();
    //     while (kit.next()) |key| {
    //         std.debug.print("{s}\n", .{key.*});
    //     }
    // }

    var count: usize = 0;
    var it = std.mem.tokenizeScalar(u8, designs, '\n');
    while (it.next()) |design| {
        const checker = try ally.alloc(CheckerTag, design.len);
        @memset(checker, CheckerTag.Unknown);

        count += @intFromBool(try displayable(design, &ps, checker, 0));
        ally.free(checker);
    }

    // {
    //     std.debug.print("\nNew Patterns:\n", .{});
    //     var kit = ps.keyIterator();
    //     while (kit.next()) |key| {
    //         std.debug.print("{s}\n", .{key.*});
    //     }
    // }

    return count;
}

pub fn main() !void {
    const pg_ally = std.heap.page_allocator;

    // Process command-line arguments passed to main.
    const args = try std.process.argsAlloc(pg_ally);
    defer std.process.argsFree(pg_ally, args);

    if (args.len < 2) {
        std.debug.print("Usage: {s} <input filename>\n", .{args[0]});
        return;
    }

    // Get passed input filename.
    const filename = args[1];
    std.debug.print("Reading file for input: {s}\n", .{filename});

    // Open the given filename as input file for reading.
    var file = try std.fs.cwd().openFile(filename, .{});
    defer file.close();

    const stat = try file.stat();
    const file_buff = try file.readToEndAlloc(pg_ally, stat.size);
    defer pg_ally.free(file_buff);

    // Process the file.
    const count = try process(pg_ally, file_buff);
    std.debug.print("{d}\n", .{count});
}
