/// shmif argument parsing API tests
///
/// Tier 3: Tests that exercise the arg_arr parsing functions (arg_unpack,
/// arg_lookup, arg_add, arg_remove, arg_serialize, arg_cleanup).
/// These are pure C library calls — no C helpers needed.
const std = @import("std");
const testing = std.testing;

const c = @import("shmif_types");

// Helper

/// Call arg_cleanup on an arg_arr, setting the pointer to null afterward.
fn cleanup(arr: *?[*]c.struct_arg_arr) void {
    if (arr.*) |ptr| {
        c.arg_cleanup(ptr);
        arr.* = null;
    }
}

// 3a. arg_unpack basic

test "unpack simple key=val" {
    var arr = c.arg_unpack("key=val");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    var found: [*c]const u8 = null;
    const ok = c.arg_lookup(arr, "key", 0, &found);
    try testing.expect(ok);
    try testing.expect(found != null);
    try testing.expectEqualStrings("val", std.mem.span(found));
}

test "unpack multiple pairs" {
    var arr = c.arg_unpack("a=1:b=2:c=3");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    var fa: [*c]const u8 = null;
    var fb: [*c]const u8 = null;
    var fc: [*c]const u8 = null;
    try testing.expect(c.arg_lookup(arr, "a", 0, &fa));
    try testing.expect(c.arg_lookup(arr, "b", 0, &fb));
    try testing.expect(c.arg_lookup(arr, "c", 0, &fc));
    try testing.expectEqualStrings("1", std.mem.span(fa));
    try testing.expectEqualStrings("2", std.mem.span(fb));
    try testing.expectEqualStrings("3", std.mem.span(fc));
}

test "unpack key-only (no value)" {
    var arr = c.arg_unpack("flag");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    var found: [*c]const u8 = null;
    const ok = c.arg_lookup(arr, "flag", 0, &found);
    try testing.expect(ok);
    // Key-only entries have null value
    try testing.expect(found == null);
}

test "unpack empty string" {
    var arr = c.arg_unpack("");
    defer cleanup(&arr);
    // Should return non-null (allocated but empty array)
    try testing.expect(arr != null);

    // Lookup should fail for any key
    var found: [*c]const u8 = null;
    const ok = c.arg_lookup(arr, "anything", 0, &found);
    try testing.expect(!ok);
}

test "unpack null returns null" {
    const arr = c.arg_unpack(null);
    try testing.expect(arr == null);
}

// 3b. arg_lookup

test "arg_lookup missing key returns false" {
    var arr = c.arg_unpack("a=1:b=2");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    var found: [*c]const u8 = null;
    const ok = c.arg_lookup(arr, "missing", 0, &found);
    try testing.expect(!ok);
}

test "arg_lookup indexed (2nd match)" {
    var arr = c.arg_unpack("k=a:k=b");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    var first: [*c]const u8 = null;
    var second: [*c]const u8 = null;
    try testing.expect(c.arg_lookup(arr, "k", 0, &first));
    try testing.expect(c.arg_lookup(arr, "k", 1, &second));
    try testing.expectEqualStrings("a", std.mem.span(first));
    try testing.expectEqualStrings("b", std.mem.span(second));
}

// 3c. serialize round-trip

test "serialize round-trip" {
    var arr = c.arg_unpack("x=10:y=20");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    const serialized = c.arg_serialize(arr);
    try testing.expect(serialized != null);
    defer std.c.free(serialized);

    const str = std.mem.span(serialized.?);
    // The serialized form should contain both key=val pairs
    try testing.expect(std.mem.indexOf(u8, str, "x=10") != null);
    try testing.expect(std.mem.indexOf(u8, str, "y=20") != null);
}

// 3d. arg_add / arg_remove

test "arg_add new key" {
    var arr = c.arg_unpack("a=1");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    const added = c.arg_add(null, &arr, "b", "2", false);
    try testing.expect(added);

    var found: [*c]const u8 = null;
    try testing.expect(c.arg_lookup(arr, "b", 0, &found));
    try testing.expectEqualStrings("2", std.mem.span(found));
}

test "arg_add replace existing" {
    var arr = c.arg_unpack("key=old");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    const added = c.arg_add(null, &arr, "key", "new", true);
    try testing.expect(added);

    var found: [*c]const u8 = null;
    try testing.expect(c.arg_lookup(arr, "key", 0, &found));
    try testing.expectEqualStrings("new", std.mem.span(found));
}

test "arg_remove key" {
    var arr = c.arg_unpack("a=1:b=2");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    c.arg_remove(arr, "a");

    var found: [*c]const u8 = null;
    const ok = c.arg_lookup(arr, "a", 0, &found);
    try testing.expect(!ok);

    // b should still be there
    try testing.expect(c.arg_lookup(arr, "b", 0, &found));
}

test "arg_remove nonexistent key (no crash)" {
    var arr = c.arg_unpack("a=1");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    // Should not crash
    c.arg_remove(arr, "nonexistent");

    // Original key still present
    var found: [*c]const u8 = null;
    try testing.expect(c.arg_lookup(arr, "a", 0, &found));
}

// 3e. arg_cleanup

test "arg_cleanup does not crash" {
    const arr = c.arg_unpack("a=1:b=2:c=3");
    try testing.expect(arr != null);
    c.arg_cleanup(arr.?);
    // If we reach here, cleanup didn't crash
}

// 3f. Edge cases

test "long key=value survives round-trip" {
    // Build a long key=value string: 200-char key, 200-char value
    const long_key = "k" ** 200;
    const long_val = "v" ** 200;
    const input = long_key ++ "=" ++ long_val;

    var arr = c.arg_unpack(input);
    defer cleanup(&arr);
    try testing.expect(arr != null);

    var found: [*c]const u8 = null;
    const ok = c.arg_lookup(arr, long_key, 0, &found);
    try testing.expect(ok);
    try testing.expect(found != null);
    try testing.expectEqualStrings(long_val, std.mem.span(found));
}

test "special characters in values" {
    // Spaces in values should work
    var arr = c.arg_unpack("msg=hello world");
    defer cleanup(&arr);
    try testing.expect(arr != null);

    var found: [*c]const u8 = null;
    const ok = c.arg_lookup(arr, "msg", 0, &found);
    try testing.expect(ok);
    try testing.expect(found != null);
    try testing.expectEqualStrings("hello world", std.mem.span(found));
}
