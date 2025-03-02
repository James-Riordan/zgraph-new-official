const std = @import("std");
const Allocator = std.mem.Allocator;
const Node = @import("../core/node.zig").Node;
const Edge = @import("../core/edge.zig").Edge;

pub fn AdjacencyList(comptime directed: bool, comptime weighted: bool) type {
    return struct {
        allocator: Allocator,
        adjacency: std.AutoHashMap(u64, std.ArrayList(Edge(weighted))),

        pub fn init(allocator: Allocator) @This() {
            return @This(){
                .allocator = allocator,
                .adjacency = std.AutoHashMap(u64, std.ArrayList(Edge(weighted))).init(allocator),
            };
        }

        pub fn deinit(self: *@This()) void {
            var it = self.adjacency.iterator();
            while (it.next()) |entry| {
                entry.value_ptr.deinit();
            }
            self.adjacency.deinit();
        }

        pub fn addNode(self: *@This(), node_id: u64) !void {
            const entry = try self.adjacency.getOrPut(node_id);
            if (!entry.found_existing) {
                entry.value_ptr.* = std.ArrayList(Edge(weighted)).init(self.allocator);
            }
        }

        pub fn removeNode(self: *@This(), node_id: u64) !void {
            std.debug.print("\n[REMOVE NODE] START: Removing node {}\n", .{node_id});

            if (self.adjacency.getPtr(node_id)) |edges| {
                edges.deinit();
                _ = self.adjacency.remove(node_id);
                // No need for `else return;` → The function exits naturally
            }

            if (!directed) {
                var it = self.adjacency.iterator();
                while (it.next()) |entry| {
                    var edges = entry.value_ptr;
                    var i: usize = 0;
                    while (i < edges.items.len) {
                        if (edges.items[i].dst == node_id) {
                            std.debug.print("[REMOVE NODE] Removing incoming edge {} -> {}\n", .{ entry.key_ptr.*, node_id });
                            _ = edges.orderedRemove(i);
                        } else {
                            i += 1;
                        }
                    }
                }
            }

            std.debug.print("[REMOVE NODE] COMPLETED removal of node {}\n", .{node_id});
        }

        pub fn addEdge(self: *@This(), src: u64, dst: u64, weight: if (weighted) ?f64 else void) !void {
            var src_entry = try self.adjacency.getOrPut(src);
            if (!src_entry.found_existing) {
                src_entry.value_ptr.* = std.ArrayList(Edge(weighted)).init(self.allocator);
            }

            var dst_entry = try self.adjacency.getOrPut(dst);
            if (!dst_entry.found_existing) {
                dst_entry.value_ptr.* = std.ArrayList(Edge(weighted)).init(self.allocator);
            }

            // ✅ Allow self-loops and multiple edges
            try src_entry.value_ptr.append(try Edge(weighted).init(self.allocator, src, dst, if (weighted) weight.? else {}));

            if (!directed) {
                try dst_entry.value_ptr.append(try Edge(weighted).init(self.allocator, dst, src, if (weighted) weight.? else {}));
            }
        }

        pub fn removeEdge(self: *@This(), src: u64, dst: u64) void {
            if (self.adjacency.getPtr(src)) |edges| {
                removeEdgeHelper(edges, dst);
                if (edges.items.len == 0) {
                    edges.deinit();
                    _ = self.adjacency.remove(src); // ✅ No `try`, since it returns `bool`
                }
            }

            if (!directed) {
                if (self.adjacency.getPtr(dst)) |edges| {
                    removeEdgeHelper(edges, src);
                    if (edges.items.len == 0) {
                        edges.deinit();
                        _ = self.adjacency.remove(dst); // ✅ No `try`
                    }
                }
            }

            // ✅ Extra safety check: Ensure no empty nodes exist
            if (self.adjacency.get(src)) |edges| {
                if (edges.items.len == 0) {
                    _ = self.adjacency.remove(src);
                }
            }

            if (self.adjacency.get(dst)) |edges| {
                if (edges.items.len == 0) {
                    _ = self.adjacency.remove(dst);
                }
            }
        }

        fn removeEdgeHelper(edges: *std.ArrayList(Edge(weighted)), target: u64) void {
            var i: usize = 0;
            var removed: bool = false;

            while (i < edges.items.len) {
                if (edges.items[i].dst == target) {
                    _ = edges.orderedRemove(i); // ✅ No need for `catch`
                    removed = true;
                    break;
                }
                i += 1;
            }

            if (!removed) {
                std.debug.print("[WARNING] Attempted to remove a non-existent edge: {}\n", .{target});
            }
        }

        pub fn getNeighbors(self: *@This(), node_id: u64) ?std.ArrayList(Edge(weighted)) {
            return self.adjacency.get(node_id);
        }

        fn ensureNodeExists(self: *@This(), node_id: u64) !void {
            const entry = try self.adjacency.getOrPut(node_id);
            if (!entry.found_existing) {
                entry.value_ptr.* = std.ArrayList(Edge(weighted)).init(self.allocator);
            }
        }
    };
}

