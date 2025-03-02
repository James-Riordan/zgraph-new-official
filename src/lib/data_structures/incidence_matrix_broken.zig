const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

fn createGraph() !IncidenceMatrix(false, true) {
    var block_alloc = try BlockAllocator.init(std.heap.page_allocator, 1024);
    defer block_alloc.deinit();
    const allocator = block_alloc.getAllocator();
    return IncidenceMatrix(false, true).init(allocator, 10);
}

pub fn BlockAllocator(comptime T: type) type {
    return struct {
        allocator: std.mem.Allocator,
        block_size: usize,
        blocks: std.ArrayList([]T),

        pub fn init(allocator: std.mem.Allocator, block_size: usize) !@This() {
            return @This(){
                .allocator = allocator,
                .block_size = block_size,
                .blocks = std.ArrayList([]T).init(allocator),
            };
        }

        pub fn getAllocator(self: *@This()) std.mem.Allocator {
            return self.allocator;
        }

        pub fn allocate(self: *@This()) ![]T {
            const block = try self.allocator.alloc(T, self.block_size); // ✅ Make mutable
            try self.blocks.append(block);
            return block;
        }

        pub fn deinit(self: *@This()) void {
            for (self.blocks.items) |block| {
                if (block.len > 0) { // ✅ Just check length, not null
                    self.allocator.free(block);
                }
            }
            self.blocks.deinit();
        }
    };
}

