//! afsrv_terminal — cli=lua-default entry point.
//!
//! Full afsrv_terminal in upstream arcan supports two modes:
//!   1. xterm-style — a child shell process (bash, etc.) behind a VT
//!      emulator (ghostty-vt or suckless ST). Heavy: pulls ghostty-vt
//!      as a remote zon dep and ~2000 lines of VT plumbing.
//!   2. cli=lua — runs lash + hem (Lua REPL) directly INSIDE the
//!      frameserver. Pure Zig, ~250 lines, no remote deps.
//!
//! In may, mode 2 is the DEFAULT — running `afsrv_terminal` with no
//! ARCAN_ARG, or with `ARCAN_ARG=cli=lua`, lands in lash + hem (the
//! user's interactive shell of choice in durian). Mode 1 is opt-in
//! via `ARCAN_ARG=cli=<anything-other-than-lua>` (e.g. `cli=vt`,
//! `cli=bash`) but is NOT yet wired into may's build — it needs
//! ghostty-vt vendoring + tsm/ linking, slated for its own follow-up
//! ticket. Requesting it today gets a clear refusal pointing at that
//! status.
//!
//! Why lua is the default: in durian, both /global/open/terminal
//! (suppl_terminal_build_argenv, no cli=) and /global/open/lash
//! (explicit cli=lua) want lash. Making lua the default lets the
//! former work without forcing every caller to thread cli=lua.
//!
//! Wired into libframeservers via _libframeservers.zig + the
//! `enable_terminal` fsrv_opts flag; afsrv_terminal symlink in
//! `<prefix>/libexec/may/` routes argv[0] sniff to may → frameserver_
//! dispatch → afsrv_terminal export here.

const std = @import("std");
const shmif = @import("shmif_types");
const libc = @import("posix");

const c = struct {
    pub const fprintf = libc.fprintf;
    pub extern "c" var stderr: *libc.FILE;
    pub const arg_lookup = shmif.arg_lookup;
};

// Defined in src/frameserver/terminal/default/cli_lua.zig (pulled into
// the frameservers compile alongside this entry).
extern fn arcterm_luacli_run(
    shmif_ctx: ?*shmif.struct_arcan_shmif_cont,
    args: ?*shmif.struct_arg_arr,
) c_int;

export fn afsrv_terminal(
    con: ?*shmif.struct_arcan_shmif_cont,
    args: ?*shmif.struct_arg_arr,
) callconv(.c) c_int {
    if (con == null) return 1;

    // Default is cli=lua (lash + hem). The xterm/bash/ghostty path is
    // opt-in via `ARCAN_ARG=cli=<anything-other-than-lua>` but is not
    // yet wired into may — needs ghostty-vt + tsm linking.
    //
    // Routing rules:
    //   - no `cli=` arg at all          → lash + hem
    //   - `cli=lua` (explicit)          → lash + hem (back-compat)
    //   - `cli=<other>` (vt/bash/...)   → polite refusal
    var val: [*c]const u8 = null;
    const has_cli = c.arg_lookup(args, "cli", 0, &val);

    if (!has_cli) {
        return arcterm_luacli_run(con, args);
    }
    if (val != null and std.mem.eql(u8, std.mem.span(val), "lua")) {
        return arcterm_luacli_run(con, args);
    }

    _ = c.fprintf(
        c.stderr,
        "afsrv_terminal (may): cli=<non-lua> (xterm/bash/ghostty mode) " ++
            "is not yet wired into may — it needs ghostty-vt + tsm/ " ++
            "linking (its own follow-up ticket). The default (omit " ++
            "ARCAN_ARG, or pass cli=lua) launches lash + hem.\n",
    );
    return 1;
}
