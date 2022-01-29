/*
 * This function exposes a popen() like call, with the twist that
 * it exposes both stdin, stdout, stderr and the pid of the new child.
 *
 * The lua interface is:
 *   (string : command, [string : mode = "rwe"]) => stdin, stdout, stderr, pid
 *
 * With the standard lua file-io userdata assigned to stdin/stdout/stderr.
 * Returns nil on failure, otherwise individual io streams for each requested
 * along with the pid.
 *
 * Lua file-io is used rather than the tui- nbio, in order to first mix with
 * other possible lua includes, but be able to import into tui-nbio at will.
 */

int tui_popen(lua_State* L);

/*
 * This goes with the pid that comes from a tui_popen call, and will merely
 * return true if it is still assumed to be alive, false if it has
 * transitioned to dead and nil if waiting is not valid for the provided pid.
 *
 * If it has transitioned to false, the exit code will also be provided as a
 * second return argument.
 *
 * The lua interface is:
 *  (number : pid) => boolean, exit_code (=false)
 *
 * Subsequent calls on the same identifier after the first transition to false
 * is undefined behaviour.
 */
int tui_pid_status(lua_State* L);
