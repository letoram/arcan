#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <arcan_tui_readline.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include "cli_builtin.h"

static struct cli_state cli_state;

static void free_strtbl(char** arg)
{
	for (size_t i = 0; arg && arg[i]; i++)
		free(arg[i]);
	free(arg);
}

static char** duplicate_strtbl(char** arg, size_t prepad, size_t pad)
{
	size_t i = 0;

/* nothing to copy? at least alloc pad buffer */
	if (!arg || !arg[i]){
		if (pad || prepad){
			size_t buf_sz = sizeof(char*) * (pad + prepad + 1);
			char** res = malloc(buf_sz);
			memset(res, '\0', buf_sz);
			return res;
		}
		return NULL;
	}

/* count */
	for(; arg[i]; i++){}

/* copy + add NULL */
	char** buf = malloc(sizeof(char*) * (i + prepad + pad + 1));
	for (size_t j = 0; j < prepad; j++)
		buf[j] = NULL;

	for (size_t j = 0; j < i; j++)
		buf[j+prepad] = strdup(arg[j]);

	for (size_t j = i; j < i + pad + 1; j++)
		buf[j+prepad] = NULL;

	return buf;
}

static ssize_t parse_command(const char* message, void* tag)
{
	return -1;
}

static void free_cmd(struct ext_cmd* cmd)
{
	cmd->id = 0;
	free_strtbl(cmd->env);
	free_strtbl(cmd->argv);
	free(cmd->wd);
	memset(cmd, '\0', sizeof(struct ext_cmd));
}

static char* get_terminal_bin()
{
#ifdef __LINUX
	return "/proc/self/exe";
/* should really mimic normal path search here, add a helper for that */
#else
	struct stat statbuf;
	if (-1 != stat("/usr/local/bin/afsrv_terminal", &statbuf))
		return "/usr/local/bin/afsrv_terminal";
	else if (-1 != stat("/usr/bin/afsrv_terminal", &statbuf))
		return "/usr/bin/afsrv_terminal";
	else
		return "afsrv_terminal";
#endif
}

static char* get_waybridge_bin()
{
	struct stat statbuf;
	if (-1 != stat("/usr/local/bin/arcan-wayland", &statbuf))
		return "/usr/local/bin/arcan-wayland";

	if (-1 != stat("/usr/bin/arcan-wayland", &statbuf))
		return "/usr/bin/arcan-wayland";

	return "arcan-wayland";
}

static char* argv_to_env(char** in)
{
	static const char prefix[] = "ARCAN_TERMINAL_ARGV=";
	size_t buflen = sizeof(prefix);

	for (size_t i = 0; in[i]; i++){
		size_t esclen = 0;
		for (size_t j = 0; in[i][j]; j++){
			char ch = in[i][j];
			if (ch == ' ' || ch == '"')
				esclen++;
			esclen++;
		}
		buflen += esclen + 1;
	}

/* start with the prefix string */
	char* res =	malloc(buflen);
	size_t ofs = 0;
	memcpy(res, prefix, sizeof(prefix));
	ofs += sizeof(prefix) - 1;

/* and now repeat the calc- dance, and add \\ to the sep and block */
	for (size_t i = 0; in[i]; i++){
		for (size_t j = 0; in[i][j]; j++){
			char ch = in[i][j];
			if (ch == ' ' || ch == '"')
				res[ofs++] = '\\';
			res[ofs++] = ch;
		}

		res[ofs++] = ' ';
	}
	res[ofs] = 0;

	return res;
}

static char* prepend_str(const char* a, const char* b)
{
	size_t alen = strlen(a);
	size_t blen = strlen(b);
	size_t len = alen + blen + 1;
	char* buf = malloc(len);
	if (!len)
		return NULL;

	memcpy(buf, a, alen);
	memcpy(&buf[alen], b, blen);
	buf[len] = '\0';

	return buf;
}

