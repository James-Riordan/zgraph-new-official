const std = @import("std");

/// 🚀 Flexible Value Type for Edge Metadata
const ValueType = union(enum) {
    int: i64,
    float: f64,
    boolean: bool,
    string: []const u8, // ✅ Only allocate strings when necessary
};

/// 🚀 Generic Edge Definition with Arbitrary Data Support
pub fn Edge(comptime weighted: bool) type {
    return struct {
        src: u64,
        dst: u64,
        data: std.StringHashMap(ValueType), // ✅ FIXED: Proper HashMap for Strings
        weight: if (weighted) f64 else void,
        allocator: std.mem.Allocator,

        /// 🚀 Initialize Edge
        pub fn init(allocator: std.mem.Allocator, src: u64, dst: u64, weight: if (weighted) f64 else void) !@This() {
            return @This(){
                .src = src,
                .dst = dst,
                .data = std.StringHashMap(ValueType).init(allocator), // ✅ FIXED
                .weight = if (weighted) weight else {},
                .allocator = allocator,
            };
        }

        /// 🚀 Deinitialize Edge (Prevent Memory Leaks)
        pub fn deinit(self: *@This()) void {
            var iter = self.data.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                if (entry.value_ptr.* == .string) { // ✅ Only free memory for string values
                    self.allocator.free(entry.value_ptr.string);
                }
            }
            self.data.deinit();
        }

        /// 🚀 Set Data with Proper Memory Management
        /// 🚀 Set Data with Proper Memory Management
        pub fn setData(self: *@This(), key: []const u8, value: ValueType) !void {
            if (key.len == 0) return error.InvalidKey; // Prevent empty keys

            // ✅ Free existing value if present
            if (self.data.getPtr(key)) |existing_value| {
                if (existing_value.* == .string) {
                    self.allocator.free(existing_value.string);
                }
            }

            // ✅ Fetch the stored key
            var old_key: ?[]const u8 = null;
            if (self.data.getKeyPtr(key)) |key_ptr| {
                old_key = key_ptr.*;
            }

            // ✅ Remove old key-value pair before inserting a new one
            if (self.data.remove(key)) {
                if (old_key) |key_ptr| {
                    self.allocator.free(key_ptr);
                }
            }

            // ✅ Allocate new key and value
            const key_dup: []const u8 = try self.allocator.dupe(u8, key);
            var value_dup: ValueType = value;

            if (value == .string) {
                value_dup.string = try self.allocator.dupe(u8, value.string);
            }

            try self.data.put(key_dup, value_dup);
        }

        /// 🚀 Retrieve Data (Efficient Pointer-Based Access)
        pub fn getData(self: *@This(), key: []const u8) ?*const ValueType {
            return self.data.getPtr(key);
        }

        /// 🚀 Remove Data (Properly Frees Allocated Strings)
        pub fn removeData(self: *@This(), key: []const u8) !void {
            if (key.len == 0) return error.InvalidKey; // 🚀 Prevents empty keys

            // ✅ Retrieve value before removing
            if (self.data.getPtr(key)) |value| {
                if (value.* == .string) {
                    self.allocator.free(value.string);
                }
            }

            // ✅ Fetch the key stored in the hashmap
            var old_key: ?[]const u8 = null;
            if (self.data.getKeyPtr(key)) |key_ptr| {
                old_key = key_ptr.*;
            }

            // ✅ Remove key-value pair
            if (self.data.remove(key)) {
                if (old_key) |key_ptr| {
                    self.allocator.free(key_ptr);
                }
            } else {
                return error.KeyNotFound; // 🚀 Explicitly return an error if key is missing
            }
        }

        /// 🚀 Debug Print (Handles All `ValueType` Cases)
        pub fn debugPrint(self: *const @This()) void {
            if (weighted) {
                std.debug.print("Edge {} -> {} (Weight: {d})\n", .{ self.src, self.dst, self.weight });
            } else {
                std.debug.print("Edge {} -> {}\n", .{ self.src, self.dst });
            }

            var iter = self.data.iterator();
            while (iter.next()) |entry| {
                std.debug.print("  {s}: ", .{entry.key_ptr.*});

                switch (entry.value_ptr.*) {
                    .int => |v| std.debug.print("{}\n", .{v}),
                    .float => |v| std.debug.print("{d}\n", .{v}),
                    .boolean => |v| std.debug.print("{}\n", .{v}),
                    .string => |v| std.debug.print("\"{s}\"\n", .{v}),
                }
            }
        }
    };
}

