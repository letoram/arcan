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

static ssize_t parse_command(const char* message, void* tag)
{
/* check builtin- commands or verify against oracle */
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

/* 'on_state'(C, input-bool, int fd, void*) */
/* 'bchunk'
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
