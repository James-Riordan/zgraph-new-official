const std = @import("std");
const Allocator = std.mem.Allocator;
const Thread = std.Thread;

fn createGraph() !IncidenceMatrix(false, true) {
    var block_alloc = try BlockAllocator.init(std.heap.page_allocator, 1024);
    defer block_alloc.deinit();
    const allocator = block_alloc.getAllocator();
    return IncidenceMatrix(false, true).init(allocator, 10);
}

const BlockAllocator = struct {
    allocator: std.mem.Allocator,
    block_size: usize,
    blocks: std.ArrayList([]i8),

    pub fn init(underlying_allocator: std.mem.Allocator, block_size: usize) !BlockAllocator {
        return BlockAllocator{
            .allocator = underlying_allocator,
            .block_size = block_size,
            .blocks = std.ArrayList([]i8).init(underlying_allocator),
        };
    }

    pub fn getAllocator(self: *BlockAllocator) std.mem.Allocator {
        return self.allocator;
    }

    pub fn allocate(self: *BlockAllocator) ![]i8 {
        const block = try self.allocator.alloc(i8, self.block_size);
        try self.blocks.append(block);
        return block;
    }

    pub fn deinit(self: *BlockAllocator) void {
        for (self.blocks.items) |block| {
            self.allocator.free(block);
        }
        self.blocks.deinit();
    }
};

