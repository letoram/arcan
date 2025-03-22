#include "arcan_hmeta.h"
#include "alt/trace.h"
#include "lauxlib.h"

#define BREAK_LIMIT 12

extern struct arcan_luactx* main_lua_context;
extern volatile _Atomic int main_lua_signalled;

/* how often a sample is generated if we are in continous monitor mode */
static int m_srate;
static int m_ctr;

/* control and output devices for monitoring channel */
static FILE* m_out;
static FILE* m_ctrl;

/* locked is waiting for monitor command, dumppause is if we should
 * automatically send a new stackdump when paused once after some command that
 * requires it to be useful */
enum {
	LOCK_NONE,
	LOCK_BREAK,
	LOCK_STEP,
	LOCK_MANUAL
};

enum {
	BPT_NONE,
	BPT_BREAK,
	BPT_WATCH
};

/* if we require the controller to unlock us */
static int m_locked;

/* roundtrip optimisation, dump important information immediately */
static bool m_dumppause;

/* in batched incoming key transfer */
static bool m_transaction;

/* to distinguish between stepping and a an error handler */
static bool m_stepreq;
static bool m_error;

/* when we are waiting for an external monitor to attach */
static bool m_error_defer;

/* used to indicate that we should trigger one of the recovery modes */
static int longjmp_mode;

static struct
{
	union {
		struct {
			size_t line;
			char* file;
		} bpt;
	};

/*
 * int type;
 * watchpoint would go here:
 *
 *  read  - tricky as access could be JITed etc.
 *  write - keep hash or value at point it's set, compare on insn/line
 *  expr  - run lua expression, trigger when TBOOLEAN == true return
 */

	int type;
} m_breakpoints[BREAK_LIMIT];
size_t m_n_breakpoints = 0;

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

static void cmd_source(char* arg, lua_State* L, lua_Debug* D)
{
	if (arg[0] == '@'){
		arg = &arg[1];
	}

/* strip \n */
	size_t len = strlen(arg);
	arg[len-1] = '\0';

	data_source indata = arcan_open_resource(arg);
	map_region reg = arcan_map_resource(&indata, false);
	if (!reg.ptr){
		fprintf(m_out, "#ERROR couldn't map Lua source ref: %s\n", arg);
	}
	else {
		fprintf(m_out, "#BEGINSOURCE\n");
			fprintf(m_out, "%s\n%s\n", arg, reg.ptr);
		fprintf(m_out, "#ENDSOURCE\n");
	}

	arcan_release_map(reg);
	arcan_release_resource(&indata);
}

static void cmd_backtrace(char* arg, lua_State* L, lua_Debug* D)
{
	size_t n_levels = 10;
	if (!L)
		return;

	fprintf(m_out, "#BEGINBACKTRACE\n");
		alt_trace_callstack_raw(L, D, n_levels, m_out);
	fprintf(m_out, "#ENDBACKTRACE\n");

	fprintf(m_out, "#BEGINSTACK\n");
		alt_trace_dumpstack_raw(L, m_out);
	fprintf(m_out, "#ENDSTACK\n");
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

	if (status != 0){
		lua_gc(L, LUA_GCCOLLECT, 0);
		const char* msg = lua_tostring(L, -1);
		if (msg){
			fprintf(m_out, "%s%s\n", msg[0] == '#' ? "\\" : "", msg);
		}
		else
			fprintf(m_out, "(error object is not a string)\n");
	}
/* possible do a real table dump here as with eval we'd want the full one most
 * of the time */
	else if (lua_type(L, -1) != LUA_TNIL){
		alt_trace_print_type(L, -1, "", m_out);
		fputc('\n', m_out);
	}

	fprintf(m_out, "#ENDRESULT\n");
	fflush(m_out);
}

static void cmd_locals(char* argv, lua_State* L, lua_Debug* D)
{
	if (!L || !D){
		fprintf(m_out, "#ERROR no Lua state\n");
		return;
	}
/* take the current stack frame index, extract locals from the activation
 * record and print each one, use that to print name or dump table */
}

static void cmd_stepline(char* argv, lua_State* L, lua_Debug* D)
{
	if (!L || !D){
		fprintf(m_out, "#ERROR no Lua state\n");
		return;
	}

	lua_sethook(L, arcan_monitor_watchdog, LUA_MASKLINE, 1);
	m_locked = false;
	m_stepreq = true;
	m_dumppause = true;
}

