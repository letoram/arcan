#include "arcan_hmeta.h"
#include "alt/trace.h"
#include "lauxlib.h"

extern struct arcan_luactx* main_lua_context;
extern volatile _Atomic int main_lua_signalled;

static int m_srate;
static int m_ctr;
static FILE* m_out;
static FILE* m_ctrl;
static bool m_locked;
static bool m_transaction;
static int longjmp_mode;

/*
 * instead of adding more commands here, the saner option is to establish
 * a shmif based control interface (with the interesting consequence of
 * being able to migrate that channel dynamically).
 *
 * With all the other monitor- uses and lwa interactions that might be easiest
 * as a command though (lwa- subsegment push is problematic as it might be a
 * native arcan running.
 *
 * Otherwise the option is to start with a primary connection coming from the
 * monitor and NEWSEGMENT the control over that. The problem then is migration
 * of the primary when that is coming from an outer UI.
 */

static void cmd_dumpkeys(char* arg, lua_State* L, lua_Debug* D)
{
	fprintf(m_out, "#BEGINKV\n");
	struct arcan_strarr res = arcan_db_applkeys(
		arcan_db_get_shared(NULL), arcan_appl_id(), "%");
	char** curr = res.data;
	while(*curr){
		fprintf(m_out, "%s\n", *curr++);
	}
	arcan_mem_freearr(&res);
	fprintf(m_out, "#ENDKV\n");
	fflush(m_out);
}

static void cmd_reload(char* arg, lua_State* L, lua_Debug* D)
{
/* signal verifyload- state, wrong sig */
	char* res = arcan_expand_resource("", RESOURCE_APPL);

	const char* errc;
	if (!arcan_verifyload_appl(res, &errc)){
		arcan_mem_free(res);
		fprintf(m_out, "#ERROR %s\n", errc);
		fflush(m_out);
		return;
	}

	arcan_mem_free(res);

/* this should correspond to a system_collapse(self) with a possible copy
 * of the source appl to revert back into the previously stable copy. The
 * problem with these tactics is our namespace enforcement of applname/..
 * so we'd need a .suffix for this to work compatibility wise. */

/* will trigger on next continue; */
	longjmp_mode = ARCAN_LUA_SWITCH_APPL;
}

static void cmd_loadkey(char* arg, lua_State* L, lua_Debug* D)
{
	if (!arg[0] || arg[0] == '\n')
		return;

/* split on = */
	char* pos = arg;
	while (*pos && *pos != '=')
		pos++;

	if (!*pos)
		return;

/* trim */
	*pos++ = '\0';
	size_t len = strlen(pos);
	if (pos[len-1] == '\n')
		pos[len-1] = '\0';

/* enable transaction on the first new key */
	if (!m_transaction){
		m_transaction = true;
		arcan_db_begin_transaction(
			arcan_db_get_shared(NULL), DVT_APPL,
			(union arcan_dbtrans_id){.applname = arcan_appl_id()}
		);
	}

/* append to transaction */
	arcan_db_add_kvpair(arcan_db_get_shared(NULL), arg, pos);
}

static void cmd_commit(char* arg, lua_State* L, lua_Debug* D)
{
	if (!m_transaction)
		return;

	arcan_db_end_transaction(arcan_db_get_shared(NULL));
	m_transaction = false;
}

static void cmd_backtrace(char* arg, lua_State* L, lua_Debug* D)
{
	size_t n_levels = 10;
	fprintf(m_out, "#BEGINBACKTRACE\n");
	if (L){
		alt_trace_callstack_raw(L, D, n_levels, m_out);
	}
	fprintf(m_out, "#ENDBACKTRACE\n");
}

static void cmd_lock(char* arg, lua_State* L, lua_Debug* D)
{
/* no-op, m_locked already set */
	fprintf(m_out, "#LOCKED\n");
	fflush(m_out);
}

static void cmd_continue(char* arg, lua_State* L, lua_Debug* D)
{
	m_locked = false;
	if (m_transaction)
		cmd_commit(arg, L, D);
}

static void cmd_dumpstate(char* argv, lua_State* L, lua_Debug* D)
{
/* previously all the dumping ran here, with the change to bootstrap a shmif
 * context, it makes more sense letting the monitor end drive the action */
	fprintf(m_out, "#BEGINKV\n");
	fprintf(m_out, "#LASTSOURCE\n");
	const char* msg = arcan_lua_crash_source(main_lua_context);
	if (msg){
		fprintf(m_out, "%s", msg);
	}
	fprintf(m_out, "#ENDLASTSOURCE\n");
	arcan_lua_statesnap(m_out, "state", true);
	fprintf(m_out, "#ENDKV\n");
}