// Unit Tests
test "AdjacencyList: Initialize and Deinitialize" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();
    try std.testing.expectEqual(@as(usize, 0), list.adjacency.count());
}

test "AdjacencyList: Can add isolated nodes" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addNode(5);
    try list.addNode(10);

    try std.testing.expect(list.getNeighbors(5) != null);
    try std.testing.expect(list.getNeighbors(10) != null);
}

test "AdjacencyList: Removing an isolated node works correctly" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addNode(7);
    list.removeNode(7) catch |err| std.debug.print("[ERROR] Failed to remove node: {}\n", .{err});

    try std.testing.expect(list.getNeighbors(7) == null);
}

test "AdjacencyList: Retrieving neighbors of an isolated node returns null" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try std.testing.expect(list.getNeighbors(99) == null);
}

test "AdjacencyList: Add and Remove Edges" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addEdge(1, 2, 5.0);
    try std.testing.expect(list.getNeighbors(1) != null);
    try std.testing.expectEqual(@as(usize, 1), list.getNeighbors(1).?.items.len);

    list.removeEdge(1, 2);
    try std.testing.expectEqual(@as(usize, 0), if (list.getNeighbors(1)) |edges| edges.items.len else 0);
}

test "AdjacencyList: Adding duplicate edges should increase count" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addEdge(1, 2, 3.5);
    try list.addEdge(1, 2, 4.2); // Same edge, different weight

    try std.testing.expectEqual(@as(usize, 2), list.getNeighbors(1).?.items.len);
}

test "AdjacencyList: Removing a non-existent edge should not crash" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    list.removeEdge(1, 2);
    try std.testing.expectEqual(@as(usize, 0), list.adjacency.count());
}

test "AdjacencyList: Adding edges to a non-existent node should create it" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addEdge(10, 20, 1.5);
    try std.testing.expect(list.getNeighbors(10) != null);
}

test "AdjacencyList: Removing a node should remove all associated edges" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addEdge(1, 2, 4.5);
    try list.addEdge(1, 3, 3.0);
    try list.addEdge(2, 3, 2.0);

    try list.removeNode(1); // 🔥 Ensure proper error handling

    // ✅ Check edges were removed correctly
    try std.testing.expect(list.getNeighbors(1) == null);
    try std.testing.expect(list.getNeighbors(2) != null); // Ensure node 2 still exists
    try std.testing.expectEqual(@as(usize, 1), list.getNeighbors(2).?.items.len);
}

test "AdjacencyList: Removing a node with many connections removes all references" {
    var list = AdjacencyList(false, true).init(std.testing.allocator); // Undirected
    defer list.deinit();

    try list.addEdge(1, 2, 5.0);
    try list.addEdge(1, 3, 6.0);
    try list.addEdge(1, 4, 7.0);
    try list.addEdge(1, 5, 8.0);
    try list.addEdge(1, 6, 9.0);

    // Ensure all neighbors exist before removal
    try std.testing.expectEqual(@as(usize, 5), list.getNeighbors(1).?.items.len);

    list.removeNode(1) catch |err| std.debug.print("[ERROR] Failed to remove node: {}\n", .{err});

    // Ensure Node 1 is gone
    try std.testing.expect(list.getNeighbors(1) == null);

    // Ensure other nodes are still there, but no reference to Node 1
    for ([_]u64{ 2, 3, 4, 5, 6 }) |n| {
        try std.testing.expect(list.getNeighbors(n) != null);
        try std.testing.expectEqual(@as(usize, 0), list.getNeighbors(n).?.items.len);
    }
}