static void cmd_stepend(char* argv, lua_State* L, lua_Debug* D)
{
	if (!L || !D){
		fprintf(m_out, "#ERROR no Lua state\n");
		return;
	}

	lua_sethook(L, arcan_monitor_watchdog, LUA_MASKRET, 1);
	m_locked = false;
	m_stepreq = true;
	m_dumppause = true;
}

static void cmd_stepcall(char* argv, lua_State* L, lua_Debug* D)
{
	if (!L || !D){
		fprintf(m_out, "#ERROR no Lua state\n");
		return;
	}

	lua_sethook(L, arcan_monitor_watchdog, LUA_MASKRET, 1);
	m_locked = false;
	m_stepreq = true;
	m_dumppause = true;
}

static void cmd_stepinstruction(char* argv, lua_State* L, lua_Debug* D)
{
	if (!L){
		fprintf(m_out, "#ERROR No Lua state\n");
		return;
	}

	long count = 1;
	if (argv && strlen(argv)){
		count = strtol(argv, NULL, 10);
	}

/* set lua_tracefunction to line mode */
	lua_sethook(L, arcan_monitor_watchdog, LUA_MASKCALL, count);
	m_locked = false;
	m_stepreq = true;
	m_dumppause = true;
}

/* part of dumptable, check for LUA_TABLE at top is done there, this just
 * extracts frame number and local number and loads whatever is there */
static void local_to_table(char** tokctx, lua_State* L)
{
	char* tok;
	bool gotframe = false;
	long lref;
	lua_Debug ar;

	while ( (tok = strtok_r(NULL, " ", tokctx) ) ){
		char* err = NULL;
		long val = strtoul(tok, &err, 10);
		if (err && *err){
			fprintf(m_out,
				"#ERROR gettable: missing %s reference\n", gotframe ? "local" : "frame");
			return;
		}

		if (!gotframe){
			if (!lua_getstack(L, val, &ar)){
				fprintf(m_out,
					"#ERROR gettable: invalid frame %ld\n", val);
				return;
			}
			gotframe = true;
		}
		else {
			lua_getlocal(L, &ar, val);
			return;
		}
	}
}

/* part of dumptable, check for LUA_TABLE at top is done there, this just
 * reads a value and then leaves the stack reference copied to the top */
static void stack_to_table(char** tokctx, lua_State* L)
{
	char* tok;

	while ( (tok = strtok_r(NULL, " ", tokctx) ) ){
		char* err = NULL;
		unsigned long index = strtoul(tok, &err, 10);
		if (err && *err){
			fprintf(m_out, "#ERROR gettable: missing stack reference\n");
		}
		else if (lua_type(L, index) == LUA_TTABLE){
			lua_pushvalue(L, index);
		}
		return;
	}
}

static void cmd_dumptable(char* argv, lua_State* L, lua_Debug* D)
{
	size_t len = strlen(argv);
	if (len)
		argv[len-1] = '\0';

	int argi = 0;
	char* tok, (* tokctx);
	int top = lua_gettop(L);

	while ( (tok = strtok_r(argv, " ", &tokctx) ) ){
		argv = NULL;

/* navigate through the table indices */
		if (argi){
			char* err = NULL;
			unsigned long skip_n = strtoul(tok, &err, 10);
			if (err && *err){
				fprintf(m_out, "#ERROR gettable: couldn't parse index\n");
				break;
			}

			if (lua_type(L, -1) != LUA_TTABLE){
				fprintf(m_out, "#ERROR gettable: resolved index is not a table\n");
				break;
			}

			lua_pushnil(L);
			while (lua_next(L, -2) != 0 && skip_n){
				lua_pop(L, 1);
				skip_n--;
			}

/* remove iteration key */
			lua_remove(L, -2);
		}

/* domain selector: */
		if (argi == 0){
			switch (tok[0]){
			case 'g': lua_pushvalue(L, LUA_GLOBALSINDEX); break;
			case 's': stack_to_table(&tokctx, L); break;
			case 'l': local_to_table(&tokctx, L); break;
			default:
				fprintf(m_out, "#ERROR gettable: bad domain selector\n");
				return;

			break;
			}
			argi++;
		}
	}

	if (lua_type(L, -1) != LUA_TTABLE){
		fprintf(m_out, "#ERROR gettable: resolved index is not a table\n");
	}
/* just dump the entire table, if needed we can support argument for setting
 * starting offset and cap later */
	else {
		fprintf(m_out, "#BEGINTABLE\n");
		alt_trace_dumptable_raw(L, 0, 0, m_out);
		fprintf(m_out, "#ENDTABLE\n");
	}

	fflush(m_out);
	lua_settop(L, top);
}

