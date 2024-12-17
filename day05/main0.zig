const std = @import("std");

const Allocator = std.mem.Allocator;

const PageValue = u32;
const Page = std.AutoHashMap(PageValue, void);
const PageGraph = std.AutoHashMap(PageValue, *Page);

const Update = std.ArrayList(PageValue);

// Returns a pointer to a newly allocated and initialized Page.
fn allocPage(ally: *const Allocator) !*Page {
    const new_page_ptr = try ally.*.create(Page);
    new_page_ptr.* = Page.init(ally.*);
    return new_page_ptr;
}

// Iteratively frees each of the given Page Graph's inner Page hash maps.
fn freeGraphPages(ally: *const Allocator, graph_ptr: *PageGraph) void {
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

// Processes the part of the file with rules and updates the Page Graph hash
// map. Returns the byte offset at which to continue processing the buffer.
fn read_graph(ally: *const Allocator, buff: []const u8, g: *PageGraph) !usize {
    var seek: usize = 0; // Byte index at which updates start.

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
                seek = i + 1;
                break;
            }

            // Write the second page number.
            page_rnum = page_num;
            page_num = 0;

            // Add both pages to the graph.
            var page_l: ?*Page = g.get(page_lnum);
            if (page_l == null) {
                const new_page = try allocPage(ally);
                try g.put(page_lnum, new_page);
                page_l = new_page;
            }

            if (!g.contains(page_rnum)) {
                const new_page = try allocPage(ally);
                try g.put(page_rnum, new_page);
            }

            // Assign relation.
            try page_l.?.put(page_rnum, {});

            line_len = 0;
            line_start = i + 1;
        } else unreachable; // Unexpected character.
    }

    return seek;
}

// Checks a single update record. If the order of pages is correct according to
// relations in the given Page Graph, returns the page number at the middle,
// otherwise zero.
fn verify_update(array_ptr: *const []PageValue, graph: *PageGraph) !PageValue {
    const array = array_ptr.*;

    if (array.len == 0) unreachable;
    if (array.len == 1) return array[0];

    var relations: ?*Page = graph.get(array[0]);

    for (1..array.len) |i| {
        const curr_num = array[i];

        // Skip unknown page numbers.
        if (!graph.contains(curr_num)) continue;

        // Order not maintained.
        if (!relations.?.*.contains(curr_num)) return 0;

        // Advance relations.
        relations = graph.get(curr_num);
    }

    // Return page value at the middle.
    // std.debug.print("{any} is valid\n", .{array});
    return array[array.len / 2];
}

// Processes the page updates line by line.
// Returns the final sum of middle page values of verified updates.
fn verify_udpates(buff: []const u8, array: *Update, graph: *PageGraph) !usize {
    var sum: usize = 0;
    var insert_i: usize = 0;

    var it = std.mem.tokenizeScalar(u8, buff, '\n');
    while (it.next()) |update_buff| {
        insert_i = 0;

        var tokenizer = std.mem.tokenizeScalar(u8, update_buff, ',');
        while (tokenizer.next()) |token| {
            const page = try std.fmt.parseInt(PageValue, token, 10);

            if (array.items.len <= insert_i) {
                try array.append(page);
            } else {
                array.items[insert_i] = page;
            }

            insert_i += 1;
        }

        sum += try verify_update(&array.items[0..insert_i], graph);
    }

    return sum;
}

fn process(ally: *const Allocator, buff: []const u8) !void {
    // Allocate graph on the heap to avoid invalidated stack pointers.
    // Same is done for inner Page hash maps.
    const graph_ptr = try ally.*.create(PageGraph);
    graph_ptr.* = PageGraph.init(ally.*);

    var graph = graph_ptr.*;
    defer freeGraphPages(ally, &graph);
    defer ally.*.destroy(graph_ptr);

    // Read rules into the graph.
    const seek = try read_graph(ally, buff, &graph);
    // printRelations(&graph);

    // Process updates.
    const array_ptr = try ally.*.create(Update);
    array_ptr.* = Update.init(ally.*);

    var array = array_ptr.*;
    defer array.deinit();
    defer ally.*.destroy(array_ptr);

    const sum = try verify_udpates(buff[seek..], &array, &graph);
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
}
