const std = @import("std");

const Allocator = std.mem.Allocator;
const FileMap = []u8;

const max_usize = std.math.maxInt(usize);

/// Compact the file contents of the given dense file format map.
/// Returns the resulting checksum of the new file contents in the file map.
fn compact(ally: *const Allocator, fm: FileMap) !usize {
    if (fm.len == 0) return 0;

    var r_fid: usize = @divTrunc(fm.len, 2) - (1 - @mod(fm.len, 2));
    var r_i: usize = r_fid * 2;

    // Allocate a compressed file index map.
    var xid = try ally.alloc(usize, fm.len);
    var xorder = try ally.alloc(usize, fm.len);
    var xfm = try ally.alloc(u8, fm.len);
    defer ally.free(xfm);
    defer ally.free(xorder);
    defer ally.free(xid);

    for (0..fm.len) |i| {
        fm[i] -= '0';
        xorder[i] = max_usize;
    }

    // Put 0th file.
    xid[0] = 0;
    xorder[0] = 0;
    xfm[0] = fm[0];
    fm[0] = 0;

    var files: usize = 1;
    while (r_fid > 0) {
        var l_i: usize = 1;
        files += 1;

        // Find a free spot before the file on the right.
        while (l_i < r_i) {
            if (fm[l_i] < fm[r_i]) {
                l_i += 2;
                continue;
            }

            // Enough space available, move the file.
            fm[l_i] -= fm[r_i];
            fm[r_i - 1] += fm[r_i]; // Moved file leaves free space behind it.
            break;
        } else {
            l_i = r_i;
        }

        // Determine the new file location in the file map.
        var x_i: usize = 0;
        while ((x_i < fm.len) and (xorder[x_i] <= l_i)) {
            x_i += 1;
        }

        var i: usize = fm.len - 1;
        while ((i > x_i) and (i > 0)) {
            xid[i] = xid[i - 1];
            xorder[i] = xorder[i - 1];
            xfm[i] = xfm[i - 1];
            i -= 1;
        }

        xid[x_i] = r_fid;
        xorder[x_i] = l_i;
        xfm[x_i] = fm[r_i];
        fm[r_i] = 0;

        // Proceed to the next file from the right.
        r_fid -= 1;
        r_i -= 2;
    }

    // std.debug.print("fm: ", .{});
    // for (fm) |v| {
    //     std.debug.print("{d}", .{v});
    // }
    // std.debug.print("\n", .{});
    //
    // std.debug.print("xid: {any}\n", .{xid});
    // std.debug.print("xorder: {any}\n", .{xorder});
    // std.debug.print("xfm: {any}\n", .{xfm});
    //
    // std.debug.print("files: {d}\n", .{files});

    // Calculate checksum.
    var checksum: usize = 0;

    var l_i: usize = 0;
    var c: usize = 0;

    for (0..files) |i| {
        if (xorder[i] == max_usize) continue;

        var dots: usize = 0;
        if (l_i != xorder[i]) {
            for (l_i..xorder[i]) |j| {
                for (0..fm[j]) |_| {
                    c += 1;
                    dots += 1;
                }
            }
        }

        for (0..xfm[i]) |_| {
            checksum += c * xid[i];
            c += 1;
        }

        // std.debug.print("Print id({d})x{d} and {d} dots from {d}-{d} orders\n", .{ xid[i], xfm[i], dots, l_i + 1, xorder[i] });
        l_i = xorder[i];
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