static void setup_cmd_mode(struct ext_cmd* cmd,
	char** bin, char*** argv, char*** env, int* flags)
{
	*bin = cmd->argv[0];
	*env = cmd->env;
	*argv = cmd->argv;
	*flags = cmd->flags;

/* while we could possibly 'just' fork and spin up the terminal in process,
 * forcing handover + exec is cleaner and won't leak as much - the ugly thing
 * is that we need to handover the arguments to the terminal in env - so undo
 * the argument that we just built */
	switch (cmd->mode){
	case LAUNCH_VT100:{
		*bin = get_terminal_bin();

/* gives us ARCAN_TERMINAL_ARGV=argv[1] .. n */
		char* arg_env = argv_to_env(&cmd->argv[1]);
		char* arg_exec = prepend_str("ARCAN_TERMINAL_EXEC=", cmd->argv[0]);

/* which means we no longer need argv */
		char** new_arg = malloc(sizeof(char*) * 2);
		new_arg[0] = strdup("afsrv_terminal");
		new_arg[1] = NULL;
		free_strtbl(cmd->argv);
		cmd->argv = new_arg;
		*argv = new_arg;

/* attach them to our env */
		char** new_env = duplicate_strtbl(cmd->env, 3, 0);
		new_env[0] = arg_exec;
		new_env[1] = arg_env;

/* question if we should build the entire thing from the arguments that we
 * ourselves got (sans -cli) or lest a few of the through for color overrides
 * and the likes */
		new_env[2] = strdup("ARCAN_ARG=keep_alive");
		free_strtbl(cmd->env);
		cmd->env = new_env;
		*env = cmd->env;
	}
	break;

/* we might also have a tui connection already as an oracle, then we can just
 * send a migrate - though something new is needed for migrating to an oracle */
	case LAUNCH_TUI:
	break;

/* arcan-wayland -exec ..., this should really check if there is a compositor
 * already reachable somewhere, and then make the decision to go system or
 * contained */
	case LAUNCH_X11:
	case LAUNCH_WL:{
		char** new_arg = duplicate_strtbl(cmd->argv, 2, 0);
		*bin = get_waybridge_bin();
		free_strtbl(cmd->argv);
		cmd->argv = new_arg;
		new_arg[0] = "arcan-wayland";
		new_arg[1] = strdup(cmd->mode == LAUNCH_X11 ? "-exec-xwl" : "-exec");
	}
	break;
	}
}

static bool on_subwindow(struct tui_context* T,
	arcan_tui_conn* conn, uint32_t id, uint8_t type, void* c)
{
/* find the pending command and handover_exec */
	for (size_t i = 0; i < 4; i++){
		if (cli_state.pending[i].id == id){
			struct ext_cmd* cmd = &cli_state.pending[i];

/* inherited state like current working directory, but ignore if we
 * cant store / restore, better than failing outright */
			char* tmp = malloc(PATH_MAX);
			if (!tmp || !getcwd(tmp, PATH_MAX)){
				free(tmp);
				tmp = NULL;
			}

/* might fiddle with offsets and alias, cmd is still responsible for alloc */
			char* bin;
			char** env;
			char** argv;
			int flags;

/* another option here is that we can using pending streams to inject as
 * stdin/stdout/stderr */
			setup_cmd_mode(cmd, &bin, &argv, &env, &flags);
			pid_t pid = arcan_tui_handover(T, conn, NULL, bin, argv, env, flags);
			free_cmd(cmd);
			return true;
		}
	}

	return false;
}

static char* group_expand(struct group_ent* group, const char* in)
{
/* depending on group, we might perform another extract_argv for specials,
 * expand user-set variables, call into script, ... */
	return strdup(in);
}

/* 'on_state'(C, input-bool, int fd, void*) [ history, config, env ] */
/* 'bchunk' (save/load from the cwd) keep as a data buffer, command to inject
 *  as pipe or store as file
 * 'reset', return cwd and other env to the current one */

/* build environment based on current state (term-wrapper, ...), thought
 * tempting to just add scripting hooks here and go the *sh route */
