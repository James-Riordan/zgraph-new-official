const std = @import("std");
const Allocator = std.mem.Allocator;
const Edge = @import("../core/edge.zig").Edge;
const BitSetRange = std.bit_set.Range;

pub fn AdjacencyMatrix(comptime directed: bool, comptime weighted: bool) type {
    return struct {
        allocator: Allocator,
        matrix: std.ArrayList([]if (weighted) ?f64 else bool),
        present_nodes: std.DynamicBitSetUnmanaged,
        node_count: usize,

        pub fn init(allocator: Allocator, initial_capacity: usize) !@This() {
            var matrix = try std.ArrayList([]if (weighted) ?f64 else bool).initCapacity(allocator, initial_capacity);
            for (0..initial_capacity) |_| {
                const row = try allocator.alloc(if (weighted) ?f64 else bool, initial_capacity);
                @memset(row, if (weighted) null else false);
                try matrix.append(row);
            }

            var present_nodes = std.DynamicBitSetUnmanaged{};
            try present_nodes.resize(allocator, initial_capacity, false);
            present_nodes.setRangeValue(BitSetRange{ .start = 0, .end = initial_capacity }, false);

            return @This(){
                .allocator = allocator,
                .matrix = matrix,
                .present_nodes = present_nodes,
                .node_count = initial_capacity,
            };
        }

        pub fn deinit(self: *@This()) void {
            for (self.matrix.items) |row| {
                self.allocator.free(row);
            }
            self.matrix.deinit();
            self.present_nodes.deinit(self.allocator);
        }

        pub fn addNode(self: *@This(), node_id: ?usize) !usize {
            const new_id = node_id orelse blk: {
                // Reuse a cleared bit if available
                var it = self.present_nodes.iterator(.{});
                while (it.next()) |i| {
                    if (!self.present_nodes.isSet(i)) break :blk i;
                }
                break :blk self.node_count;
            };

            if (new_id >= self.node_count) {
                const new_size = new_id + 1;

                // Expand each existing row
                for (self.matrix.items) |*row| {
                    row.* = try self.allocator.realloc(row.*, new_size);
                    @memset(row.*[self.node_count..new_size], if (weighted) null else false);
                }

                // Add new rows
                for (self.node_count..new_size) |_| {
                    const row = try self.allocator.alloc(if (weighted) ?f64 else bool, new_size);
                    @memset(row, if (weighted) null else false);
                    try self.matrix.append(row);
                }

                try self.present_nodes.resize(self.allocator, new_size, false);
                self.node_count = new_size;
            }

            self.present_nodes.set(new_id);
            return new_id;
        }

        pub fn removeNode(self: *@This(), node_id: usize) !void {
            if (node_id >= self.node_count or !self.present_nodes.isSet(node_id)) {
                return error.InvalidNode;
            }
            self.present_nodes.unset(node_id);

            // Clear all edges to/from this node
            for (0..self.node_count) |i| {
                if (weighted) {
                    self.matrix.items[node_id][i] = null;
                    self.matrix.items[i][node_id] = null;
                } else {
                    self.matrix.items[node_id][i] = false;
                    self.matrix.items[i][node_id] = false;
                }
            }
        }

        pub fn addEdge(self: *@This(), src: usize, dst: usize, weight: if (weighted) ?f64 else void) !void {
            if (src >= self.node_count or dst >= self.node_count) return error.InvalidNode;
            self.matrix.items[src][dst] = if (weighted) weight.? else true;
            if (!directed) {
                self.matrix.items[dst][src] = if (weighted) weight.? else true;
            }
        }

        pub fn removeEdge(self: *@This(), src: usize, dst: usize) !void {
            if (src >= self.node_count or dst >= self.node_count) return error.InvalidNode;
            if (self.matrix.items[src][dst] == if (weighted) null else false) return error.EdgeNotFound; // ✅ Ensure edge exists before removal

            self.matrix.items[src][dst] = if (weighted) null else false;
            if (!directed) {
                self.matrix.items[dst][src] = if (weighted) null else false;
            }
        }

        pub fn getNeighbors(self: *@This(), node_id: usize) !std.ArrayList(usize) {
            if (node_id >= self.node_count or !self.present_nodes.isSet(node_id)) {
                return error.InvalidNode;
            }

            var neighbors = std.ArrayList(usize).init(self.allocator);
            errdefer neighbors.deinit();

            for (0..self.matrix.items[node_id].len) |i| {
                if (self.present_nodes.isSet(i)) {
                    const val = self.matrix.items[node_id][i];
                    if (val != if (weighted) null else false) {
                        try neighbors.append(i);
                    }
                }
            }
            return neighbors;
        }
    };
}

// Unit Tests
test "AdjacencyMatrix: Initialize and Deinitialize" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 5);
    defer matrix.deinit();
    try std.testing.expectEqual(@as(usize, 5), matrix.node_count);
}

test "AdjacencyMatrix: Add and Remove Nodes with Auto-Assigned IDs" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 2);
    defer matrix.deinit();

    const id1 = try matrix.addNode(null);
    const id2 = try matrix.addNode(null);

    try std.testing.expectEqual(@as(usize, 4), matrix.node_count);
    try std.testing.expectEqual(@as(usize, 2), id1);
    try std.testing.expectEqual(@as(usize, 3), id2);

    try matrix.removeNode(id1);
    try std.testing.expectError(error.InvalidNode, matrix.getNeighbors(id1));
}