pub fn IncidenceMatrix(comptime directed: bool, comptime weighted: bool) type {
    return struct {
        const Mutex = std.Thread.Mutex;

        allocator: Allocator,
        matrix: std.ArrayList(?[]if (weighted) f64 else i8),
        node_count: usize,
        edge_count: usize,
        edge_set: std.AutoHashMap(struct { usize, usize }, void),
        mutex: Mutex,

        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !@This() {
            var block_alloc = try BlockAllocator(if (weighted) f64 else i8).init(allocator, 1024);
            defer block_alloc.deinit();

            var matrix = std.ArrayList(?[]if (weighted) f64 else i8).initCapacity(block_alloc.getAllocator(), initial_capacity) catch |err| {
                std.debug.print("[ERROR] Memory allocation failed: {}\n", .{err});
                return err;
            };

            for (0..initial_capacity) |_| {
                const row: ?[]if (weighted) f64 else i8 = try block_alloc.allocate();
                try matrix.append(row);
            }

            return @This(){
                .allocator = block_alloc.getAllocator(),
                .matrix = matrix,
                .node_count = initial_capacity,
                .edge_count = 0,
                .edge_set = std.AutoHashMap(struct { usize, usize }, void).init(block_alloc.getAllocator()),
                .mutex = Mutex{},
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.matrix.items) |*row| {
                if (row.*) |*unwrapped_row| {
                    if (unwrapped_row.len > 0) { // ✅ Check length instead of `null`
                        self.allocator.free(unwrapped_row.*);
                    }
                    row.* = null; // ✅ Set to null to prevent use-after-free
                }
            }

            self.matrix.deinit();
            self.edge_set.deinit();
        }

        pub fn addNode(self: *@This()) !usize {
            const new_id = self.node_count;
            self.node_count += 1;

            // ✅ Ensure proper type (`?[]f64` instead of `[]?f64`)
            const new_row: ?[]if (weighted) f64 else i8 = try self.allocator.alloc(if (weighted) f64 else i8, self.edge_count);

            // ✅ Properly append to matrix
            try self.matrix.append(new_row);
            return new_id;
        }

        const EdgeSet = std.AutoHashMap(struct { usize, usize }, void);

        pub fn addEdge(self: *@This(), src: usize, dst: usize, weight: if (weighted) ?f64 else void) !usize {
            if (src >= self.node_count or dst >= self.node_count) return error.InvalidNode;

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.edge_set.contains(.{ src, dst })) return error.EdgeAlreadyExists;

            // ✅ Ensure rows exist for src & dst
            if (self.matrix.items[src] == null) {
                self.matrix.items[src] = try self.allocator.alloc(if (weighted) f64 else i8, self.edge_count + 1);
                @memset(self.matrix.items[src].?, if (weighted) 0.0 else @as(i8, 0)); // Initialize memory
            }
            if (self.matrix.items[dst] == null) {
                self.matrix.items[dst] = try self.allocator.alloc(if (weighted) f64 else i8, self.edge_count + 1);
                @memset(self.matrix.items[dst].?, if (weighted) 0.0 else @as(i8, 0)); // Initialize memory
            }

            // ✅ Ensure `realloc()` only operates on valid pointers
            self.matrix.items[src] = try self.allocator.realloc(self.matrix.items[src].?, self.edge_count + 1);
            self.matrix.items[dst] = try self.allocator.realloc(self.matrix.items[dst].?, self.edge_count + 1);

            // ✅ Assign weight values safely
            self.matrix.items[src].?[self.edge_count] = if (weighted) weight.? else 1;
            self.matrix.items[dst].?[self.edge_count] =
                if (directed) (if (weighted) -weight.? else -1) else (if (weighted) weight.? else 1);

            // ✅ Add to edge_set
            try self.edge_set.put(.{ src, dst }, {});
            if (!directed) {
                try self.edge_set.put(.{ dst, src }, {});
            }

            self.edge_count += 1;
            return self.edge_count - 1;
        }

        pub fn reserveEdges(self: *@This(), additional_edges: usize) !void {
            const new_capacity = self.edge_count + additional_edges;
            for (self.matrix.items) |*row| {
                if (row.* == null) {
                    row.* = try self.allocator.alloc(if (weighted) f64 else i8, new_capacity);
                } else {
                    const old_buffer = row.* orelse try self.allocator.alloc(if (weighted) f64 else i8, new_capacity);
                    row.* = try self.allocator.realloc(old_buffer, new_capacity);
                }
            }
        }

        pub fn prepareParallelEdges(self: *@This(), additional_edges: usize) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            const new_capacity = self.edge_count + additional_edges;
            for (self.matrix.items) |*row| {
                if (row.* == null) {
                    row.* = try self.allocator.alloc(if (weighted) f64 else i8, new_capacity);
                } else {
                    const old_buffer = row.* orelse try self.allocator.alloc(if (weighted) f64 else i8, new_capacity);
                    row.* = try self.allocator.realloc(old_buffer, new_capacity);
                }
            }
        }

        pub fn addEdgesParallel(self: *@This(), start: usize, end: usize) !void {
            const num_threads = try std.Thread.getCpuCount();
            var threads = try std.ArrayList(std.Thread).initCapacity(self.allocator, num_threads);
            defer threads.deinit();

            for (0..num_threads) |t_index| {
                try threads.append(try std.Thread.spawn(.{}, worker, .{ self, t_index, start, end, num_threads }));
            }

            for (threads.items) |*thread| {
                thread.join();
            }
        }

        fn worker(graph: *IncidenceMatrix(false, false), thread_id: usize, inner_start: usize, inner_end: usize, total_threads: usize) void {
            for (inner_start..inner_end) |i| {
                if (i % total_threads != thread_id) continue; // Distribute work evenly

                for (0..graph.node_count) |j| {
                    if (i == j) continue;

                    // ✅ Lock only when modifying shared state
                    graph.mutex.lock();
                    defer graph.mutex.unlock();

                    const result = graph.addEdge(i, j, {}) catch |err| {
                        if (err == error.EdgeAlreadyExists) continue;
                        std.debug.print("[Thread {d}] Error adding edge {d} -> {d}: {}\n", .{ thread_id, i, j, err });
                        continue;
                    };
                    std.debug.print("[Thread {d}] Added edge {d} -> {d} (id: {d})\n", .{ thread_id, i, j, result });
                }
            }
        }

        pub fn removeEdge(self: *@This(), edge_id: usize) void {
            if (edge_id >= self.edge_count) return;

            for (self.matrix.items) |*row| {
                if (row.*) |*unwrapped_row| { // ✅ Dereference before indexing
                    if (edge_id < unwrapped_row.len) {
                        if (weighted) {
                            unwrapped_row.*[edge_id] = std.math.nan(f64); // ✅ Corrected indexing
                        } else {
                            unwrapped_row.*[edge_id] = -1; // ✅ Corrected indexing
                        }
                    }
                }
            }

            // ✅ Remove from edge_set safely
            _ = self.edge_set.remove(.{ edge_id, edge_id });

            self.edge_count -= 1;
        }

        pub fn getNeighbors(self: *@This(), node_id: usize) !std.ArrayList(usize) {
            if (node_id >= self.node_count) return error.InvalidNode;

            var neighbors = std.ArrayList(usize).init(self.allocator);
            errdefer neighbors.deinit();

            var seen = std.AutoHashMap(usize, void).init(self.allocator);
            defer seen.deinit();

            var it = self.edge_set.iterator();
            while (it.next()) |entry| {
                const src = entry.key_ptr.*[0]; // ✅ Correct tuple access
                const dst = entry.key_ptr.*[1];

                if (src == node_id and !seen.contains(dst)) {
                    try seen.put(dst, {});
                    try neighbors.append(dst);
                } else if (!directed and dst == node_id and !seen.contains(src)) {
                    try seen.put(src, {});
                    try neighbors.append(src);
                }
            }

            return neighbors;
        }
    };
}

