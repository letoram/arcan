/*
 * Line-based debug/control interface for using an external launcher with
 * course control over the arcan process. The point is mainly for arcan-net, a
 * suid- chainloader, interactive debugger or other privileged owner to get
 * collaborative process control and state dump without hitting other
 * safe-guards such as watchdog timers.
 *
 * Currently the psep_open implementation has its own line protocol in order
 * to push file descriptors and other properties through (vt- switching
 * handshake) and this interface is not particularly suitable for that setup
 * as DuplicateHandle is but a pipedream.
 */
#ifndef HAVE_ARCAN_MONITOR
#define HAVE_ARCAN_MONITOR

/*
 * Set as the temporary error_hook to a arcan_luactx upon an external trigger,
 * typically SIGUSR1 when monitoring is enabled, the default only triggers a
 * luaL_error in order to get the script error recovery working.
 */
void arcan_monitor_watchdog(lua_State*, lua_Debug*);

/*
 * Switch to the FIFO- pair external debugger mode with the FIFO created at
 * the resolved [name] path.
 */
void arcan_monitor_watchdog_listen(lua_State* L, const char* name);

/*
 * When the Lua VM pcall or panic handler gets triggered from code, this should
 * be called first to determine if an attached debugger is there to take over
 * recovery rather than the default path of jumping into recovery-switch or the
 * _fatal entrypoint.
 */
FILE* arcan_monitor_watchdog_error(lua_State* L, int in_panic, bool check);

/*
 * call once, set periodic output monitoring destination:
 *  LOG:fname
 *  LOGFD:fd
 *
 * and possibly activate control interface (ctrl) that will be processed as
 * part of arcan_monitor_watchdog.
 *
 * If srate is set to positive, a sample will be emitted each tick with a
 * #BEGINSTATE\n start and #ENDSTATE\n delimiter for each sample.
 * If srate is set to 0, the feature is disabled.
 *
 * If srate is set to negative, only crashes will be written to the output.
 */
bool arcan_monitor_configure(int srate, const char*, FILE* ctrl);

/*
 * hooked into the conductor's monotonic 'internal processing', used to
 * snapshot VM state into a configured output
 */
void arcan_monitor_tick(int);

/*
 * clean up and dump appl kv state and/or the VM state (including error
 * traceback on error and any possible 'crash_message' to the log output.
 */
void arcan_monitor_finish(bool ok);

/*
 * trigger prior to pcall:ing something which matched the trigger mask
 */
void arcan_monitor_masktrigger(lua_State* L);

/*
 * forward connection point information over the monitor and have the
 * parent bind to it (replacing any existing one).
 */
bool arcan_monitor_fsrvvid(const char* cp, struct arcan_frameserver* fsrv);

#endif
