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

/* Send a signal to the pid passed as argument,
 *
 * this takes a pid and a string representation of a supported string or raw
 * signal number.
 *
 *  kill, close, usr1, usr2, hup, suspend, resume
 */
int tui_pid_signal(lua_State* L);

/* Extract an execve friendly environment table and argument vector from the
 * lua ttable at ind. All strings inside the returned array are dynamically
 * allocated and should be iterated until NULL and freed.
 */
char** tui_popen_tbltoenv(lua_State* L, int ind);
char** tui_popen_tbltoargv(lua_State* L, int ind);

/* Try to resize a pty bound to a nbio by performing the TIOCSWINSZ ioctl. */
int tui_pty_resize(lua_State* L);
