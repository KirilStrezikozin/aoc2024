const std = @import("std");

const PageValue = u32;
const Page = std.AutoHashMap(PageValue, void);
const PageGraph = std.AutoHashMap(PageValue, *Page);

// Returns a pointer to a newly allocated and initialized Page.
fn allocPage(ally: *const std.mem.Allocator) !*Page {
    const new_page_ptr = try ally.*.create(Page);
    new_page_ptr.* = Page.init(ally.*);
    return new_page_ptr;
}

// Iteratively frees each of the given Page Graph's inner Page hash maps.
fn freeGraphPages(ally: *const std.mem.Allocator, graph_ptr: *PageGraph) void {
    var it = graph_ptr.*.valueIterator();
    while (it.next()) |val_ptr| {
        const page_ptr: *Page = val_ptr.*;
        page_ptr.*.deinit();
        ally.*.destroy(page_ptr);
    }
    graph_ptr.*.deinit();
}

// Prints relations for each node in the given Page Graph.
fn printRelations(graph_ptr: *PageGraph) void {
    std.debug.print("Graph:\n", .{});

    var it = graph_ptr.*.iterator();
    while (it.next()) |entry| {
        std.debug.print("Relations for {d}:\n", .{entry.key_ptr.*});

        var kit = entry.value_ptr.*.*.keyIterator();
        while (kit.next()) |key_ptr| {
            std.debug.print("{d} ", .{key_ptr.*});
        }

        std.debug.print("\n", .{});
    }
}

fn process(ally: *const std.mem.Allocator, buff: []const u8) !void {
    // Allocate on the heap to avoid invalidated stack pointers.
    // Same is done for inner Page hash maps.
    const graph_ptr = try ally.*.create(PageGraph);
    graph_ptr.* = PageGraph.init(ally.*);

    var graph = graph_ptr.*;
    defer freeGraphPages(ally, &graph);
    defer ally.*.destroy(graph_ptr);

    var updates_i: usize = 0; // Byte index at which updates start.

    var line_len: usize = 0;
    var line_start: usize = 0;
    var page_num: PageValue = 0;

    var page_lnum: PageValue = undefined;
    var page_rnum: PageValue = undefined;

    for (buff, 0..) |c, i| {
        line_len += 1;

        // Parse digit.
        if (('0' <= c) and (c <= '9')) {
            page_num = page_num * 10 + c - '0';
        } else if (c == '|') {
            // Write the first page number.
            page_lnum = page_num;
            page_num = 0;
        } else if (c == '\n') {
            if (line_len <= 1) {
                // Empty line, proceed to updates.
                updates_i = i + 1;
                break;
            }

            // Write the second page number.
            page_rnum = page_num;
            page_num = 0;

            // Add both pages to the graph.
            var page_l: ?*Page = graph.get(page_lnum);
            if (page_l == null) {
                const new_page = try allocPage(ally);
                try graph.put(page_lnum, new_page);
                page_l = new_page;
            }

            if (graph.get(page_rnum)) |_| {} else {
                const new_page = try allocPage(ally);
                try graph.put(page_rnum, new_page);
            }

            // Assign relation.
            if (page_l) |page| {
                try page.put(page_rnum, {});
            } else unreachable;

            line_len = 0;
            line_start = i + 1;
        } else unreachable; // Unexpected character.
    }

    // TODO: process updates.
    // std.debug.print("Updates: {s}\n\n", .{buff[updates_i..]});
    printRelations(&graph);

    // Process updates.
    var relations: ?*Page = null;
    var line_valid: bool = true;

    line_start = updates_i;
    var sum: usize = 0;

    for (buff[updates_i..], updates_i..) |c, i| {
        if (c == '\n') {
            relations = null;

            if (!line_valid) {
                std.debug.print("Invalid: {s}\n", .{buff[line_start..i]});
                line_valid = true;
                line_start = i + 1;
                continue;
            }

            const num_start: usize = (i + line_start) / 2 - 1;
            const num = try std.fmt.parseInt(PageValue, buff[num_start .. num_start + 2], 10);
            sum += num;

            line_start = i + 1;
        } else if (!line_valid) {
            continue;
        }

        // Parse digit.
        else if (('0' <= c) and (c <= '9')) {
            page_num = page_num * 10 + c - '0';
        } else if (c == ',') {
            const current_num = page_num;
            page_num = 0;

            // First number in line.
            if (relations == null) {
                if (graph.get(current_num)) |new_relations| {
                    relations = new_relations;
                }
                continue;
            }

            // Skip unknown page numbers.
            if (!graph.contains(current_num)) continue;

            // Order not maintained.
            if (!relations.?.*.contains(current_num)) {
                line_valid = false;
                std.debug.print("Bad number: {d}\n", .{current_num});
                continue;
            }

            // Advance relations.
            relations = graph.get(current_num);
        }
    }

    std.debug.print("{d}\n", .{sum});
    return;
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
    try process(&pg_ally, file_buff);

    // std.debug.print("{d}\n", .{count});
}
