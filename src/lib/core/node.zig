const std = @import("std");

const ValueType = union(enum) {
    int: i64,
    float: f64,
    boolean: bool,
    string: []const u8,
};

pub const Node = struct {
    allocator: std.mem.Allocator,
    id: u64,
    label: []const u8,
    data: std.StringHashMap(ValueType),

    pub fn init(allocator: std.mem.Allocator, id: u64, label: []const u8) !Node {
        return Node{
            .allocator = allocator,
            .id = id,
            .label = try allocator.dupe(u8, label),
            .data = std.StringHashMap(ValueType).init(allocator),
        };
    }

    pub fn deinit(self: *Node) void {
        self.allocator.free(self.label);

        var iter = self.data.iterator();
        while (iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);

            // ✅ Ensure we only free memory if it's a string
            if (entry.value_ptr.* == .string) {
                self.allocator.free(entry.value_ptr.string);
            }
        }

        self.data.deinit();
    }

    pub fn getData(self: *const Node, key: []const u8) ?*const ValueType {
        if (key.len == 0) return null; // 🚀 Return null immediately if key is empty

        return self.data.getPtr(key);
    }

    pub fn setData(self: *Node, key: []const u8, value: ValueType) !void {
        if (key.len == 0) return error.InvalidKey; // 🚀 Prevents empty keys

        // ✅ Check if key exists before overwriting
        if (self.data.getPtr(key)) |existing_value| {
            if (existing_value.* == .string) {
                self.allocator.free(existing_value.string);
            }
        }

        // ✅ Retrieve old key pointer correctly
        var old_key_ptr: ?[]const u8 = null;
        if (self.data.getKeyPtr(key)) |existing_key_ptr| {
            old_key_ptr = existing_key_ptr.*;
        }

        // ✅ Remove existing key before replacing
        if (self.data.remove(key)) {
            if (old_key_ptr) |key_str| {
                self.allocator.free(key_str); // Free old key memory safely
            }
        }

        // ✅ Allocate new key and value
        const key_dup = try self.allocator.dupe(u8, key);
        var value_dup: ValueType = value;
        if (value == .string) {
            value_dup.string = try self.allocator.dupe(u8, value.string);
        }

        // ✅ Insert into hashmap
        try self.data.put(key_dup, value_dup);
    }

    pub fn removeData(self: *Node, key: []const u8) !void {
        if (key.len == 0) return error.InvalidKey; // 🚀 Prevents empty keys

        // ✅ Ensure key exists before removing
        if (self.data.getPtr(key)) |value| {
            if (value.* == .string) {
                self.allocator.free(value.string);
            }
        } else {
            return error.KeyNotFound; // 🚀 Explicit error when key does not exist
        }

        // ✅ Retrieve the actual key stored in the hashmap before modifying
        var old_key_ptr: ?[]const u8 = null;
        if (self.data.getKeyPtr(key)) |stored_key_ptr| {
            old_key_ptr = stored_key_ptr.*;
        }

        // ✅ Remove key-value pair before freeing memory
        if (self.data.remove(key)) {
            if (old_key_ptr) |key_str| {
                self.allocator.free(key_str);
            }
        } else {
            return error.KeyNotFound; // 🚀 Safety check: ensure key actually got removed
        }
    }
};

// Unit Tests
test "Node: Initialization & Deinitialization" {
    var n = try Node.init(std.testing.allocator, 1, "Test Node");
    defer n.deinit();
    try std.testing.expectEqual(@as(u64, 1), n.id);
    try std.testing.expectEqualStrings("Test Node", n.label);
}

test "Node: Set and Get Data" {
    var n = try Node.init(std.testing.allocator, 2, "Data Node");
    defer n.deinit();

    try n.setData("key1", ValueType{ .string = "value1" });
    try n.setData("key2", ValueType{ .int = 42 });

    try std.testing.expectEqualStrings("value1", n.getData("key1").?.string);
    try std.testing.expectEqual(@as(i64, 42), n.getData("key2").?.int);
}

test "Node: Overwrite Existing Data" {
    var n = try Node.init(std.testing.allocator, 3, "Overwrite Test");
    defer n.deinit();

    try n.setData("key", ValueType{ .string = "initial" });
    try n.setData("key", ValueType{ .string = "updated" });

    try std.testing.expectEqualStrings("updated", n.getData("key").?.string);
}

test "Node: Remove Data" {
    var n = try Node.init(std.testing.allocator, 4, "Remove Test");
    defer n.deinit();

    try n.setData("key", ValueType{ .string = "to be removed" });
    try n.removeData("key"); // ✅ Now catching potential errors

    try std.testing.expect(n.getData("key") == null);
}

// 🚀 New Tests: Edge Cases
test "Node: Handle Empty Key" {
    var n = try Node.init(std.testing.allocator, 5, "Empty Key Test");
    defer n.deinit();

    // Expect setData to fail with an InvalidKey error
    try std.testing.expectError(error.InvalidKey, n.setData("", ValueType{ .string = "empty" }));

    // Expect getData to return null for an empty key
    try std.testing.expect(n.getData("") == null);

    // Expect removeData to fail with an InvalidKey error
    try std.testing.expectError(error.InvalidKey, n.removeData(""));
}

test "Node: Overwrite Stress Test" {
    var n = try Node.init(std.testing.allocator, 6, "Overwrite Stress Test");
    defer n.deinit();

    try n.setData("key", ValueType{ .string = "first" });
    try n.setData("key", ValueType{ .string = "second" });
    try n.setData("key", ValueType{ .string = "third" });

    try std.testing.expectEqualStrings("third", n.getData("key").?.string);
}

test "Node: Remove Non-Existent Key" {
    var n = try Node.init(std.testing.allocator, 7, "Remove Non-Existent");
    defer n.deinit();

    // ✅ Expect `removeData` to return an error for a non-existent key
    try std.testing.expectError(error.KeyNotFound, n.removeData("does_not_exist"));

    try std.testing.expect(n.getData("does_not_exist") == null);
}
