const std = @import("std");

const Allocator = std.mem.Allocator;
const FileMap = []u8;

/// Compact the file contents of the given dense file format map.
/// Returns the resulting checksum of the new file contents in the file map.
fn compact(ally: *const Allocator, fm: FileMap) !usize {
    if (fm.len == 0) return 0;

    var r_fid: usize = @divTrunc(fm.len, 2) - (1 - @mod(fm.len, 2));

    var l_i: usize = 1;
    var r_i: usize = fm.len - 1 - (1 - @mod(fm.len, 2));

    // Allocate a compressed file index map.
    var xfm = try ally.alloc(u8, fm.len);
    var xid = try ally.alloc(usize, fm.len);
    defer ally.free(xfm);
    defer ally.free(xid);

    for (0..fm.len) |i| {
        xfm[i] = 0;
    }

    xid[0] = 0;
    xfm[0] = fm[0] - '0';

    while (r_fid > 0) {
        l_i = 1;

        while (l_i < r_i) {
            // Check the current free space spot capacity.
            if (fm[l_i] >= fm[r_i]) {
                // Enough space available.
                fm[l_i] = fm[l_i] - fm[r_i] + '0';
                std.debug.print("Storing {d} at pos {d}\n", .{ r_fid, l_i / 2 + 1 });
                break;
            } else {
                // Not enough space available.
                l_i += 2;
            }
        } else {
            l_i = r_i;
            std.debug.print("Leaving {d} at pos {d}\n", .{ r_fid, l_i / 2 + 1 });
        }

        // Insert file into x.
        var x_i: usize = @divTrunc(l_i, 2) + 1;
        if (xfm[x_i] != 0) {
            // Already occupied, shift to allow for space after.
            for (0..fm.len - x_i - 1) |i| {
                xfm[xfm.len - i - 1] = xfm[xfm.len - i - 2];
                xid[xid.len - i - 1] = xid[xid.len - i - 2];
            }
            x_i += 1;
        }

        xid[x_i] = r_fid;
        xfm[x_i] = fm[r_i] - '0';

        // Proceed with the next file from the right.
        r_i -= 2;
        r_fid -= 1;
    }

    std.debug.print("IDs: {any}\n", .{xid});
    std.debug.print("FMs: {any}\n", .{xfm});
    // std.debug.print("size: {d}\n", .{x_i});

    // Calculate checksum.
    var checksum: usize = 0;
    var c: usize = 0;
    for (0..fm.len) |i| {
        std.debug.print("Printing {d} id {d} times", .{ xid[i], xfm[i] });
        for (0..xfm[i]) |_| {
            checksum += c * xid[i];
            c += 1;
        }

        if (i * 2 + 1 < fm.len) {
            std.debug.print(" and {d} dots\n", .{fm[i * 2 + 1] - '0'});
            for (0..fm[i * 2 + 1] - '0') |_| {
                c += 1;
            }
        }
    }

    return checksum;
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
    const buff = try file.readToEndAlloc(pg_ally, stat.size);

    // Process the file.
    const checksum = try compact(&pg_ally, buff[0 .. buff.len - 1]);
    std.debug.print("{d}\n", .{checksum});
}
