// Zig port of posix/strip_traverse.c
// Path traversal validator: rejects paths that escape root via ../

const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

extern fn arcan_warning(msg: [*c]const u8, ...) callconv(.c) void;

export fn verify_traverse(input_arg: [*c]const u8) [*c]const u8 {
    if (is_freestanding) return input_arg;
    var input = input_arg;
    if (input == null) return null;

    var level: i32 = 0;
    var gotch: i32 = 0;
    var dc: i32 = 0;

    while (input[0] != 0) {
        if (input[0] == '.') {
            dc += 1;
        } else if (input[0] == '/') {
            if (dc == 2 and gotch == 0) {
                level -= 1;
                if (level < 0) {
                    // traversal outside root
                    return null;
                }
            } else if (gotch > 0) {
                level += 1;
            }
            gotch = 0;
            dc = 0;
        } else {
            gotch += 1;
        }
        input += 1;
    }

    if (dc == 2 and gotch == 0 and level == 0) {
        // traversal outside root
        return null;
    }

    return input;
}