fn getRandomNode(max: usize) usize {
    var buf: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&buf)); // Fill the `u64` buffer with random bytes
    return @as(usize, buf % max); // Ensure the value is within range
}

test "IncidenceMatrix: Initialize and Deinitialize" {
    const allocator = std.heap.page_allocator; // ✅ Faster for small tests
    var matrix = try IncidenceMatrix(true, true).init(allocator, 5);
    defer matrix.deinit();

    try std.testing.expectEqual(@as(usize, 5), matrix.node_count);
    try std.testing.expectEqual(@as(usize, 0), matrix.edge_count);
}

test "IncidenceMatrix: Add and Remove Nodes" {
    const allocator = std.heap.page_allocator;
    var matrix = try IncidenceMatrix(true, true).init(allocator, 2);
    defer matrix.deinit();

    const id = try matrix.addNode();
    try std.testing.expectEqual(@as(usize, 3), matrix.node_count);
    try std.testing.expect(id == 2);
}

test "IncidenceMatrix: Add and Remove Edges" {
    const allocator = std.heap.page_allocator;
    var matrix = try IncidenceMatrix(true, true).init(allocator, 3);
    defer matrix.deinit();

    const edge_id = try matrix.addEdge(0, 1, 3.5);
    try std.testing.expectEqual(@as(usize, 1), matrix.edge_count);

    matrix.removeEdge(edge_id);
    try std.testing.expectEqual(@as(usize, 0), matrix.edge_count);
}

// ---

test "IncidenceMatrix: Get Neighbors" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(false, false).init(allocator, 4);
    defer matrix.deinit();

    _ = try matrix.addEdge(1, 2, {}); // ✅ Explicitly discard return value
    _ = try matrix.addEdge(1, 3, {});

    var neighbors = try matrix.getNeighbors(1);
    defer neighbors.deinit();

    try std.testing.expectEqual(@as(usize, 2), neighbors.items.len);
}

test "IncidenceMatrix: Optimized Get Neighbors" {
    const allocator = std.heap.page_allocator;
    var matrix = try IncidenceMatrix(false, false).init(allocator, 4);
    defer matrix.deinit();

    _ = try matrix.addEdge(1, 2, {});
    _ = try matrix.addEdge(1, 3, {});

    var neighbors = try matrix.getNeighbors(1);
    defer neighbors.deinit();

    try std.testing.expectEqual(@as(usize, 2), neighbors.items.len);
}

test "IncidenceMatrix: Invalid Node in AddEdge" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(true, true).init(allocator, 3);
    defer matrix.deinit();

    const result = matrix.addEdge(0, 10, 2.5);
    try std.testing.expectError(error.InvalidNode, result);
}

test "IncidenceMatrix: Invalid Edge Removal" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(true, true).init(allocator, 3);
    defer matrix.deinit();

    matrix.removeEdge(10); // ✅ Should not panic
}

