const std = @import("std");

/// 🚀 Generic Edge Definition with Arbitrary Data Support
pub fn Edge(comptime weighted: bool) type {
    return struct {
        src: u64,
        dst: u64,
        data: std.StringHashMap([]const u8), // ✅ Arbitrary attributes
        weight: if (weighted) f64 else void, // ✅ Conditionally include weight
        allocator: std.mem.Allocator, // ✅ Store allocator for cleanup

        /// 🚀 Initialize Edge
        pub fn init(allocator: std.mem.Allocator, src: u64, dst: u64, weight: if (weighted) f64 else void) !@This() {
            return @This(){
                .src = src,
                .dst = dst,
                .data = std.StringHashMap([]const u8).init(allocator),
                .weight = if (weighted) weight else {},
                .allocator = allocator,
            };
        }

        /// 🚀 Deinitialize Edge (Fixing Memory Leaks & Double-Free Issues)
        pub fn deinit(self: *@This()) void {
            var iter = self.data.iterator();
            while (iter.next()) |entry| {
                // ✅ Free the key if it was allocated
                if (entry.key_ptr.*.len > 0) {
                    self.allocator.free(entry.key_ptr.*);
                }

                // ✅ Free the value if it was allocated
                if (entry.value_ptr.*.len > 0) {
                    self.allocator.free(entry.value_ptr.*);
                }
            }
            self.data.deinit(); // ✅ Clean up the hash map itself
        }

        /// 🚀 Set Data with Safe Memory Allocation
        pub fn setData(self: *@This(), key: []const u8, value: []const u8) !void {
            const key_alloc = try self.allocator.dupe(u8, key); // ✅ Copy key safely
            const value_alloc = try self.allocator.dupe(u8, value); // ✅ Copy value safely
            try self.data.put(key_alloc, value_alloc);
        }

        /// 🚀 Retrieve Data
        pub fn getData(self: *@This(), key: []const u8) ?[]const u8 {
            return self.data.get(key);
        }

        /// 🚀 Debug Print for Inspection
        pub fn debugPrint(self: *const @This()) void {
            if (weighted) {
                std.debug.print("Edge {} -> {} (Weight: {d})\n", .{ self.src, self.dst, self.weight });
            } else {
                std.debug.print("Edge {} -> {}\n", .{ self.src, self.dst });
            }

            var iter = self.data.iterator();
            while (iter.next()) |entry| {
                std.debug.print("  {s}: \"{s}\"\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
        }
    };
}

// ✅ Unit Test for Proper Memory Management
test "Edge: Memory Management" {
    const allocator = std.testing.allocator;

    // ✅ Weighted Edge
    const WeightedEdge = Edge(true);
    var e = try WeightedEdge.init(allocator, 1, 2, 5.7);
    try e.setData("type", "friendship");
    e.debugPrint();
    e.deinit(); // ✅ Free memory safely

    // ✅ Unweighted Edge
    const UnweightedEdge = Edge(false);
    var e2 = try UnweightedEdge.init(allocator, 3, 4, {});
    try e2.setData("type", "follows");
    e2.debugPrint();
    e2.deinit(); // ✅ Free memory safely
}
