const std = @import("std");
const c = @import("arcan_str");

const expectEqual = std.testing.expectEqual;
const expectEqualSlices = std.testing.expectEqualSlices;

fn arcan_str(str: []const u8) c.arcan_str {
    return c.arcan_str{
        .ptr = @constCast(str.ptr),
        .len = str.len,
        .mut = false,
    };
}

fn arcan_str_mut(str: []u8) c.arcan_str {
    return c.arcan_str{
        .ptr = str.ptr,
        .len = str.len,
        .mut = true,
    };
}

fn arcan_str_slice(str: c.arcan_str) []const u8 {
    return str.ptr[0..str.len];
}

fn arcan_str_empty() c.arcan_str {
    return c.arcan_str{ .ptr = null, .len = 0, .mut = false };
}

test "arcan_str_fromcstr" {
    const str = "Testing";
    const s1 = c.arcan_str_fromcstr(str.ptr);
    try expectEqual(str.len, s1.len);
    try expectEqual(str.ptr, s1.ptr);

    const s2 = c.arcan_str_fromcstr(null);
    try expectEqual(false, c.arcan_strvalid(s2));

    const empty = "\x00";
    const s3 = c.arcan_str_fromcstr(empty.ptr);
    try expectEqual(0, s3.len);
    try expectEqual(empty.ptr, s3.ptr);
}

test "arcan_stridx" {
    const str = arcan_str("Hello");
    try expectEqual(str.ptr, c.arcan_stridx(str, 0));
    try expectEqual(str.ptr + 4, c.arcan_stridx(str, 4));
    try expectEqual(null, c.arcan_stridx(str, 5));
    try expectEqual(str.ptr + 4, c.arcan_stridx(str, -1));
    try expectEqual(str.ptr, c.arcan_stridx(str, -5));
    try expectEqual(null, c.arcan_stridx(str, -6));
}

test "arcan_strcmp" {
    const s1 = arcan_str("hello");
    const s2 = arcan_str("hello world");
    const s3 = arcan_str("hell!");
    try expectEqual(0, c.arcan_strcmp(s1, s1));
    try expectEqual(-1, c.arcan_strcmp(s1, s2));
    try expectEqual(1, c.arcan_strcmp(s1, s3));
    try expectEqual(-1, c.arcan_strcmp(s3, s1));

    const s2_sub = c.arcan_str{ .ptr = s2.ptr, .len = 5 };
    try expectEqual(0, c.arcan_strcmp(s1, s2_sub));
}

test "arcan_strchr" {
    const s1 = arcan_str("Some string");
    try expectEqual(s1.ptr, c.arcan_strchr(s1, 'S'));
    try expectEqual(&s1.ptr[5], c.arcan_strchr(s1, 's'));
    try expectEqual(null, c.arcan_strchr(s1, 'w'));
}

test "arcan_strcpy" {
    var destarr = "world".*;
    const src = arcan_str("hello");
    const dest = arcan_str_mut(&destarr);
    const result = c.arcan_strcpy(dest, src);

    try expectEqual(result.ptr, dest.ptr);
    try expectEqual(result.len, dest.len);
    try expectEqualSlices(u8, arcan_str_slice(src), arcan_str_slice(result));
}

test "arcan_strsub" {
    const str = arcan_str("One two three");

    const s1 = c.arcan_strsub(str, 4, 7);
    try expectEqualSlices(u8, "two", arcan_str_slice(s1));

    const s2 = c.arcan_strsub(str, 4, 4);
    try expectEqualSlices(u8, "", arcan_str_slice(s2));

    const s3 = c.arcan_strsub(str, 4, 0);
    try expectEqual(false, c.arcan_strvalid(s3));

    const s4 = c.arcan_strsub(str, 4, 100);
    try expectEqual(false, c.arcan_strvalid(s4));

    const s5 = c.arcan_strsub(str, 8, 13);
    try expectEqualSlices(u8, "three", arcan_str_slice(s5));
}

test "arcan_strprefix" {
    const str = arcan_str("one two three");
    const p1 = arcan_str("one");
    const p2 = arcan_str("two");

    try expectEqual(true, c.arcan_strprefix(str, p1));
    try expectEqual(false, c.arcan_strprefix(str, p2));
}

test "arcan_strpostfix" {
    const str = arcan_str("one two three");
    const p1 = arcan_str("three");
    const p2 = arcan_str("two");

    try expectEqual(true, c.arcan_strpostfix(str, p1));
    try expectEqual(false, c.arcan_strpostfix(str, p2));
}

test "arcan_strstr" {
    const str = arcan_str("one two three");
    const s1 = arcan_str("three");
    const s2 = arcan_str("two");
    const s3 = arcan_str("cow");

    try expectEqual(&str.ptr[8], c.arcan_strstr(str, s1).ptr);
    try expectEqual(&str.ptr[4], c.arcan_strstr(str, s2).ptr);
    try expectEqual(false, c.arcan_strvalid(c.arcan_strstr(str, s3)));
}

test "arcan_strtok" {
    const str = arcan_str(" one two three ");

    var tok = arcan_str_empty();
    try expectEqual(true, c.arcan_strtok(str, &tok, ' '));
    try expectEqualSlices(u8, "", arcan_str_slice(tok));

    try expectEqual(true, c.arcan_strtok(str, &tok, ' '));
    try expectEqualSlices(u8, "one", arcan_str_slice(tok));

    try expectEqual(true, c.arcan_strtok(str, &tok, ' '));
    try expectEqualSlices(u8, "two", arcan_str_slice(tok));

    try expectEqual(true, c.arcan_strtok(str, &tok, ' '));
    try expectEqualSlices(u8, "three", arcan_str_slice(tok));

    try expectEqual(true, c.arcan_strtok(str, &tok, ' '));
    try expectEqualSlices(u8, "", arcan_str_slice(tok));

    try expectEqual(false, c.arcan_strtok(str, &tok, ' '));
}

test "arcan_strglobmatch" {
    const str = arcan_str("One two three");

    try expectEqual(false, c.arcan_strglobmatch(arcan_str_empty(), arcan_str("*"), '*'));
    try expectEqual(false, c.arcan_strglobmatch(str, arcan_str_empty(), '*'));

    try expectEqual(true, c.arcan_strglobmatch(arcan_str(""), arcan_str(""), '*'));
    try expectEqual(true, c.arcan_strglobmatch(arcan_str(""), arcan_str("*"), '*'));
    try expectEqual(false, c.arcan_strglobmatch(arcan_str(" "), arcan_str(""), '*'));

    try expectEqual(true, c.arcan_strglobmatch(str, str, '*'));
    try expectEqual(true, c.arcan_strglobmatch(str, arcan_str("*"), '*'));
    try expectEqual(true, c.arcan_strglobmatch(str, arcan_str("%"), '%'));

    try expectEqual(true, c.arcan_strglobmatch(str, arcan_str("One*"), '*'));
    try expectEqual(true, c.arcan_strglobmatch(str, arcan_str("*two*"), '*'));
    try expectEqual(true, c.arcan_strglobmatch(str, arcan_str("*three"), '*'));
    try expectEqual(true, c.arcan_strglobmatch(str, arcan_str("One*w*three"), '*'));

    try expectEqual(false, c.arcan_strglobmatch(str, arcan_str("One"), '*'));
    try expectEqual(false, c.arcan_strglobmatch(str, arcan_str("two"), '*'));
    try expectEqual(false, c.arcan_strglobmatch(str, arcan_str("three"), '*'));
}