static void cmd_breakpoint(char* argv, lua_State* L, lua_Debug* D)
{
	size_t len = strlen(argv);

/* dump current set */
	if (!len || len == 1){
		fprintf(m_out, "#BEGINBREAK\n");
		for (size_t i = 0, c = m_n_breakpoints; i < BREAK_LIMIT && c; i++){
			if (m_breakpoints[i].bpt.file){
				c--;
				fprintf(m_out, "file=%s:line=%zu\n",
					m_breakpoints[i].bpt.file, m_breakpoints[i].bpt.line);
			}
		}
		fprintf(m_out, "#ENDBREAK\n");
		return;
	}

/* strip lf, extract file:line */
	char* endptr = &argv[len-1];
	*endptr = '\0';
	unsigned long line = 0;

	while (endptr != argv && *endptr != ':')
		endptr--;

	if (*endptr == ':'){
		*endptr++ = '\0';
		if (!strlen(endptr)){
			fprintf(m_out, "#ERROR breakpoint: expected file:line\n");
			return;
		}

		char* err = NULL;
		line = strtoul(endptr, &err, 10);
		if (err && *err){
			fprintf(m_out,
				"#ERROR breakpoint: malformed line specifier\n");
			return;
		}
	}

/* if match, remove */
	for (size_t i = 0, c = m_n_breakpoints; i < BREAK_LIMIT && c; i++){
		if (!m_breakpoints[i].bpt.file)
			continue;
		c--;

		if (m_breakpoints[i].bpt.line == line &&
			strcmp(m_breakpoints[i].bpt.file, argv) == 0){
			free(m_breakpoints[i].bpt.file);
			m_breakpoints[i].bpt.file = NULL;
			m_n_breakpoints--;
			return;
		}
	}

/* There is the option of better controls here, with lua_getinfo for >L when we
 * have a function on top of the stack, it'll return a list of valid lines to
 * put breakpoints on. */

/* add, unless we are at cap */
	if (m_n_breakpoints == BREAK_LIMIT){
		fprintf(m_out, "#ERROR breakpoint: limit filled\n");
		return;
	}

	for (size_t i = 0; i < BREAK_LIMIT; i++){
		if (!m_breakpoints[i].bpt.file){
			m_breakpoints[i].bpt.file = strdup(argv);
			m_breakpoints[i].bpt.line = line;

			if (m_breakpoints[i].bpt.file)
				m_n_breakpoints++;
			else
				fprintf(m_out, "#ERROR breakpoint: out of memory\n");
			break;
		}
	}

/* send the set */
	cmd_breakpoint("", NULL, NULL);
}

static void cmd_paths(char* argv, lua_State* L, lua_Debug* D)
{
	int spaces[] = {
		RESOURCE_APPL,
		RESOURCE_APPL_SHARED,
		RESOURCE_APPL_TEMP,
		RESOURCE_APPL_STATE,
		RESOURCE_SYS_APPLBASE,
		RESOURCE_SYS_APPLSTORE,
		RESOURCE_SYS_APPLSTATE,
		RESOURCE_SYS_FONT,
		RESOURCE_SYS_BINS,
		RESOURCE_SYS_LIBS,
		RESOURCE_SYS_DEBUG,
		RESOURCE_SYS_SCRIPTS
	};
	const char* space_names[] = {
		"appl",
		"appl-shared",
		"appl-temporary",
		"appl-state",
		"sys-applbase",
		"sys-applstore",
		"sys-statebase",
		"sys-font",
		"sys-binaries",
		"sys-libraries",
		"sys-debugoutput",
		"sys-scripts"
	};

	fprintf(m_out, "#BEGINPATHS\n");
	for (size_t i = 0; COUNT_OF(spaces); i++){
		char* ns = arcan_expand_resource("", spaces[i]);
		fprintf(m_out, "namespace=%s:path=%s", space_names[i], ns ? ns : "(missing)");
		free(ns);

	}
	fprintf(m_out, "#ENDPATHS\n");
}

