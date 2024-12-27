const std = @import("std");

const Allocator = std.mem.Allocator;

const Rows = 7;
const Columns = 5;
const Height = usize;

const Lock = struct {
    schematic: [Columns]Height,
    uses_key: ?*const Key,

    /// Returns whether the given key schematic aligns with this lock schematic.
    fn matches(self: Lock, key: *const Key) bool {
        for (0..Columns) |i| {
            const sum: Height, const overflow: u1 = @addWithOverflow(
                self.schematic[i],
                key.schematic[i],
            );

            if ((overflow == @as(u1, 1)) or (sum > Rows)) return false;
        }

        return true;
    }
};

const Key = struct {
    schematic: [Columns]Height,
};

fn parse(ally: Allocator, input: []const u8) !struct { []Lock, []Key } {
    var lock_array = try std.ArrayList(Lock).initCapacity(ally, 1024);
    var key_array = try std.ArrayList(Key).initCapacity(ally, 1024);

    var dtype: ?enum { Lock, Key } = null;

    const Character = enum(u8) { Filled = '#', Empty = '.' };
    const filled: []const u8 = &[_]u8{@intFromEnum(Character.Filled)} ** Columns;

    var buffer: [Columns]Height = undefined;

    var lineIt = std.mem.splitScalar(u8, input, '\n');
    while (lineIt.next()) |line| {
        if (line.len == 0) {
            // Key/Lock descriptor ended, push it in.
            switch (dtype.?) {
                .Lock => {
                    var lock = Lock{ .schematic = undefined, .uses_key = null };
                    @memcpy(&lock.schematic, &buffer);
                    try lock_array.append(lock);
                },
                .Key => {
                    var key = Key{ .schematic = undefined };
                    @memcpy(&key.schematic, &buffer);
                    try key_array.append(key);
                },
            }

            dtype = null;
            continue;
        }

        if (line.len != Columns) @panic("Invalid input");

        if (dtype == null) {
            // Determine descriptor type based off the first row.
            if (std.mem.order(u8, line, filled) == .eq) {
                dtype = .Lock;
                @memset(&buffer, 1);
            } else {
                dtype = .Key;
                @memset(&buffer, 0);
            }
            continue;
        }

        // Fill heights.
        for (line, 0..) |c, i| switch (@as(Character, @enumFromInt(c))) {
            .Filled => buffer[i] += 1,
            .Empty => {},
        };
    }

    return .{ try lock_array.toOwnedSlice(), try key_array.toOwnedSlice() };
}

fn process(ally: Allocator, buff: []const u8) !usize {
    const locks, const keys = try parse(ally, buff);

    defer {
        ally.free(locks);
        ally.free(keys);
    }

    {
        // Print locks and keys.
        for (locks) |lock| {
            std.debug.print("Lock: {any}\n", .{lock.schematic});
        }
        for (keys) |key| {
            std.debug.print("Key: {any}\n", .{key.schematic});
        }
    }

    var matches: usize = 0;
    for (0..keys.len) |key_i| {
        const key_ptr = &keys[key_i];

        for (0..locks.len) |lock_i| {
            var lock_ptr = &locks[lock_i];
            if (!lock_ptr.matches(key_ptr)) continue;

            std.debug.print("Lock: {any}, matches key: {any}\n", .{ lock_ptr.schematic, key_ptr.schematic });
            matches += 1;
        }

        // if (match_key(locks, &keys[key_i], 0)) {
        //     matches += 1;
        // }
    }

    // {
    //     // Print lock-key pairs.
    //
    //     std.debug.print("\nAfter matching:\n", .{});
    //     for (locks) |lock| {
    //         std.debug.print("Lock: {any}, uses key: ", .{lock.schematic});
    //         if (lock.uses_key) |key_ptr| {
    //             std.debug.print("{any}\n", .{key_ptr.schematic});
    //         } else {
    //             std.debug.print("null\n", .{});
    //         }
    //     }
    // }

    return matches;
}

// fn match_key(locks: []Lock, key_ptr: *const Key, min_lock_i: usize) bool {
//     for (0..locks.len) |lock_i| {
//         if (lock_i < min_lock_i) continue;
//
//         var lock_ptr = &locks[lock_i];
//         if (!lock_ptr.matches(key_ptr)) continue;
//
//         if ((lock_ptr.uses_key == null) or
//             (match_key(locks, lock_ptr.uses_key.?, lock_i)))
//         {
//             lock_ptr.uses_key = key_ptr;
//             return true;
//         }
//     }
//
//     return false;
// }

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const ally = gpa.allocator();

    defer {
        if (gpa.deinit() == .leak) {
            @panic("Not all allocated memory was freed");
        }
    }

    // Process command-line arguments passed to main.
    const args = try std.process.argsAlloc(ally);
    defer std.process.argsFree(ally, args);

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
    const file_buff = try file.readToEndAlloc(ally, stat.size);
    defer ally.free(file_buff);

    // Process the file.
    const count = try process(ally, file_buff);
    std.debug.print("{d}\n", .{count});
}
