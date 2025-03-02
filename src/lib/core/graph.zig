const std = @import("std");

const Node = @import("node.zig").Node;
const Edge = @import("edge.zig").Edge;

/// 🚀 Generic Graph Definition with Compile-Time Optimizations
pub fn Graph(comptime directed: bool, comptime acyclic: bool, comptime weighted: bool) type {
    return struct {
        const EdgeT = Edge(weighted);
        allocator: std.mem.Allocator,
        nodes: std.AutoHashMap(u64, Node),
        edges: if (directed) std.AutoHashMap(u64, std.ArrayList(EdgeT)) else std.AutoHashMap(u64, std.ArrayListUnmanaged(EdgeT)),

        heterogeneous: bool, // ✅ Explicitly controlled by user
        node_types: ?std.AutoHashMap(u64, []const u8), // ✅ Only allocated if converted to heterogeneous
        edge_types: ?std.AutoHashMap(u64, []const u8), // ✅ Only allocated if converted to heterogeneous

        /// 🚀 Initialize Graph
        pub fn init(allocator: std.mem.Allocator) @This() {
            std.debug.print("[INIT] Graph Initialized.\n", .{});
            return @This(){
                .allocator = allocator,
                .nodes = std.AutoHashMap(u64, Node).init(allocator),
                .edges = if (directed) std.AutoHashMap(u64, std.ArrayList(EdgeT)).init(allocator) else std.AutoHashMap(u64, std.ArrayListUnmanaged(EdgeT)).init(allocator),
                .heterogeneous = false,
                .node_types = null,
                .edge_types = null,
            };
        }

        /// 🚀 Deinitialize Graph
        pub fn deinit(self: *@This()) void {
            if (self.heterogeneous) {
                if (self.node_types) |*nt| {
                    var it = nt.iterator();
                    while (it.next()) |entry| {
                        self.allocator.free(entry.value_ptr.*); // ✅ No null check needed
                    }
                    nt.deinit();
                }

                if (self.edge_types) |*et| {
                    var it = et.iterator();
                    while (it.next()) |entry| {
                        self.allocator.free(entry.value_ptr.*); // ✅ No null check needed
                    }
                    et.deinit();
                }
            }

            // 🚀 Free Edges
            var it = self.edges.iterator();
            while (it.next()) |entry| {
                if (directed) {
                    entry.value_ptr.deinit(); // ✅ `ArrayList` version (No allocator needed)
                } else {
                    entry.value_ptr.deinit(self.allocator); // ✅ `ArrayListUnmanaged` version
                }
            }

            self.edges.deinit();

            // 🚀 Free Nodes (INCLUDING `label`)
            var node_it = self.nodes.iterator();
            while (node_it.next()) |entry| {
                self.allocator.free(entry.value_ptr.label); // ✅ No need for null check
            }
            self.nodes.deinit();
        }

        /// 🚀 Convert Graph to Heterogeneous (Explicit User Action)
        pub fn convertToHeterogeneous(self: *@This()) !void {
            if (self.heterogeneous) return error.AlreadyHeterogeneous;
            self.node_types = std.AutoHashMap(u64, []const u8).init(self.allocator);
            self.edge_types = std.AutoHashMap(u64, []const u8).init(self.allocator);
            self.heterogeneous = true;
        }

        /// 🚀 Add Node (Compile-Time Optimized for Homogeneous & Heterogeneous Graphs)
        pub fn addNode(self: *@This(), id: u64, label: []const u8, node_type: ?[]const u8) !void {
            try self.nodes.put(id, Node{
                .id = id,
                .label = try self.allocator.dupe(u8, label), // ✅ Heap-allocate label
                .data = std.StringHashMap([]const u8).init(self.allocator),
            });

            if (self.heterogeneous) {
                if (node_type == null) return error.MissingNodeType;
                const allocated_type = try self.allocator.dupe(u8, node_type.?);
                try self.node_types.?.put(id, allocated_type);
            } else if (node_type != null) {
                return error.GraphIsHomogeneous;
            }
        }

        pub fn removeNode(self: *@This(), node_id: u64) void {
            if (self.nodes.getPtr(node_id)) |node| {
                self.allocator.free(node.label); // ✅ Free label before removing
            }

            _ = self.nodes.remove(node_id);

            if (self.heterogeneous) {
                _ = self.node_types.?.remove(node_id);
            }

            // Remove all outgoing edges
            if (self.edges.getPtr(node_id)) |edges| {
                for (edges.*.items) |edge| {
                    if (self.heterogeneous) {
                        const edge_key = generateEdgeKey(node_id, edge.dst);
                        const hashed_key = hashEdgeKey(edge_key);
                        _ = self.edge_types.?.remove(hashed_key);
                    }
                }
                if (directed) {
                    edges.*.deinit();
                } else {
                    edges.*.deinit(self.allocator);
                }
                _ = self.edges.remove(node_id);
            }

            // ✅ Remove incoming edges from other nodes (fixes dangling edges)
            var it = self.edges.iterator();
            while (it.next()) |entry| {
                var i: usize = 0;
                while (i < entry.value_ptr.items.len) {
                    if (entry.value_ptr.items[i].dst == node_id) {
                        if (self.heterogeneous) {
                            const edge_key = generateEdgeKey(entry.key_ptr.*, node_id);
                            const hashed_key = hashEdgeKey(edge_key);
                            _ = self.edge_types.?.remove(hashed_key);
                        }
                        _ = entry.value_ptr.orderedRemove(i);
                        continue;
                    }
                    i += 1;
                }
            }
        }

        /// 🚀 Add Edge (with Explicit Debugging)
        pub fn addEdge(self: *@This(), src: u64, dst: u64, weight: if (weighted) ?f64 else void, edge_type: ?[]const u8) !void {
            std.debug.print("[ADD EDGE] Attempting to add edge {} -> {} (Weight: {})\n", .{ src, dst, if (weighted) weight.? else 0.0 });

            if (!self.nodes.contains(src) or !self.nodes.contains(dst)) {
                std.debug.print("[ERROR] NodeNotFound: Either {} or {} does not exist!\n", .{ src, dst });
                return error.NodeNotFound;
            }

            if (acyclic) {
                var visited = std.AutoHashMap(u64, bool).init(self.allocator);
                defer visited.deinit();

                if (self.hasCycle(dst, src, &visited)) {
                    std.debug.print("[ERROR] CycleDetected: Adding {} -> {} would create a cycle!\n", .{ src, dst });
                    return error.CycleDetected;
                }
            }

            if (weighted and weight == null) {
                std.debug.print("[ERROR] MissingWeight: Edge {} -> {} requires a weight!\n", .{ src, dst });
                return error.MissingWeight;
            }

            const edge_key = generateEdgeKey(src, dst);
            const hashed_key = std.hash.Wyhash.hash(0, std.mem.asBytes(&edge_key));

            if (self.heterogeneous) {
                if (edge_type == null) {
                    std.debug.print("[ERROR] MissingEdgeType: Heterogeneous graph requires edge type!\n", .{});
                    return error.MissingEdgeType;
                }
                const allocated_edge_type = try self.allocator.dupe(u8, edge_type.?);
                try self.edge_types.?.put(hashed_key, allocated_edge_type);
            } else if (edge_type != null) {
                std.debug.print("[ERROR] GraphIsHomogeneous: Cannot add type to homogeneous graph!\n", .{});
                return error.GraphIsHomogeneous;
            }

            // Ensure an edge list exists for src
            var edge_list = try self.edges.getOrPut(src);
            if (!edge_list.found_existing) {
                if (directed) {
                    edge_list.value_ptr.* = std.ArrayList(EdgeT).init(self.allocator);
                } else {
                    edge_list.value_ptr.* = std.ArrayListUnmanaged(EdgeT){};
                }
                std.debug.print("[ADD EDGE] Created new edge list for {}\n", .{src});
            }

            if (directed) {
                try edge_list.value_ptr.append(try EdgeT.init(self.allocator, src, dst, if (weighted) weight.? else {}));
            } else {
                try edge_list.value_ptr.append(self.allocator, try EdgeT.init(self.allocator, src, dst, if (weighted) weight.? else {}));
            }

            std.debug.print("[ADD EDGE] AFTER ADD: Edges from {}: {}\n", .{ src, edge_list.value_ptr.items.len });

            // 🚀 Ensure undirected graphs add the reverse edge (dst -> src)
            if (!directed) {
                var reverse_edge_list = try self.edges.getOrPut(dst);
                if (!reverse_edge_list.found_existing) {
                    reverse_edge_list.value_ptr.* = std.ArrayListUnmanaged(EdgeT){};
                }
                try reverse_edge_list.value_ptr.append(self.allocator, try EdgeT.init(self.allocator, dst, src, if (weighted) weight.? else {}));
                std.debug.print("[ADD EDGE] (UNDIRECTED) Added reverse edge {} -> {}\n", .{ dst, src });

                if (self.heterogeneous) {
                    try self.edge_types.?.put(std.hash.Wyhash.hash(0, std.mem.asBytes(&generateEdgeKey(dst, src))), try self.allocator.dupe(u8, edge_type.?));
                }
            }
        }

        /// 🚀 Remove Edge (with Explicit Debugging)
        pub fn removeEdge(self: *@This(), src: u64, dst: u64) void {
            std.debug.print("[REMOVE EDGE] Attempting to remove edge {} -> {}\n", .{ src, dst });

            const edge_key = generateEdgeKey(src, dst);
            const hashed_key = hashEdgeKey(edge_key);

            if (self.edges.getPtr(src)) |edges| {
                std.debug.print("[REMOVE EDGE] Found edges for {}\n", .{src});

                var i: usize = 0;
                var removed = false;
                while (i < edges.items.len) {
                    if (edges.items[i].dst == dst) {
                        std.debug.print("[REMOVE EDGE] Found edge {} -> {} at index {}. Removing...\n", .{ src, dst, i });
                        _ = edges.orderedRemove(i);
                        removed = true;
                        break;
                    }
                    i += 1;
                }

                if (!removed) {
                    std.debug.print("[REMOVE EDGE] WARNING: Edge {} -> {} was NOT found!\n", .{ src, dst });
                }

                std.debug.print("[REMOVE EDGE] AFTER REMOVE: Edges from {}: {}\n", .{ src, edges.items.len });

                if (edges.items.len == 0) {
                    std.debug.print("[REMOVE EDGE] No more edges from {}. Removing entry from map.\n", .{src});

                    if (directed) {
                        edges.deinit();
                    } else {
                        edges.deinit(self.allocator);
                    }
                    _ = self.edges.remove(src);
                }
            } else {
                std.debug.print("[REMOVE EDGE] WARNING: No edges exist for {}. Skipping removal.\n", .{src});
            }

            if (!directed) {
                if (self.edges.getPtr(dst)) |edges| {
                    std.debug.print("[REMOVE EDGE] Found edges for {} (UNDIRECTED).\n", .{dst});

                    var i: usize = 0;
                    var removed = false;
                    while (i < edges.items.len) {
                        if (edges.items[i].dst == src) {
                            std.debug.print("[REMOVE EDGE] Found edge {} -> {} (UNDIRECTED) at index {}. Removing...\n", .{ dst, src, i });
                            _ = edges.orderedRemove(i);
                            removed = true;
                            break;
                        }
                        i += 1;
                    }

                    if (!removed) {
                        std.debug.print("[REMOVE EDGE] WARNING: Edge {} -> {} (UNDIRECTED) was NOT found!\n", .{ dst, src });
                    }

                    std.debug.print("[REMOVE EDGE] AFTER REMOVE (UNDIRECTED): Edges from {}: {}\n", .{ dst, edges.items.len });

                    if (edges.items.len == 0) {
                        std.debug.print("[REMOVE EDGE] No more edges from {} (UNDIRECTED). Removing entry from map.\n", .{dst});

                        edges.deinit(self.allocator);
                        _ = self.edges.remove(dst);
                    }
                } else {
                    std.debug.print("[REMOVE EDGE] WARNING: No edges exist for {} (UNDIRECTED). Skipping removal.\n", .{dst});
                }
            }

            if (self.heterogeneous) {
                const wasRemoved = self.edge_types.?.remove(hashed_key);
                std.debug.print("[REMOVE EDGE] Removed heterogeneous edge entry? {}\n", .{wasRemoved});
            }
        }

        /// 🚀 Cycle Detection (Added this function)
        fn hasCycle(self: *@This(), current: u64, target: u64, visited: *std.AutoHashMap(u64, bool)) bool {
            if (current == target) return true;

            if (visited.get(current) != null) return false;
            visited.put(current, true) catch return false;

            if (self.edges.get(current)) |edges| {
                for (edges.items) |edge| {
                    if (self.hasCycle(edge.dst, target, visited)) return true;
                }
            }

            _ = visited.remove(current);
            return false;
        }

        /// 🚀 Helper Functions
        fn generateEdgeKey(src: u64, dst: u64) u128 {
            return (@as(u128, src) << 64) | dst;
        }

        fn hashEdgeKey(edge_key: u128) u64 {
            return std.hash.Wyhash.hash(0, std.mem.asBytes(&edge_key));
        }

        pub fn getNodeType(self: *const @This(), id: u64) ?[]const u8 {
            if (!self.heterogeneous) return null;
            return self.node_types.?.get(id);
        }

        pub fn getEdgeType(self: *@This(), src: u64, dst: u64) ?[]const u8 {
            if (!self.heterogeneous) return null;
            const edge_key = generateEdgeKey(src, dst);
            const hashed_key = hashEdgeKey(edge_key);
            return self.edge_types.?.get(hashed_key);
        }

        pub fn debugPrint(self: *@This()) void {
            std.debug.print("Graph:\n", .{});
            var node_it = self.nodes.iterator();
            while (node_it.next()) |entry| {
                std.debug.print("  Node {}: \"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.label });
            }

            var edge_it = self.edges.iterator();
            while (edge_it.next()) |entry| {
                std.debug.print("  Edges from {}:\n", .{entry.key_ptr.*});
                for (entry.value_ptr.items) |edge| {
                    std.debug.print("    -> {} (Weight: {d})\n", .{ edge.dst, if (weighted) edge.weight else 0.0 });
                }
            }
        }
    };
}

test "Graph: Initialize and Deinitialize" {
    var g = Graph(true, false, true).init(std.testing.allocator);
    defer g.deinit();

    try std.testing.expectEqual(@as(usize, 0), g.nodes.count());
    try std.testing.expectEqual(@as(usize, 0), g.edges.count());
}

test "Graph: Add Nodes (Homogeneous)" {
    var g = Graph(true, false, true).init(std.testing.allocator);
    defer g.deinit();

    try g.addNode(1, "NodeA", null);
    try g.addNode(2, "NodeB", null);

    try std.testing.expect(g.nodes.contains(1));
    try std.testing.expect(g.nodes.contains(2));
}

test "Graph: Add Nodes (Heterogeneous)" {
    var g = Graph(true, false, true).init(std.testing.allocator);
    defer g.deinit();

    try g.convertToHeterogeneous();
    try g.addNode(1, "NodeA", "TypeA");
    try g.addNode(2, "NodeB", "TypeB");

    try std.testing.expectEqualStrings("TypeA", g.getNodeType(1).?);
    try std.testing.expectEqualStrings("TypeB", g.getNodeType(2).?);
}

test "Graph: Remove Node" {
    var g = Graph(true, false, true).init(std.testing.allocator);
    defer g.deinit();

    try g.addNode(1, "NodeA", null);
    try g.addNode(2, "NodeB", null);
    try g.addEdge(1, 2, 3.5, null);

    g.removeNode(1);

    try std.testing.expect(!g.nodes.contains(1));
    try std.testing.expect(g.edges.get(1) == null);
}

test "Graph: Add Edges (Homogeneous Directed)" {
    var g = Graph(true, false, true).init(std.testing.allocator);
    defer g.deinit();

    try g.addNode(1, "NodeA", null);
    try g.addNode(2, "NodeB", null);
    try g.addEdge(1, 2, 3.5, null);

    try std.testing.expect(g.edges.contains(1));
    try std.testing.expectEqual(@as(usize, 1), g.edges.get(1).?.items.len);
}

test "Graph: Add and Remove Edges (Homogeneous Undirected)" {
    var g = Graph(false, false, true).init(std.testing.allocator);
    defer g.deinit();

    try g.addNode(1, "NodeA", null);
    try g.addNode(2, "NodeB", null);

    std.debug.print("Checking edges[1] before add: {}\n", .{g.edges.contains(1)});

    std.debug.print("BEFORE ADD: Edges from 1: {}\n", .{if (g.edges.contains(1)) g.edges.get(1).?.items.len else 0});
    try g.addEdge(1, 2, 3.5, null);
    std.debug.print("AFTER ADD: Edges from 1: {}\n", .{if (g.edges.contains(1)) g.edges.get(1).?.items.len else 0});

    // ✅ Ensure edges exist before removal
    try std.testing.expectEqual(@as(usize, 1), if (g.edges.contains(1)) g.edges.get(1).?.items.len else 0);
    try std.testing.expectEqual(@as(usize, 1), if (g.edges.contains(2)) g.edges.get(2).?.items.len else 0);

    g.removeEdge(1, 2);
    std.debug.print("AFTER REMOVE: Edges from 1: {}\n", .{if (g.edges.contains(1)) g.edges.get(1).?.items.len else 0});

    // 🚀 Final Fix: Check `edges.contains()` before accessing `.items`
    try std.testing.expectEqual(@as(usize, 0), if (g.edges.contains(1)) g.edges.get(1).?.items.len else 0);
    try std.testing.expectEqual(@as(usize, 0), if (g.edges.contains(2)) g.edges.get(2).?.items.len else 0);
}

test "Graph: Add Edges (Heterogeneous)" {
    var g = Graph(true, false, true).init(std.testing.allocator);
    defer g.deinit();

    try g.convertToHeterogeneous();
    try g.addNode(1, "NodeA", "TypeA");
    try g.addNode(2, "NodeB", "TypeB");
    try g.addEdge(1, 2, 2.5, "Strong Connection");

    try std.testing.expectEqualStrings("Strong Connection", g.getEdgeType(1, 2).?);
}

test "Graph: Cycle Detection (Acyclic Graphs)" {
    var g = Graph(true, true, false).init(std.testing.allocator);
    defer g.deinit();

    try g.addNode(1, "A", null);
    try g.addNode(2, "B", null);
    try g.addEdge(1, 2, {}, null);

    try std.testing.expectError(error.CycleDetected, g.addEdge(2, 1, {}, null));
}

test "Graph: Remove Edge" {
    var g = Graph(true, false, true).init(std.testing.allocator);
    defer g.deinit();

    try g.addNode(1, "NodeA", null);
    try g.addNode(2, "NodeB", null);
    try g.addEdge(1, 2, 4.5, null);

    g.removeEdge(1, 2);

    try std.testing.expectEqual(@as(usize, 0), if (g.edges.get(1)) |e| e.items.len else 0);
}

test "Graph: Debug Print" {
    var g = Graph(true, false, true).init(std.testing.allocator);
    defer g.deinit();

    try g.addNode(1, "A", null);
    try g.addNode(2, "B", null);
    try g.addEdge(1, 2, 4.5, null);

    g.debugPrint();
}