pub fn IncidenceMatrix(comptime directed: bool, comptime weighted: bool) type {
    return struct {
        const Mutex = std.Thread.Mutex;

        allocator: Allocator,
        matrix: std.ArrayList([]if (weighted) ?f64 else i8),
        node_count: usize,
        edge_count: usize,
        edge_set: std.AutoHashMap(struct { usize, usize }, void),
        mutex: Mutex,

        pub fn init(allocator: std.mem.Allocator, initial_capacity: usize) !@This() {
            var matrix = std.ArrayList([]if (weighted) ?f64 else i8).initCapacity(allocator, initial_capacity) catch |err| {
                std.debug.print("[ERROR] Memory allocation failed: {}\n", .{err});
                return err;
            };

            for (0..initial_capacity) |_| {
                const row = try allocator.alloc(if (weighted) ?f64 else i8, 0);
                try matrix.append(row);
            }

            return @This(){
                .allocator = allocator,
                .matrix = matrix,
                .node_count = initial_capacity,
                .edge_count = 0,
                .edge_set = std.AutoHashMap(struct { usize, usize }, void).init(allocator),
                .mutex = Mutex{},
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.matrix.items) |row| {
                self.allocator.free(row);
            }
            self.matrix.deinit();
            self.edge_set.deinit();
        }

        fn resizeMatrix(self: *@This(), node_id: usize, new_capacity: usize) !void {
            if (node_id >= self.node_count) return error.InvalidNode;

            if (self.matrix.items[node_id].len < new_capacity) {
                self.matrix.items[node_id] = try self.allocator.realloc(self.matrix.items[node_id], new_capacity);
                @memset(self.matrix.items[node_id][self.edge_count..new_capacity], if (weighted) null else 0);
            }
        }

        pub fn addNode(self: *@This()) !usize {
            const new_id = self.node_count;
            self.node_count += 1;

            const new_row = try self.allocator.alloc(if (weighted) ?f64 else i8, self.edge_count);
            @memset(new_row, if (weighted) @as(?f64, null) else @as(i8, 0));

            try self.matrix.append(new_row);

            return new_id;
        }

        pub fn removeNode(self: *@This(), node_id: usize) !void {
            if (node_id >= self.node_count) return error.InvalidNode;

            self.mutex.lock();
            defer self.mutex.unlock();

            // ✅ Collect edges before removal using `.iterator()`
            var edges_to_remove = std.ArrayList(struct { usize, usize }).init(self.allocator);
            defer edges_to_remove.deinit();

            var it = self.edge_set.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (key[0] == node_id or key[1] == node_id) {
                    try edges_to_remove.append(key);
                }
            }

            for (edges_to_remove.items) |edge| {
                _ = self.edge_set.remove(edge);
            }

            // ✅ Free row & shift matrix
            self.allocator.free(self.matrix.items[node_id]);
            _ = self.matrix.orderedRemove(node_id);

            self.node_count -= 1;
        }

        pub fn addEdge(self: *@This(), src: usize, dst: usize, weight: if (weighted) ?f64 else void) !usize {
            if (src >= self.node_count or dst >= self.node_count) return error.InvalidNode;

            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.edge_set.contains(.{ src, dst })) return error.EdgeAlreadyExists;

            // ✅ Use resizeMatrix to ensure rows are large enough
            try self.resizeMatrix(src, self.edge_count + 1);
            try self.resizeMatrix(dst, self.edge_count + 1);

            if (weighted) {
                self.matrix.items[src][self.edge_count] = weight.?;
                self.matrix.items[dst][self.edge_count] = if (directed) -weight.? else weight.?;
            } else {
                self.matrix.items[src][self.edge_count] = 1;
                self.matrix.items[dst][self.edge_count] = if (directed) -1 else 1;
            }

            try self.edge_set.put(.{ src, dst }, {});
            if (!directed) {
                try self.edge_set.put(.{ dst, src }, {});
            }

            self.edge_count += 1;

            return self.edge_count - 1;
        }

        pub fn hasEdge(self: *@This(), src: usize, dst: usize) bool {
            if (src >= self.node_count or dst >= self.node_count) return false;

            if (self.edge_set.contains(.{ src, dst })) {
                return true;
            }

            for (0..self.edge_count) |edge_id| {
                if (self.matrix.items[src].len > edge_id and self.matrix.items[dst].len > edge_id) {
                    if ((weighted and self.matrix.items[src][edge_id] != null) or (!weighted and self.matrix.items[src][edge_id] != 0)) {
                        return true;
                    }
                }
            }

            return false;
        }

        pub fn updateEdgeWeight(self: *@This(), src: usize, dst: usize, new_weight: f64) !void {
            if (!weighted) return error.GraphNotWeighted;
            if (!self.hasEdge(src, dst)) return error.EdgeDoesNotExist;

            self.mutex.lock(); // 🔒 Ensure thread safety
            defer self.mutex.unlock();

            self.matrix.items[src][self.edge_count - 1] = new_weight;
            self.matrix.items[dst][self.edge_count - 1] = if (directed) -new_weight else new_weight;
        }

        pub fn reserveEdges(self: *@This(), additional_edges: usize) !void {
            const new_capacity = self.edge_count + additional_edges;

            for (0..self.node_count) |node_id| {
                try self.resizeMatrix(node_id, new_capacity);
            }
        }

        pub fn prepareParallelEdges(self: *@This(), additional_edges: usize) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            for (0..self.node_count) |node_id| {
                try self.resizeMatrix(node_id, self.edge_count + additional_edges);
            }
        }

        pub fn addEdgesParallel(self: *@This(), start: usize, end: usize) !void {
            const num_threads = try std.Thread.getCpuCount();
            var threads = try std.ArrayList(std.Thread).initCapacity(self.allocator, num_threads);
            defer threads.deinit();

            // **1️⃣ Allocate Edge Batches Properly**
            var edge_batches = try self.allocator.alloc(std.ArrayList(struct { usize, usize }), num_threads);
            defer self.allocator.free(edge_batches);

            for (0..num_threads) |t_index| {
                edge_batches[t_index] = std.ArrayList(struct { usize, usize }).init(self.allocator);
                errdefer edge_batches[t_index].deinit();
            }

            // **2️⃣ Distribute Edges Among Threads**
            var edge_count: usize = 0;
            for (start..end) |i| {
                for (0..self.node_count) |j| {
                    if (i == j) continue;

                    // Assign edge to a batch
                    const batch_index = edge_count % num_threads;
                    try edge_batches[batch_index].append(.{ i, j });
                    edge_count += 1;
                }
            }

            // **3️⃣ Spawn Threads**
            for (0..num_threads) |t_index| {
                try threads.append(try std.Thread.spawn(.{}, worker, .{ self, edge_batches[t_index].items }));
            }

            // **4️⃣ Join Threads**
            for (threads.items) |*thread| {
                thread.join();
            }

            // **5️⃣ Cleanup**
            for (0..num_threads) |t_index| {
                edge_batches[t_index].deinit();
            }
        }

        fn worker(graph: *IncidenceMatrix(false, false), edges: []struct { usize, usize }) void {
            for (edges) |edge| {
                const result = graph.addEdge(edge[0], edge[1], {}) catch |err| {
                    if (err == error.EdgeAlreadyExists) continue;
                    std.debug.print("[Thread] Error adding edge {d} -> {d}: {}\n", .{ edge[0], edge[1], err });
                    continue;
                };
                std.debug.print("[Thread] Added edge {d} -> {d} (id: {d})\n", .{ edge[0], edge[1], result });
            }
        }

        pub fn removeEdge(self: *@This(), edge_id: usize) void {
            if (edge_id >= self.edge_count) return; // ✅ Prevent out-of-bounds removal

            self.mutex.lock();
            defer self.mutex.unlock();

            std.debug.print("[REMOVE EDGE] Attempting to remove edge ID {d}\n", .{edge_id});

            var edges_to_remove = std.ArrayList(struct { usize, usize }).init(self.allocator);
            defer edges_to_remove.deinit();

            var it = self.edge_set.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                if (self.matrix.items[key[0]].len > edge_id and self.matrix.items[key[1]].len > edge_id) {
                    if (edges_to_remove.append(key)) |success| {
                        _ = success; // ✅ Ignore the success case
                    } else |err| {
                        std.debug.print("[ERROR] Out of Memory while collecting edges for removal: {}\n", .{err});
                        return; // ✅ Gracefully exit without crashing
                    }
                }
            }

            for (edges_to_remove.items) |edge| {
                _ = self.edge_set.remove(edge);
                if (!directed) {
                    _ = self.edge_set.remove(.{ edge[1], edge[0] }); // ✅ Remove reverse for undirected graphs
                }
            }

            for (self.matrix.items) |*row| {
                if (edge_id < row.*.len) {
                    for (edge_id..self.edge_count - 1) |i| {
                        row.*[i] = row.*[i + 1];
                    }
                    row.* = self.allocator.realloc(row.*, self.edge_count - 1) catch {
                        std.debug.print("[ERROR] Out of Memory while resizing adjacency matrix.\n", .{});
                        return;
                    };
                }
            }

            self.edge_count -= 1;

            std.debug.print("[REMOVE EDGE] Edge Set After Removal:\n", .{});
            var it2 = self.edge_set.iterator();
            while (it2.next()) |entry| {
                std.debug.print("[REMOVE EDGE] Edge {d} -> {d}\n", .{ entry.key_ptr.*[0], entry.key_ptr.*[1] });
            }

            std.debug.print("[REMOVE EDGE] Completed removal of edge {d}\n", .{edge_id});
        }

        pub fn getNeighbors(self: *@This(), node_id: usize) !std.ArrayList(usize) {
            if (node_id >= self.node_count) return error.InvalidNode;

            var neighbors = std.ArrayList(usize).init(self.allocator);
            errdefer neighbors.deinit();

            var seen = std.AutoHashMap(usize, void).init(self.allocator);
            defer seen.deinit();

            std.debug.print("[DEBUG] Finding neighbors for node {d}\n", .{node_id});

            var it = self.edge_set.iterator();
            while (it.next()) |entry| {
                const key = entry.key_ptr.*;
                const src = key[0];
                const dst = key[1];

                if (src == node_id and !seen.contains(dst)) {
                    try seen.put(dst, {});
                    try neighbors.append(dst);
                    std.debug.print("[DEBUG] Neighbor added: {d} (via edge {d} -> {d})\n", .{ dst, src, dst });
                } else if (dst == node_id and !seen.contains(src)) {
                    try seen.put(src, {});
                    try neighbors.append(src);
                    std.debug.print("[DEBUG] Neighbor added: {d} (via edge {d} -> {d})\n", .{ src, dst, src });
                }
            }

            std.debug.print("[DEBUG] Final unique neighbors for node {d}: {any}\n", .{ node_id, neighbors.items });

            return neighbors;
        }

        pub fn toAdjacencyList(self: *@This()) !std.AutoHashMap(usize, std.ArrayList(usize)) {
            var adj_list = std.AutoHashMap(usize, std.ArrayList(usize)).init(self.allocator);
            errdefer adj_list.deinit();

            for (0..self.node_count) |node| {
                const neighbors = try self.getNeighbors(node);
                try adj_list.put(node, neighbors);
            }

            return adj_list;
        }
    };
}

