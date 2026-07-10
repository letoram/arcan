// Zig reimplementation of cli_parse.c
// CLI argument parser for arcan terminal frameserver.
//
// Exports: extract_argv
//
const std = @import("std");

const shmif = @import("shmif_types");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const struct_group_ent = shmif.struct_group_ent;
    pub const struct_argv_parse_opt = shmif.struct_argv_parse_opt;
};

const malloc = shmif.malloc;
const free = shmif.free;
const strdup = shmif.strdup;
const strlen = shmif.strlen;
const memset = shmif.memset;

// test vector:
//  this is just a string => {this, is, just, a, string, NULL}
//  this 'can be' grouped => {this, can be, grouped, NULL}
//  this `subexp` => {this, (expand-res), NULL}

/// unescaped presence of any of these characters enters that parsing group,
/// and when the next unescaped presence of the same character occurs, split
/// off the current work buffer into the argv array
fn find_escape_group(grp: [*c]c.struct_group_ent, ch: u8) isize {
    var i: usize = 0;
    while (grp[i].enter != 0) : (i += 1) {
        if (ch == @as(u8, @bitCast(grp[i].enter)))
            return @intCast(i);
    }
    return -1;
}

/// C char** as a Zig pointer — nullable entries (for prepad slots and NULL terminator).
/// [*c][*c]u8 in Zig: outer [*c] is many-pointer (nullable C-style), inner [*c] likewise.
export fn extract_argv(
    message: [*c]const u8,
    opts: c.struct_argv_parse_opt,
    esc_ind: *isize,
) callconv(.c) [*c][*c]u8 {
    const groups = opts.groups;
    const sep: u8 = @bitCast(opts.sep);

    // just overfit, not worth the extra work
    const len: usize = strlen(message) + 1;
    const len_buf_sz: usize = @sizeOf([*c]u8) * (len + opts.prepad);

    const argv_raw: *anyopaque = malloc(len_buf_sz) orelse return null;
    const argv: [*][*c]u8 = @ptrCast(@alignCast(argv_raw));
    _ = memset(argv_raw, 0, len_buf_sz);

    var arg_i: usize = opts.prepad;
    var esc_ign: bool = false;

    const work_raw: *anyopaque = malloc(len) orelse {
        free(argv_raw);
        return null;
    };
    const work: [*]u8 = @ptrCast(work_raw);
    var pos: usize = 0;
    work[0] = 0;
    esc_ind.* = -1;

    // Main parse loop — uses labeled block so error paths can break out.
    const success: bool = success: {
        var i: usize = 0;
        while (i < len - 1) : (i += 1) {
            const ch: u8 = message[i];

            // first backslash outside of a postprocessing scope, consume on use
            if (esc_ign) {
                switch (ch) {
                    '\\' => {
                        work[pos] = ch;
                        pos += 1;
                    },
                    'n' => {
                        work[pos] = '\n';
                        pos += 1;
                    },
                    't' => {
                        work[pos] = '\t';
                        pos += 1;
                    },
                    ' ' => {
                        work[pos] = ' ';
                        pos += 1;
                    },
                    // re-add the backslash for non-group characters
                    else => {
                        if (find_escape_group(groups, ch) == -1 and ch != sep) {
                            work[pos] = '\\';
                            pos += 1;
                        }
                        work[pos] = ch;
                        pos += 1;
                    },
                }
                esc_ign = false;
                continue;
            }

            // in escaping group? check for exit and forward or leave
            if (esc_ind.* != -1) {
                const group_idx: usize = @intCast(esc_ind.*);

                // constraint: expansion can only yield one discrete argument
                if (groups[group_idx].leave == @as(i8, @bitCast(ch))) {
                    work[pos] = 0;
                    if (groups[group_idx].expand) |exp_fn| {
                        const group_ptr: *c.struct_group_ent = @ptrCast(groups + group_idx);
                        const exp: [*c]u8 = exp_fn(group_ptr, work);
                        esc_ind.* = -1;
                        if (exp != null) {
                            argv[arg_i] = exp;
                            arg_i += 1;
                        }
                    } else {
                        esc_ind.* = -1;
                    }
                }

                pos = 0;
                esc_ind.* = -1;
                continue;
            }

            // got one of the escape groups that might warrant different
            // postprocessing or interpretation
            const ind: isize = find_escape_group(groups, ch);

            if (ind != -1) {
                if (pos != 0) {
                    work[pos] = 0;
                    argv[arg_i] = strdup(work);
                    arg_i += 1;
                }

                pos = 0;
                esc_ind.* = ind;
                continue;
            }

            // outside escape group, but escape next character
            if (ch == '\\') {
                esc_ign = true;
                continue;
            }

            // finish and append to argv, ignore leading whitespace
            if (ch == sep) {
                if (pos != 0) {
                    work[pos] = 0;
                    argv[arg_i] = strdup(work);
                    arg_i += 1;
                    pos = 0;
                }
                continue;
            }

            // or append to work
            work[pos] = ch;
            pos += 1;
        }

        // In escape state? parsing error
        if (esc_ign)
            break :success false;

        // a special attribute is required for ending while in group state,
        // this will permit things like $HOME to have an escape group of $
        if (esc_ind.* != -1) {
            const group_idx: usize = @intCast(esc_ind.*);

            if (!groups[group_idx].leave_eol)
                break :success false;

            work[pos] = 0;
            if (groups[group_idx].expand) |exp_fn| {
                const group_ptr: *c.struct_group_ent = @ptrCast(groups + group_idx);
                const exp: [*c]u8 = exp_fn(group_ptr, work);
                esc_ind.* = -1;
                if (exp != null) {
                    argv[arg_i] = exp;
                    arg_i += 1;
                }
            } else {
                esc_ind.* = -1;
            }
        }

        // argv is already null terminated, but might have dangling arg
        if (pos != 0) {
            work[pos] = 0;
            argv[arg_i] = strdup(work);
            arg_i += 1;
        }

        free(work_raw);
        break :success true;
    };

    if (!success) {
        // err_out: free work, free all argv entries, free argv
        free(work_raw);
        for (0..len) |j| {
            const entry: [*c]u8 = argv[j];
            if (entry != null)
                free(entry);
        }
        free(argv_raw);
        if (esc_ign)
            esc_ind.* = @as(isize, @intCast(len));
        return null;
    }

    return @ptrCast(argv);
}