// ✅ Unit Test for Proper Memory Management & Error Debugging
test "Edge: Memory Management" {
    const allocator = std.testing.allocator;

    // ✅ Weighted Edge
    const WeightedEdge = Edge(true);
    var e = try WeightedEdge.init(allocator, 1, 2, 5.7);
    defer e.deinit(); // ✅ Ensure cleanup

    try e.setData("type", ValueType{ .string = "friendship" });

    std.testing.expectEqual(@as(u64, 1), e.src) catch |err| {
        std.debug.print("[TEST FAILURE] WeightedEdge Debug:\n", .{});
        e.debugPrint();
        return err;
    };

    std.testing.expectEqual(@as(u64, 2), e.dst) catch |err| {
        std.debug.print("[TEST FAILURE] WeightedEdge Debug:\n", .{});
        e.debugPrint();
        return err;
    };

    std.testing.expectEqual(@as(f64, 5.7), e.weight) catch |err| {
        std.debug.print("[TEST FAILURE] WeightedEdge Debug:\n", .{});
        e.debugPrint();
        return err;
    };

    std.testing.expectEqualStrings("friendship", e.getData("type").?.string) catch |err| {
        std.debug.print("[TEST FAILURE] WeightedEdge Debug:\n", .{});
        e.debugPrint();
        return err;
    };

    // ✅ Unweighted Edge
    const UnweightedEdge = Edge(false);
    var e2 = try UnweightedEdge.init(allocator, 3, 4, {});
    defer e2.deinit(); // ✅ Ensure cleanup

    try e2.setData("type", ValueType{ .string = "follows" });

    std.testing.expectEqual(@as(u64, 3), e2.src) catch |err| {
        std.debug.print("[TEST FAILURE] UnweightedEdge Debug:\n", .{});
        e2.debugPrint();
        return err;
    };

    std.testing.expectEqual(@as(u64, 4), e2.dst) catch |err| {
        std.debug.print("[TEST FAILURE] UnweightedEdge Debug:\n", .{});
        e2.debugPrint();
        return err;
    };

    std.testing.expectEqualStrings("follows", e2.getData("type").?.string) catch |err| {
        std.debug.print("[TEST FAILURE] UnweightedEdge Debug:\n", .{});
        e2.debugPrint();
        return err;
    };
}

// ✅ Debug Print Test (Only Runs If the Test Fails)
test "Edge: Debug Print" {
    const allocator = std.testing.allocator;
    const TestEdge = Edge(true);
    var e = try TestEdge.init(allocator, 10, 20, 3.14);
    defer e.deinit();

    std.testing.expectEqual(@as(f64, 3.14), e.weight) catch |err| {
        std.debug.print("[TEST FAILURE] Edge Debug Print:\n", .{});
        e.debugPrint();
        return err;
    };
}

// ✅ Additional Tests: Ensure removeData() handles errors
test "Edge: Remove Data" {
    const allocator = std.testing.allocator;
    const TestEdge = Edge(true);
    var e = try TestEdge.init(allocator, 1, 2, 5.7);
    defer e.deinit();

    try e.setData("type", ValueType{ .string = "friendship" });

    try e.removeData("type"); // ✅ Try to remove existing key
    try std.testing.expect(e.getData("type") == null);

    // ✅ Try to remove a non-existent key and expect a KeyNotFound error
    try std.testing.expectError(error.KeyNotFound, e.removeData("non_existent"));
}

test "Edge: Overwrite Stress Test" {
    const allocator = std.testing.allocator;
    const TestEdge = Edge(true);
    var e = try TestEdge.init(allocator, 1, 2, 5.7);
    defer e.deinit();

    try e.setData("status", ValueType{ .string = "initial" });
    try e.setData("status", ValueType{ .string = "updated" });
    try e.setData("status", ValueType{ .string = "final" });

    // ✅ Ensure the key still exists
    const status_opt = e.getData("status") orelse return error.StatusNotFound;
    if (status_opt.* != .string) return error.UnexpectedValueType;

    try std.testing.expectEqualStrings("final", status_opt.string);
}