static bool eval_to_cmd(char* out, struct ext_cmd* cmd, bool noexec)
{
	struct group_ent groups[] = {
		{.enter = '\'', .leave = '\'', .expand = group_expand},
		{.enter = '"',  .leave = '"',  .expand = group_expand},
		{.enter = '`',  .leave = '`',  .expand = group_expand},
		{.enter = '\0', .leave = '\0', .expand = NULL}
	};

/* environment variable, kind of expansion is its own step */

	ssize_t err_ofs;
	struct argv_parse_opt opts = {
		.prepad = 0,
		.groups = groups,
		.sep = ' '
	};
	char** argv = extract_argv(out, opts, &err_ofs);
	int pos = 0;

/* builtin commands? */
	if (!argv)
		return false;

	struct cli_command* builtin = cli_get_builtin(argv[0]);

/* now, return the argv- array, this comes post expansion so the first arg in
 * argv (cmd) follows the execlpe format, due to the asynch/ handover approach
 * with cmd, the active working directory needs to be tracked as well - this is
 * likely to trigger only in a network environment or during some pipelined
 * stall (hotplug, ...) */
	if (!builtin){
		cmd->argv = argv;
		cmd->env = duplicate_strtbl(cli_state.env, 0, 0);
		return true;
	}

/* builtin- commands should only be executed if we explicitly request that */
	char* err = NULL;
	if (noexec){
		free_strtbl(argv);
		return false;
	}

/* but they can also expand to an external command, so let it */
	struct ext_cmd* res = builtin->exec(&cli_state, argv, &err_ofs, &err);
	if (res){
		memcpy(cmd, res, sizeof(struct ext_cmd));
		return true;
	}

	free_strtbl(argv);
	return false;
}

static void parse_eval(struct tui_context* T, char* out)
{
	size_t ind = 0;

	for (size_t i = 0; i < 4; i++)
		if (!cli_state.pending[i].id){
			ind = i;
			break;
		}

	if (4 == ind){
/* sorry we are full - alert the user via the prompt */
		cli_state.blocked = true;
		return;
	}

	struct ext_cmd* cmd = &cli_state.pending[ind];

	if (!eval_to_cmd(out, cmd, false))
		return;

/* we are supposed to execute the thing - a primitive we need here is
 * to evaluate if the target is a binary, and if that binary is likely
 * to use tui, shmif, wayland, X or vt100.
 *
 * the tui- evaluation stage is needed in beforehand to provide interactive
 * command-line construction, and possibly we should write a bash completion
 * oracle that can be used for legacy completion.
 *
 * this won't be sufficient for distinguishing between wayland or X,
 * as both libs might be present in the case of toolkits - first trying
 * to execute without a DISPLAY and then try wayland_display is one costly
 * and somewhat risky tactic, but the other would be whitelists/database
 * like .desktop files and that is also uninteresting.
 *
 * right now we can just set it manually based on some built-in command
 */
	cmd->mode = cli_state.mode;
	cmd->id = ++cli_state.id_counter;
	cmd->wd = malloc(PATH_MAX);
	getcwd(cmd->wd, PATH_MAX);
	arcan_tui_request_subwnd(T, TUI_WND_HANDOVER, cmd->id);
}

int arcterm_cli_run(struct arcan_shmif_cont* c, struct arg_arr* args)
{
/* source arguments, prompt, ... from args or config file */
	struct tui_readline_opts opts = {
		.allow_exit = false,
		.verify = parse_command
	};

/* don't need much on top of the normal readline:
 * subwindow handler for dispatching new command basically */
	struct tui_cbcfg cfg = {
		.subwindow = on_subwindow,
	};

	struct tui_context* tui = arcan_tui_setup(c, NULL, &cfg, sizeof(cfg));
	if (!tui)
		return EXIT_FAILURE;

	arcan_tui_readline_setup(tui, &opts, sizeof(opts));
	bool running = true;
	char* out;

	while (running){
		int status;
		while (!(status = arcan_tui_readline_finished(tui, &out)) && running){
			struct tui_process_res res = arcan_tui_process(&tui, 1, NULL, 0, -1);
			if (res.errc == TUI_ERRC_OK){
				if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
					running = false;
			}
		}

		if (status == READLINE_STATUS_DONE){
/* parse, commit to history, ... */
			if (out){
				parse_eval(tui, out);
			}
			arcan_tui_readline_reset(tui);
		}
		else if (status == READLINE_STATUS_TERMINATE){
			running = false;
		}
	}

	arcan_tui_destroy(tui, NULL);
	return EXIT_SUCCESS;
}