/*
 * watchset could be:
 *  _G table member (?)
 *  eval expression to run at each step
 *
 * we don't have a good way of intercepting all updates to a given key, so
 * stick to primitive types and a static set of watches that we fetch on each
 * step.
 *
 * tactic:
 *
 *  set lua_hook, mark us as in freerunning mode, on each monitor invocation
 *  from the hook, sample the watches, if there is a change then set blocking
 *  and forward the watch changes.
 */

/* Same as used in lua.c and alt/trace.c - there is a better version in LuaJIT
 * and in Lua5.3+ but relies on function and access that we lack. In difference
 * to alt/trace.c though, we don't force-load from lualibs so there might be an
 * option of someone maliciously replacing it. */
static int traceback (lua_State *L) {
  if (!lua_isstring(L, 1))  /* 'message' not a string? */
    return 1;  /* keep it intact */
  lua_getfield(L, LUA_GLOBALSINDEX, "debug");
  if (!lua_istable(L, -1)) {
    lua_pop(L, 1);
    return 1;
  }
  lua_getfield(L, -1, "traceback");
  if (!lua_isfunction(L, -1)) {
    lua_pop(L, 2);
    return 1;
  }
  lua_pushvalue(L, 1);  /* pass error message */
  lua_pushinteger(L, 2);  /* skip this function and traceback */
  lua_call(L, 2, 1);  /* call debug.traceback */
  return 1;
}

static void cmd_eval(char* argv, lua_State* L, lua_Debug* D)
{
	int status = luaL_loadbuffer(L, argv, strlen(argv), "eval");
	if (status){
		const char* msg = lua_tostring(L, -1);
		fprintf(m_out,
			"#BADRESULT\n%s\n#ENDBADRESULT\n", msg ? msg : "(error object is not a string)");
		fflush(m_out);
		lua_pop(L, 1);
		return;
	}

	int base = lua_gettop(L);
	lua_pushcfunction(L, traceback);
	lua_insert(L, base);

	fprintf(m_out, "#BEGINRESULT\n");

	status = lua_pcall(L, 0, LUA_MULTRET, base);
	lua_remove(L, base);

/* don't need to put effort in printing the results here as print(...) would be
 * captured by stdout in the debugger launching it, for arcan-net we do need a
 * different method for capturing output */

	if (status != 0){
		lua_gc(L, LUA_GCCOLLECT, 0);
		const char* msg = lua_tostring(L, -1);
		if (msg){
			fprintf(m_out, "%s%s\n", msg[0] == '#' ? "\\" : "", msg);
		}
		else
			fprintf(m_out, "(error object is not a string)\n");
	}

	fprintf(m_out, "#ENDRESULT\n");
	fflush(m_out);
}

static void cmd_locals(char* argv, lua_State* L, lua_Debug* D)
{
	if (!L || !D){
		fprintf(m_out, "ERROR no Lua state\n");
		return;
	}
/* take the current stack frame index, extract locals from the activation
 * record and print each one, use that to print name or dump table */
}

static void cmd_stepn(char* argv, lua_State* L, lua_Debug* D)
{
/* set lua_tracefunction to line mode */
}

static void cmd_stepinstruction(char* argv, lua_State* L, lua_Debug* D)
{
/*set lua_tracefunction to instruction mode */
}

static void cmd_dumptable(char* argv, lua_State* L, lua_Debug* D)
{
/* extract offset, seek to that position and dump keys, recurse */
}

static void cmd_breakep(char* argv, lua_State* L, lua_Debug* D)
{
/* check argv for entrypoint, mark it as hooked in the arcan_lua bitmap
 * and that will trigger the lua_trace for us */
}

/*
 * sources we can get from globbing the appl path for all .lua
 */