fn getRandomNode(max: usize) usize {
    var buf: u64 = undefined;
    std.crypto.random.bytes(std.mem.asBytes(&buf)); // Fill the `u64` buffer with random bytes
    return @as(usize, buf % max); // Ensure the value is within range
}

test "IncidenceMatrix: Initialize and Deinitialize" {
    const allocator = std.heap.page_allocator;
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

// test "IncidenceMatrix: Get Neighbors" {
//     var gpa = std.heap.GeneralPurposeAllocator(.{}){};
//     const allocator = gpa.allocator();
//     defer _ = gpa.deinit();

//     var matrix = try IncidenceMatrix(false, false).init(allocator, 4);
//     defer matrix.deinit();

//     _ = try matrix.addEdge(1, 2, {});
//     _ = try matrix.addEdge(1, 3, {});

//     var neighbors = try matrix.getNeighbors(1);
//     defer neighbors.deinit();

//     try std.testing.expectEqual(@as(usize, 2), neighbors.items.len);
//     try std.testing.expectEqual(@as(usize, 2), neighbors.items[0]);
//     try std.testing.expectEqual(@as(usize, 3), neighbors.items[1]);
// }

test "IncidenceMatrix: Get Neighbors (Debug Check)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(false, false).init(allocator, 4);
    defer matrix.deinit();

    _ = try matrix.addEdge(1, 2, {});
    _ = try matrix.addEdge(1, 3, {});

    var neighbors = try matrix.getNeighbors(1);
    defer neighbors.deinit();

    std.debug.print("[TEST] Neighbors of 1: {any}\n", .{neighbors.items});

    // ✅ Ensure exactly 2 neighbors
    try std.testing.expectEqual(@as(usize, 2), neighbors.items.len);

    // ✅ Check that both 2 and 3 exist, regardless of order
    try std.testing.expect((neighbors.items[0] == 2 and neighbors.items[1] == 3) or
        (neighbors.items[0] == 3 and neighbors.items[1] == 2));
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

    if (matrix.matrix.items.len > 0) {
        try std.testing.expectEqual(@as(i8, 1), matrix.matrix.items[0][0]);
    } else return error.RowNotAllocated;

    if (matrix.matrix.items.len > 1) {
        try std.testing.expectEqual(@as(i8, -1), matrix.matrix.items[1][0]);
    } else return error.RowNotAllocated;
}

test "IncidenceMatrix: Weighted Edge Correctness" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer _ = gpa.deinit();

    var matrix = try IncidenceMatrix(true, true).init(allocator, 3);
    defer matrix.deinit();

    _ = try matrix.addEdge(0, 1, 7.5);

    if (matrix.matrix.items.len > 0) {
        try std.testing.expectEqual(@as(f64, 7.5), matrix.matrix.items[0][0]);
    } else return error.RowNotAllocated;

    if (matrix.matrix.items.len > 1) {
        try std.testing.expectEqual(@as(f64, -7.5), matrix.matrix.items[1][0]);
    } else return error.RowNotAllocated;
}

test "IncidenceMatrix: Large Fully Connected Graph" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
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

    // **✅ New Parallel Edge Processing**
    try matrix.addEdgesParallel(0, node_count);

    try std.testing.expectEqual(@as(usize, node_count * (node_count - 1) / 2), matrix.edge_count);
}