static void monitor_hup(int sig)
{
	if (m_ctrl){
		fclose(m_ctrl);
		m_ctrl = NULL;
	}

	if (m_out != stdout && m_out){
		fclose(m_out);
		m_out = stdout;
	}
}

static lua_State* m_sigusr_L;
static void monitor_sigusr(int sig)
{
	if (m_sigusr_L)
		lua_sethook(m_sigusr_L, arcan_monitor_watchdog, LUA_MASKCOUNT, 1);
}

/*
 * this is mainly used to swap output
 */
static void cmd_out(char* argv, lua_State* L, lua_Debug* D)
{
	size_t len = strlen(argv);
	if (!len)
		return;
	argv[len-1] = '\0';
	m_out = fopen(argv, "w");
	if (!m_out)
		m_out = stdout;
	fprintf(m_out, "#PID %d\n", getpid());

	if (m_error_defer && L){
/* we have a broken callstack at this point so the stacktrace would do nothing */
		fprintf(m_out,
			"#BEGINERROR\n%s\n#ENDERROR\n",
				lua_type(L, -1) == LUA_TSTRING ? lua_tostring(L, -1) : "(panic)");
		m_error_defer = false;
		m_dumppause = true;
	}

/* swap out the SIGUSR1 handler */

/* the ctrl/out pipe might die, then we should reset those */
	sigaction(SIGHUP,&(struct sigaction){.sa_handler = monitor_hup}, 0);
	sigaction(SIGUSR1,&(struct sigaction){.sa_handler = monitor_sigusr}, 0);
	m_sigusr_L = L;

	setlinebuf(m_out);
}

static void cmd_entrypoint(char* argv, lua_State* L, lua_Debug* D)
{
	uint64_t mask_kind = 0;
	char* tok;
	char* tokctx;

/* strip \n */
	size_t len = strlen(argv);
	if (len)
		argv[len-1] = '\0';

	while ( (tok = strtok_r(argv, " ", &tokctx) ) ){
		argv = NULL;
		mask_kind |= alt_trace_strtoep(tok);
	}

	alt_trace_hookmask(mask_kind, false);
}

void arcan_monitor_masktrigger(lua_State* L)
{
	m_dumppause = true;
}

static char* get_extmon_path()
{
	uintptr_t tag;
	char* monitor = NULL;

	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	get_config("debug_monitor", 0, &monitor, tag);
	return monitor;
}

static char* get_extpipe_path()
{
	uintptr_t tag;
	char* monitor = NULL;
	cfg_lookup_fun get_config = platform_config_lookup(&tag);
	get_config("debug_monitor_path", 0, &monitor, tag);

/* hardcoded default */
	if (!monitor)
		monitor = strdup("/tmp/c2a");

	return monitor;
}

void arcan_monitor_watchdog_listen(lua_State* L, const char* fname)
{
/* similar to the on-demand launch below but with explicit path and no exec */
	int fv = mkfifo(fname, S_IRUSR | S_IWUSR);
	if (-1 == fv)
		return;

/* open the command channel */
	FILE* fpek = fopen(fname, "r");
	if (!fpek){
		unlink(fname);
		return;
	}

}

FILE* arcan_monitor_watchdog_error(lua_State* L, int in_panic, bool check)
{
	static bool extmon_checked = false;

/* we don't have a monitor attached, is the engine configured to spawn one?
 * check the config db once so the error format would switch from human
 * readable to machine readable. */
	if (!m_ctrl){
		if (check && !extmon_checked){
			extmon_checked = true;

			if (get_extmon_path()){
				m_out = stdout;
			}
			return m_out;
		}

		if (!check){
			char* monitor = get_extmon_path();
			if (!monitor)
				return m_out;

			char* path = get_extpipe_path();

/* set temporary monitor-out to stdout waiting for cmd_out to change it */
			if (!m_out)
				m_out = stdout;

/* launch the process and switch to waiting for command on it */
			m_error_defer = true;
			arcan_conductor_toggle_watchdog();
			arcan_monitor_external(monitor, path, &m_ctrl);
			free(monitor);
			free(path);

			arcan_conductor_toggle_watchdog();
			arcan_monitor_watchdog(L, NULL);
		}

		return m_out;
	}

	if (check)
		return m_out;

	if (in_panic)
		longjmp_mode = ARCAN_LUA_RECOVERY_FATAL_IGNORE;

	m_error = true;

/* we have a broken callstack at this point so the stacktrace would do nothing */
	fprintf(m_out,
		"#BEGINERROR\n%s\n#ENDERROR\n",
			lua_type(L, -1) == LUA_TSTRING ? lua_tostring(L, -1) : "(panic)");

	arcan_monitor_watchdog(L, NULL);

	return m_out;
}