test "IncidenceMatrix: Directed Edge Correctness" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(true, false).init(allocator, 3);
    defer matrix.deinit();

    _ = try matrix.addEdge(0, 1, {});

    // ✅ Fix: Unwrap optional before indexing
    const row = matrix.matrix.items[0] orelse return error.RowNotAllocated;
    try std.testing.expectEqual(@as(i8, 1), row[0]);

    const row_1 = matrix.matrix.items[1] orelse return error.RowNotAllocated;
    try std.testing.expectEqual(@as(i8, -1), row_1[0]);
}

test "IncidenceMatrix: Weighted Edge Correctness" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(true, true).init(allocator, 3);
    defer matrix.deinit();

    _ = try matrix.addEdge(0, 1, 7.5);

    // ✅ Fix: Unwrap optional before indexing
    const row = matrix.matrix.items[0] orelse return error.RowNotAllocated;
    try std.testing.expectEqual(@as(f64, 7.5), row[0]);

    const row_1 = matrix.matrix.items[1] orelse return error.RowNotAllocated;
    try std.testing.expectEqual(@as(f64, -7.5), row_1[0]);
}

test "IncidenceMatrix: Remove Edge Sentinel Test" {
    const allocator = std.heap.page_allocator;
    var matrix = try IncidenceMatrix(false, false).init(allocator, 5);
    defer matrix.deinit();

    const edge_id = try matrix.addEdge(0, 1, {});
    matrix.removeEdge(edge_id);

    // ✅ Fix: Unwrap optional before indexing
    if (matrix.matrix.items[0]) |row| {
        try std.testing.expectEqual(@as(i8, -1), row[edge_id]);
    }
}

test "IncidenceMatrix: Large Fully Connected Graph" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; // ✅ Use GPA
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(false, false).init(allocator, 100);
    defer matrix.deinit();

    for (0..100) |i| {
        for (i + 1..100) |j| {
            _ = try matrix.addEdge(i, j, {});
        }
    }

    try std.testing.expectEqual(@as(usize, 100 * 99 / 2), matrix.edge_count);
}

test "IncidenceMatrix: Large Dense Graph (Optimized)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const node_count = 100;
    var matrix = try IncidenceMatrix(false, true).init(allocator, node_count);
    defer matrix.deinit();

    for (0..node_count) |i| {
        for (i + 1..node_count) |j| {
            _ = try matrix.addEdge(i, j, @floatFromInt(i + j));
        }
    }

    try std.testing.expectEqual(@as(usize, node_count * (node_count - 1) / 2), matrix.edge_count);
}

test "IncidenceMatrix: Large Dense Graph (Parallel, Optimized)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; // ✅ Use GPA for parallel test
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    const node_count = 100;
    var matrix = try IncidenceMatrix(false, false).init(allocator, node_count);
    defer matrix.deinit();

    try matrix.prepareParallelEdges(node_count * (node_count - 1) / 2);

    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;
    const chunk_size = node_count / num_threads;

    for (0..num_threads) |t| {
        threads[t] = try std.Thread.spawn(std.Thread.SpawnConfig{}, IncidenceMatrix(false, false).addEdgesParallel, .{ &matrix, t * chunk_size, (t + 1) * chunk_size });
    }

    for (threads) |thread| {
        thread.join();
    }

    try std.testing.expectEqual(@as(usize, node_count * (node_count - 1) / 2), matrix.edge_count);
}

test "IncidenceMatrix: High Load Parallel Insertions" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(false, false).init(allocator, 100);
    defer matrix.deinit();

    try matrix.prepareParallelEdges(5000); // ✅ Ensure we can handle high loads

    const num_threads = 4;
    var threads: [num_threads]std.Thread = undefined;
    for (0..num_threads) |t| {
        threads[t] = try std.Thread.spawn(std.Thread.SpawnConfig{}, IncidenceMatrix(false, false).addEdgesParallel, .{ &matrix, 0, 100 });
    }

    for (threads) |thread| {
        thread.join();
    }

    std.debug.print("[TEST] Final Edge Count: {d}\n", .{matrix.edge_count});
}
