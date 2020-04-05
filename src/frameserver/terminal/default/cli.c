#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <arcan_tui_readline.h>
#include <errno.h>

struct ext_cmd {
	uint32_t id;
	int flags;
	char* cmd;
	char** argv;
	char** env;
};

struct {
	char* pwd;
	uint32_t id_counter;
	struct ext_cmd pending[4];
	bool blocked;
} cli_state;

/*
 * multiple paths to venture through here -
 *
 * 1. is a launch mode, legacy terminal or tui
 *
 *    - if tui, setup a shmif server, inherit-spawn the client
 *    and use that channel to run the cli-command sequence in
 *    order to populate the dynamic command-line
 *
 *    - when a command-line is commited, use handover- setup
 *    twice to attach the client to the outer desktop
 *
 *    - have a detach command that sends the forced migration
 *    event as a means of switching it to the server
 *
 * 2. make the command evaluation / readline event handlers
 *    dynamic and pluggable / build-time configured, in order
 *    to have the shell behavior user defined - and provide
 *    a lua script default one.
 *
 *    - this should somehow also affect prompt state
 *    - we have some unique shell opportunities here though
 *    that should not be squandered, cat / data-stream into
 *    the clipboard for instance (bchunk-out)
 *
 * 3. repeat / use the probe process to setup arcan-wayland
 *    in wayland or X mode as well
 */

static char** grab_argv(
	const char* message, char* (*expand)(char group, const char*))
{
/* just overfit, not worth the extra work */
	size_t len = strlen(message);
	size_t len_buf_sz = sizeof(char*) * len;
	char** argv = malloc(len_buf_sz);
	size_t arg_i = 0;
	memset(argv, '\0', len_buf_sz);

/* unescaped presence of any of these characters enters that parsing group,
 * and when the next unescaped presence of the same character occurs, split
 * off the current work buffer into the argv array */
	static const char esc_grp[] = {'\'', '"', '`'};
	ssize_t esc_ind = -1;
	bool esc_ign = false;

	char* work = malloc(len);
	size_t pos = 0;
	work[0] = '\0';

	for (size_t i = 0; i < len; i++){
		char ch = message[i];

		if (esc_ign){
			work[pos++] = ch;
			esc_ign = false;
			continue;
		}

/* got one of the escape groups that might warrant different postprocessing or
 * interpretation, e.g. execute and absorb into buffer, forward to script
 * engine or other expansion */
		for (size_t j = 0; j < sizeof(esc_grp) / sizeof(esc_grp[0]); j++){
			if (ch != esc_grp[j])
				continue;

			if (esc_ind == -1)
				esc_ind = j;

			else if (esc_ind == j){
				esc_ind = -1;
				argv[arg_i++] = expand(esc_ind, work);
			}
		}
		if (ch == esc_grp[0] || ch == esc_grp[1] || ch == esc_grp[2]){
			if (esc_ind == -1){
			}

			continue;
		}

		if (ch == '\\' && esc_ind == -1){
			esc_ign = true;
			continue;
		}

/* finish and append to argv */
		if (ch == ' ' && pos && esc_ind == -1){
			continue;
		}

/* or append to work */
		work[pos++] = ch;
	}

	if (esc_ign || esc_ind != -1)
		goto err_out;

	free(work);
	return argv;

err_out:
	free(work);
	for (size_t i = 0; i < len; i++){
		if (argv[i])
			free(argv[i]);
	}
	free(argv);
	return NULL;
}

static ssize_t parse_command(const char* message, void* tag)
{
	return -1;
}

static void free_cmd(struct ext_cmd* cmd)
{
	cmd->id = 0;
	free(cmd->cmd);

	for (size_t i = 0; cmd->argv[i]; i++)
		free(cmd->argv[i]);
	free(cmd->argv);

	for (size_t i = 0; cmd->env[i]; i++)
		free(cmd->env[i]);
	free(cmd->env);

	memset(cmd, '\0', sizeof(struct ext_cmd));
}

static bool on_subwindow(struct tui_context* T,
	arcan_tui_conn* conn, uint32_t id, uint8_t type, void* c)
{
/* find the pending command and handover_exec */
	for (size_t i = 0; i < 4; i++){
		if (cli_state.pending[i].id == id){
			struct ext_cmd* cmd = &cli_state.pending[i];
			pid_t pid = arcan_tui_handover(
				c, conn, NULL, cmd->cmd, cmd->argv, cmd->env, cmd->flags);
			free_cmd(cmd);
		return true;
		}
	}

	return false;
}

/* 'on_state'(C, input-bool, int fd, void*) [ history, config, env ] */
/* 'bchunk' (save/load from the cwd) keep as a data buffer, command to inject
 *  as pipe or store as file
 * 'reset', return cwd and other env to the current one */

/* build environment based on current state (term-wrapper, ...), thought
 * tempting to just add scripting hooks here and go the *sh route */
static bool eval_to_cmd(char* out, struct ext_cmd* cmd)
{
	return false;
}

static void parse_eval(struct tui_context* T, char* out)
{
	size_t ind = 0;

	for (size_t i = 0; i < 4; i++)
		if (!cli_state.pending[i].id)
			ind = i;

	if (4 == ind){
/* sorry we are full - alert the user via the prompt */
		cli_state.blocked = true;
		return;
	}

	struct ext_cmd* cmd = &cli_state.pending[ind];

	if (!eval_to_cmd(out, cmd))
		return;

	cmd->id = ++cli_state.id_counter;
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