static bool check_breakpoints(lua_State* L)
{
	lua_Debug ar;
	if (!m_n_breakpoints || !lua_getstack(L, 0, &ar)){
		return false;
	}

	lua_getinfo(L, "Snl", &ar);

/* check source and current line against set */
	for (size_t i = 0, c = m_n_breakpoints; i < BREAK_LIMIT && c; i++){
		if (m_breakpoints[i].bpt.file){
			c--;
			const char* base = ar.source;
			if (base[0] == '@')
				base++;

			size_t line = m_breakpoints[i].bpt.line;
			char* source = m_breakpoints[i].bpt.file;

			if (ar.currentline != line)
				continue;

			if (strcmp(base, source) == 0){
				fprintf(m_out, "#BREAK %s:%zu\n", source, line);
				return true;
			}
		}
	}

	return false;
}

static void cmd_detach(char* argv, lua_State* L, lua_Debug* D)
{
	if (m_out != stdout){
		fclose(m_out);
		m_out = stdout;
	}

	fclose(m_ctrl);
	m_ctrl = NULL;
	m_locked = false;

/* restore default SIGUSR1 */
	arcan_lua_default_errorhook(L);
}

static struct {
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
	{"stepnext", cmd_stepline},
	{"stepend", cmd_stepend},
	{"stepcall", cmd_stepcall},
	{"stepinstruction", cmd_stepinstruction},
	{"table", cmd_dumptable},
	{"source", cmd_source},
	{"breakpoint", cmd_breakpoint},
	{"entrypoint", cmd_entrypoint},
	{"paths", cmd_paths},
	{"output", cmd_out},
	{"detach", cmd_detach}
};

void arcan_monitor_watchdog(lua_State* L, lua_Debug* D)
{
/* triggered on SIGUSR1, when there's been an error condition or when we have
 * requested stepping in one way or another. Used by m_ctrl to indicate that
 * there is a command that should be read, but also for the Lua-VM to allow
 * debugging.
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

/* if we have breakpoints set, not in an error handler and not requested
 * manual stepping, return immediately so execution continues */
	if (!check_breakpoints(L) && m_n_breakpoints &&
		!m_stepreq && !m_error && !m_transaction){
		arcan_conductor_toggle_watchdog();
		return;
	}

	m_locked = true;
	m_stepreq = false;

/* revert the errorhook if we come with L/D set. SIGUSR1 would re-arm
 * as does other step*** calls.
 */
	if (L){
		lua_sethook(L, NULL, 0, 0);
	}

	do {
		if (m_dumppause && L){
			fprintf(m_out, "#WAITING\n");
			m_dumppause = false;
			cmd_backtrace("", L, D);
		}

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

	if (m_n_breakpoints || m_stepreq){
		lua_sethook(L, arcan_monitor_watchdog, LUA_MASKLINE, 1);
	}
	else
		lua_sethook(L, NULL, LUA_MASKLINE, 0);

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
	m_out = stdout;

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

extern struct arcan_luactx* main_lua_context;
void arcan_monitor_tick(int n)
{
	static size_t count;

	if (m_ctrl){
		struct pollfd pfd = {
			.fd = STDIN_FILENO,
			.events = POLLIN
		};
		if (1 == poll(&pfd, 1, 0)){
			arcan_monitor_watchdog(
				(lua_State*)main_lua_context, NULL);
		}
	}

	if (m_srate <= 0)
		return;

/* sampling is monotonic 25Hz clock aligned */
	m_ctr--;
	if (m_ctr)
		return;

	char buf[8];
	snprintf(buf, 8, "%zu", count);
	count += n;
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
