const std = @import("std");

const instruction = "mul(";
const dl1 = ",";
const dl2 = ")";

// Find the first occurrence of sub buffer find in buffer buff.
fn buff_find(buff: []const u8, find: []const u8) i64 {
    var i_find: usize = 0;
    for (0..buff.len) |i_buff| {
        if (buff[i_buff] == find[i_find]) {
            // std.debug.print("{d} {c}\n", .{ i_buff, buff[i_buff] });
            i_find += 1;
        } else {
            i_find = 0;
        }

        if (i_find == find.len) {
            return @as(i64, @intCast(i_buff));
        }
    }
    return -1;
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

    var sum: i64 = 0;
    var buff = file_buff;

    var i_find: i64 = undefined;
    while (true) {
        i_find = buff_find(buff, instruction);
        if (i_find == -1) break;
        buff = buff[@as(usize, @intCast(i_find + 1))..];

        i_find = buff_find(buff, dl1);
        if (i_find == -1) continue;

        const tkn1_i = @as(usize, @intCast(i_find));
        var num1: i64 = undefined;
        // std.debug.print("{s} {s}\n", .{ buff, buff[0..tkn1_i] });
        if (std.fmt.parseInt(i64, buff[0..tkn1_i], 10)) |num| {
            num1 = num;
        } else |_| {
            continue;
        }

        buff = buff[(tkn1_i + 1)..];

        i_find = buff_find(buff, dl2);
        if (i_find == -1) continue;

        const tkn2_i = @as(usize, @intCast(i_find));
        var num2: i64 = undefined;
        // std.debug.print("{s} {s}\n", .{ buff, buff[0..tkn2_i] });
        if (std.fmt.parseInt(i64, buff[0..tkn2_i], 10)) |num| {
            num2 = num;
        } else |_| {
            continue;
        }

        buff = buff[tkn2_i..];
        // std.debug.print("{s}\n", .{buff});

        sum += num1 * num2;
    }

    std.debug.print("{d}\n", .{sum});
}
