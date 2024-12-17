const std = @import("std");

const Allocator = std.mem.Allocator;
const FileMap = []u8;

/// Compact the file contents of the given dense file format map.
/// Returns the resulting checksum of the new file contents in the file map.
fn compact(ally: *const Allocator, fm: FileMap) !usize {
    if (fm.len == 0) return 0;

    var l_fid: usize = 1;
    var r_fid: usize = @divTrunc(fm.len, 2) - (1 - @mod(fm.len, 2));

    var l_i: usize = 1;
    var r_i: usize = fm.len - 1 - (1 - @mod(fm.len, 2));

    // Allocate a compressed file index map.
    var xfm = try ally.alloc(u8, fm.len);
    var xid = try ally.alloc(usize, fm.len);
    defer ally.free(xfm);
    defer ally.free(xid);

    var x_i: usize = 1;
    xid[0] = 0;
    xfm[0] = fm[0] - '0';

    while (r_i >= l_i) {
        // Leave file contents on the left unchanged.
        if (@mod(l_i, 2) == 0) {
            xid[x_i] = l_fid;
            xfm[x_i] = fm[l_i] - '0';
            x_i += 1;
            l_i += 1;
            l_fid += 1;
            continue;
        }

        // Fill space on the left with file contents on the right.
        if (fm[l_i] == 0) {
            // No free space.
            l_i += 1;
            continue;
        }

        xid[x_i] = r_fid;

        if (fm[l_i] >= fm[r_i]) {
            // Enough free space available.
            xfm[x_i] = fm[r_i] - '0';
            fm[l_i] = fm[l_i] - fm[r_i] + '0';
            fm[r_i] = 0;
            r_i -= 2;
            r_fid -= 1;

            // If more than enough, continue processing left space.
            if (fm[l_i] == 0) {
                l_i += 1;
            }
        } else {
            // Not enough free space available.
            xfm[x_i] = fm[l_i] - '0';
            fm[r_i] = fm[r_i] - fm[l_i] + '0';
            l_i += 1;
        }

        x_i += 1;
    }

    // std.debug.print("IDs: {any}\n", .{xid});
    // std.debug.print("FMs: {any}\n", .{xfm});
    // std.debug.print("size: {d}\n", .{x_i});

    // Calculate checksum.
    var checksum: usize = 0;
    var c: usize = 0;
    for (0..x_i) |i| {
        for (0..xfm[i]) |_| {
            checksum += c * xid[i];
            c += 1;
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