test "AdjacencyMatrix: Add and Remove Nodes with Explicit ID" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 2);
    defer matrix.deinit();

    _ = try matrix.addNode(5); // Explicit ID
    try std.testing.expectEqual(@as(usize, 6), matrix.node_count);

    _ = try matrix.addNode(2); // Mid-range explicit ID
    try std.testing.expectEqual(@as(usize, 6), matrix.node_count); // Node count should not change

    try matrix.removeNode(2);
    try std.testing.expectError(error.InvalidNode, matrix.getNeighbors(2)); // Node should be removed
}

test "AdjacencyMatrix: Remove Nonexistent Node Returns Error" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try std.testing.expectError(error.InvalidNode, matrix.removeNode(10));
}

test "AdjacencyMatrix: Add and Remove Edges" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try matrix.addEdge(0, 1, 3.5);
    try std.testing.expect(matrix.matrix.items[0][1] != null);

    try matrix.removeEdge(0, 1);
    try std.testing.expect(matrix.matrix.items[0][1] == null);
}

test "AdjacencyMatrix: Remove Nonexistent Edge Returns Error" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try std.testing.expectError(error.EdgeNotFound, matrix.removeEdge(0, 2));
}

test "AdjacencyMatrix: Get Neighbors" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 4);
    defer matrix.deinit();

    // Mark node 1 as live
    _ = try matrix.addNode(1); // redundant but safe
    _ = try matrix.addNode(2);
    _ = try matrix.addNode(3);

    try matrix.addEdge(1, 2, {});
    try matrix.addEdge(1, 3, {});

    var neighbors = try matrix.getNeighbors(1);
    defer neighbors.deinit();

    try std.testing.expectEqual(@as(usize, 2), neighbors.items.len);
}

test "AdjacencyMatrix: Get Neighbors of Invalid Node Returns Error" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try std.testing.expectError(error.InvalidNode, matrix.getNeighbors(10));
}

test "AdjacencyMatrix: Self-Loops" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try matrix.addEdge(1, 1, 7.5);
    try std.testing.expect(matrix.matrix.items[1][1] == 7.5);
}

test "AdjacencyMatrix: Adding and Removing a Self-Loop Edge" {
    var matrix = try AdjacencyMatrix(true, true).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try matrix.addEdge(1, 1, 7.5);
    try std.testing.expect(matrix.matrix.items[1][1] == 7.5);

    try matrix.removeEdge(1, 1);
    try std.testing.expect(matrix.matrix.items[1][1] == null);
}

test "AdjacencyMatrix: Add and Remove Many Nodes" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 2);
    defer matrix.deinit();

    var added: usize = 0;
    while (added < 10) : (added += 1) {
        _ = try matrix.addNode(null);
    }

    // Remove 5 distinct live nodes
    var removed: usize = 0;
    var id: usize = 0;
    while (removed < 5 and id < matrix.node_count) : (id += 1) {
        if (matrix.present_nodes.isSet(id)) {
            try matrix.removeNode(id);
            removed += 1;
        }
    }

    const remaining = blk: {
        var count: usize = 0;
        var it = matrix.present_nodes.iterator(.{});
        while (it.next()) |_| {
            count += 1;
        }
        break :blk count;
    };

    try std.testing.expectEqual(@as(usize, 5), remaining);
}

test "AdjacencyMatrix: Remove Last Node" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 3);
    defer matrix.deinit();

    _ = try matrix.addNode(2); // ✅ ensure node 2 is marked as present
    try matrix.removeNode(2);
    try std.testing.expect(!matrix.present_nodes.isSet(2));
}

test "AdjacencyMatrix: Get Neighbors of Isolated Node" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 3);
    defer matrix.deinit();

    _ = try matrix.addNode(1); // Ensure 1 is marked present

    var neighbors = try matrix.getNeighbors(1);
    defer neighbors.deinit();

    try std.testing.expectEqual(@as(usize, 0), neighbors.items.len);
}

test "AdjacencyMatrix: Ensure Node Expansion with Explicit ID" {
    var matrix = try AdjacencyMatrix(true, false).init(std.testing.allocator, 3);
    defer matrix.deinit();

    _ = try matrix.addNode(7);
    _ = try matrix.addNode(2); // Make sure node 2 is live
    try std.testing.expectEqual(@as(usize, 8), matrix.node_count);

    try matrix.addEdge(7, 2, {});
    var neighbors = try matrix.getNeighbors(7);
    defer neighbors.deinit();

    try std.testing.expectEqual(@as(usize, 1), neighbors.items.len);
    try std.testing.expectEqual(@as(usize, 2), neighbors.items[0]);
}

test "AdjacencyMatrix: Undirected Edge Propagation" {
    var matrix = try AdjacencyMatrix(false, false).init(std.testing.allocator, 3);
    defer matrix.deinit();

    try matrix.addEdge(0, 1, {});
    try std.testing.expect(matrix.matrix.items[1][0]); // Ensure bidirectional edge exists
}

test "AdjacencyMatrix: Handle Large Graphs" {
    var matrix = try AdjacencyMatrix(false, true).init(std.testing.allocator, 10_000);
    defer matrix.deinit();

    for (0..9_999) |i| {
        try matrix.addEdge(i, i + 1, @floatFromInt(i % 100));
    }

    try std.testing.expectEqual(@as(usize, 10_000), matrix.node_count);
}

test "AdjacencyMatrix: Fully Connected Large Graph" {
    var matrix = try AdjacencyMatrix(false, true).init(std.testing.allocator, 100);
    defer matrix.deinit();

    for (0..100) |i| {
        _ = try matrix.addNode(i); // Ensure all are marked present
    }

    for (0..100) |i| {
        for (0..100) |j| {
            if (i != j) try matrix.addEdge(i, j, @floatFromInt(i + j));
        }
    }

    var neighbors = try matrix.getNeighbors(50);
    defer neighbors.deinit();

    try std.testing.expectEqual(@as(usize, 99), neighbors.items.len);
}