void arcan_monitor_watchdog(lua_State* L, lua_Debug* D)
{
/* triggered on SIGUSR1 - used by m_ctrl to indicate that there is a command
 * that should be read, but also for the Lua-VM to allow debugging.
 *
 * We can see this when L, D are set.
 *
 * The option then is to return and possible be triggered again, check a list
 * of breakpoints and repeat until we hit one of those, trace the functions
 * into a ringbuffer, randomly sample for profiling and so on.
 *
 */
	if (!m_ctrl)
		return;

	extern jmp_buf arcanmain_recover_state;

	arcan_conductor_toggle_watchdog();

	struct {
		const char* word;
		void (*ptr)(char* arg, lua_State*, lua_Debug*);
	} cmds[] =
	{
		{"continue", cmd_continue},
		{"dumpkeys", cmd_dumpkeys},
		{"loadkey", cmd_loadkey},
		{"dumpstate", cmd_dumpstate},
		{"commit", cmd_commit},
		{"reload", cmd_reload},
		{"backtrace", cmd_backtrace},
		{"lock", cmd_lock},
		{"eval", cmd_eval},
		{"locals", cmd_locals},
		{"stepnext", cmd_stepn},
		{"stepinstruction", cmd_stepinstruction},
		{"dumptable", cmd_dumptable}
	};

	m_locked = true;

	do {
		char buf[4096];
		fprintf(m_out, "#WAITING\n");
		if (!fgets(buf, 4096, m_ctrl)){
			arcan_warning("monitor: couldn't read control command");
			longjmp_mode = ARCAN_LUA_KILL_SILENT;
			break;
		}
/* no funny / advanced format here, just command\sarg*/
		size_t i = 0;
		for (; i < 4096 && buf[i] && buf[i] != ' ' && buf[i] != '\n'; i++){}

		if (i == 4096)
			continue;

		buf[i] = '\0';
		for (size_t j = 0; j < COUNT_OF(cmds); j++){
			if (strcasecmp(buf, cmds[j].word) == 0){
				cmds[j].ptr(&buf[i+1], L, D);
				break;
			}
		}
	} while (m_locked);

/* revert the errorhook
 *
 * we get into the watchdog with L/D set based on SIGUSR1 being sent,
 * other commands come due to input on monitor control in.
 *
 * For single-stepping etc. we can also let the hook remain, and switch
 * between line, instruction, ...
 * The mask (MASKCALL, MASKLRET, MASKLINE, MASKCOUNT) sets condition for
 * hook trigger.
 */
	if (L){
		lua_sethook(L, NULL, 0, 0);
	}

	arcan_conductor_toggle_watchdog();

	if (longjmp_mode){
		int mode = longjmp_mode;
		longjmp_mode = 0;
		longjmp(arcanmain_recover_state, mode);
	}
}

bool arcan_monitor_configure(int srate, const char* dst, FILE* ctrl)
{
	m_srate = srate;
	if (m_srate > 0){
		m_ctr = m_srate;
	}

	bool logtgt = dst ? strncmp(dst, "LOG:", 4) == 0 : false;
	bool logfdtgt = dst ? strncmp(dst, "LOGFD:", 6) == 0 : false;

	m_ctrl = ctrl;
	if (ctrl)
		setlinebuf(m_ctrl);

	if (!logtgt && !logfdtgt)
		return false;

	if (logtgt)
		m_out = fopen(&dst[4], "w");
	else {
		int fd = strtoul(&dst[6], NULL, 0);
		if (fd > 0){
			m_out = fdopen(fd, "w");
			if (NULL == m_out){
				arcan_fatal("-O LOGFD:%d points to an invalid descriptor\n", fd);
			}
			else
				fcntl(fd, F_SETFD, FD_CLOEXEC);
		}
	}
	setlinebuf(m_out);
	return true;
}

void arcan_monitor_finish(bool ok)
{
	if (!m_out)
		return;

	if (ok)
		fprintf(m_out, "#FINISH\n");
	else
		fprintf(m_out, "#FAIL\n");

	arcan_monitor_watchdog(NULL, NULL);
}

void arcan_monitor_tick()
{
	static size_t count;

	if (m_ctrl){
		struct pollfd pfd = {
			.fd = STDIN_FILENO,
			.events = POLLIN
		};
		if (1 == poll(&pfd, 1, 0)){
			arcan_monitor_watchdog(NULL, NULL);
		}
	}

	if (m_srate <= 0)
		return;

/* sampling is monotonic 25Hz clock aligned */
	m_ctr--;
	if (m_ctr)
		return;

	char buf[8];
	snprintf(buf, 8, "%zu", count++);
	m_ctr = m_srate;
	arcan_lua_statesnap(m_out, buf, true);
}

bool arcan_monitor_fsrvvid(const char* cp)
{
	if (!m_ctrl)
		return false;

	fprintf(m_out, "join %s\n", cp);
	return true;
}