test "AdjacencyList: Removing self-loop should work correctly" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addEdge(1, 1, 2.5); // ✅ Self-loop

    try std.testing.expectEqual(@as(usize, 1), list.getNeighbors(1).?.items.len);

    list.removeEdge(1, 1);

    try std.testing.expectEqual(@as(usize, 0), if (list.getNeighbors(1)) |edges| edges.items.len else 0);
}

test "AdjacencyList: Can handle multiple self-loops and remove them correctly" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addEdge(1, 1, 2.5);
    try list.addEdge(1, 1, 3.0);
    try list.addEdge(1, 1, 3.5);

    list.removeEdge(1, 1);
    try std.testing.expectEqual(@as(usize, 2), if (list.getNeighbors(1)) |edges| edges.items.len else 0);

    list.removeEdge(1, 1);
    try std.testing.expectEqual(@as(usize, 1), if (list.getNeighbors(1)) |edges| edges.items.len else 0);

    list.removeEdge(1, 1);
    try std.testing.expectEqual(@as(usize, 0), if (list.getNeighbors(1)) |edges| edges.items.len else 0);
}

test "AdjacencyList: Removing a node in an undirected graph removes incoming edges" {
    var list = AdjacencyList(false, true).init(std.testing.allocator); // ❗ `false` for undirected
    defer list.deinit();

    try list.addEdge(1, 2, 4.5);
    try list.addEdge(1, 3, 3.0);
    try list.addEdge(2, 3, 2.0);

    std.debug.print("[DEBUG] Neighbors before removal:\n", .{});
    std.debug.print(" - Node 1: {}\n", .{if (list.getNeighbors(1)) |edges| edges.items.len else 0});
    std.debug.print(" - Node 2: {}\n", .{if (list.getNeighbors(2)) |edges| edges.items.len else 0});
    std.debug.print(" - Node 3: {}\n", .{if (list.getNeighbors(3)) |edges| edges.items.len else 0});

    list.removeNode(2) catch |err| std.debug.print("[ERROR] Failed to remove node: {}\n", .{err});

    std.debug.print("[DEBUG] Neighbors after removal:\n", .{});
    std.debug.print(" - Node 1: {}\n", .{if (list.getNeighbors(1)) |edges| edges.items.len else 0});
    std.debug.print(" - Node 3: {}\n", .{if (list.getNeighbors(3)) |edges| edges.items.len else 0});

    // ✅ Ensure Node 2 is fully removed
    try std.testing.expect(list.getNeighbors(2) == null);

    // ✅ Ensure Node 1 still exists before checking edges
    try std.testing.expect(list.getNeighbors(1) != null);
    try std.testing.expectEqual(@as(usize, 1), list.getNeighbors(1).?.items.len);

    // ✅ Ensure Node 3 still exists before checking edges
    try std.testing.expect(list.getNeighbors(3) != null);
    try std.testing.expectEqual(@as(usize, 1), list.getNeighbors(3).?.items.len); // ❗ Fix: Should be 1, not 2
}

test "AdjacencyList: Adding edge should auto-create nodes" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addEdge(99, 100, 3.5);
    try std.testing.expect(list.getNeighbors(99) != null);
    try std.testing.expect(list.getNeighbors(100) != null);
}

test "AdjacencyList: Removing a non-existent edge does nothing" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    list.removeEdge(42, 99);
    try std.testing.expectEqual(@as(usize, 0), list.adjacency.count());
}

test "AdjacencyList: Removing last edge removes empty nodes" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    try list.addEdge(1, 2, 5.0);
    try std.testing.expect(list.getNeighbors(1) != null);

    list.removeEdge(1, 2);

    // Ensure nodes were removed when empty
    try std.testing.expect(list.getNeighbors(1) == null);
    try std.testing.expect(list.getNeighbors(2) == null);
}

test "AdjacencyList: Memory is properly freed on deinit" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);

    try list.addEdge(1, 2, 3.5);
    try list.addEdge(3, 4, 1.2);

    list.deinit(); // ✅ Should release all memory with no leaks

    // Check that accessing after deinit is invalid (should crash in Debug mode)
    // try std.testing.expect(list.getNeighbors(1) == null);
}

test "AdjacencyList: Can handle large graphs efficiently" {
    var list = AdjacencyList(true, true).init(std.testing.allocator);
    defer list.deinit();

    var i: u64 = 0;
    while (i < 9_999) : (i += 1) {
        try list.addEdge(i, i + 1, @floatFromInt(i % 100));
    }

    try std.testing.expectEqual(@as(usize, 10_000), list.adjacency.count());
}
