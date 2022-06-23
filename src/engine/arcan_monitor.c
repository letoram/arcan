#include "arcan_hmeta.h"
extern struct arcan_luactx* main_lua_context;

static int m_srate;
static int m_ctr;
static FILE* m_out;
static FILE* m_ctrl;
static bool m_locked;
static bool m_transaction;

/* fgets ->
 *  need command for:
 *       database externally modified (new namespaces, EVENT_SYSTEM)
 *       debug-controls
 *           (single stepping, add breakpoint, tracing)
 *       force-reset (can longjmp to recover)
 *       soft shutdown (enqueue EVENT_SYSTEM_EXIT)
 *       lua-statesnap
 *       mask function
 *       add / run hookscript
 */

static void cmd_dumpkeys(char* arg)
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

static void cmd_loadkey(char* arg)
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

static void cmd_commit(char* arg)
{
	if (!m_transaction)
		return;

	arcan_db_end_transaction(arcan_db_get_shared(NULL));
	m_transaction = false;
}

static void cmd_continue(char* arg)
{
	m_locked = false;
	if (m_transaction)
		cmd_commit(arg);
}

void arcan_monitor_watchdog(lua_State* L, lua_Debug* D)
{
/* triggered on SIGUSR1 - used by m_ctrl to indicate that
 * there is a command that should be read */
	if (!m_ctrl)
		return;

	extern jmp_buf arcanmain_recover_state;

	arcan_conductor_toggle_watchdog();

	struct {
		const char* word;
		void (*ptr)(char* arg);
	} cmds[] =
	{
		{"continue", cmd_continue},
		{"dumpkeys", cmd_dumpkeys},
		{"loadkey", cmd_loadkey},
		{"commit", cmd_commit},
	};

	m_locked = true;

	do {
		char buf[4096];
		if (!fgets(buf, 4096, m_ctrl)){
			longjmp(arcanmain_recover_state, ARCAN_LUA_KILL_SILENT);
		}
/* no funny / advanced format here, just command\sarg*/
		size_t i = 0;
		for (; i < 4096 && buf[i] && buf[i] != ' ' && buf[i] != '\n'; i++){}

		if (i == 4096)
			continue;

		buf[i] = '\0';
		for (size_t j = 0; j < COUNT_OF(cmds); j++){
			if (strcasecmp(buf, cmds[j].word) == 0)
				cmds[j].ptr(&buf[i+1]);
		}
	} while (m_locked);

	arcan_conductor_toggle_watchdog();
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

	return true;
}

void arcan_monitor_finish(bool ok)
{
	m_locked = false;

	if (m_srate < 0 && m_out && !ok){
		fprintf(m_out, "#LASTSOURCE\n");
		const char* msg = arcan_lua_crash_source(main_lua_context);
		if (msg){
			fprintf(m_out, "%s", msg);
		}
		fprintf(m_out, "#ENDLASTSOURCE\n");
		arcan_lua_statesnap(m_out, "state", true);
	}

	if (m_out && ok){
		cmd_dumpkeys(NULL);
	}

	if (m_ctrl){
		fclose(m_ctrl);
		m_ctrl = NULL;
	}

	if (m_out){
		fclose(m_out);
		m_out = NULL;
	}
}

void arcan_monitor_tick()
{
	static size_t count;

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
