#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include "cli_builtin.h"

struct cmd_state {
	char* cwd;
	size_t capacity;
	bool dynamic;
};

/* cwd allocation retained for the lifespan of the process */
static struct cmd_state current;

/* extract current working directory into cmd_state, or write
 * the error state withing ( .. ) */
static void synch_cwd(struct cmd_state* C, bool sync_env)
{
/* ensure 'cwd' is synched */
	if (!C->capacity){
		C->cwd = malloc(4096);
		if (!C->cwd)
			return;

		C->capacity = 4096;
	}

	if (!getcwd(C->cwd, C->capacity)){
/* the 'lovely' getcwd lacking dynamic option */
		while (errno == ERANGE){
			size_t new_sz = C->capacity * 2;
			char* new = realloc(C->cwd, new_sz);
			if (!new){
				sprintf(C->cwd, "(out of memory)");
				return;
			}

			C->cwd = new;
			C->capacity = new_sz;
			if (getcwd(C->cwd, C->capacity))
				goto ok;
		}

/* may be indicated by prompt */
		if (errno == ENOENT){
			sprintf(C->cwd, "(unlinked)");
			return;
		}

		if (errno == EACCES){
			sprintf(C->cwd, "(no permission)");
			return;
		}

		sprintf(C->cwd, "(unknown)");
		return;
	}

ok:
	if (!sync_env)
		return;

	char* lastpwd = getenv("PWD");
	if (lastpwd)
		setenv("OLDPWD", lastpwd, 1);

	setenv("PWD", C->cwd, 1);
}

static struct ext_cmd* cmd_cd(
	struct cli_state* state, char** argv, ssize_t* ofs, char** err)
{
	*ofs = -1;
	*err = NULL;

/* empty argv? try $HOME */
	if (!argv[1]){
		const char* home = getenv("HOME");
		if (!home)
			return NULL;

		if (0 != chdir(home))
			return NULL;

		synch_cwd(&current, true);
		return NULL;
	}

/* not that we are a posix shell, but should -L / -P be supported?
 * right now it isn't - possibly that the shell type should be a .so
 * plugin that gets to override builtins and prompt */
	if (0 == chdir(argv[1])){
		synch_cwd(&current, true);
	}

	return NULL;
}

static struct ext_cmd* cmd_mode(
	struct cli_state* state, char** argv, ssize_t* ofs, char** err)
{
/* with completion / eval we won't get here either so no need to propagate
 * error as it'll be fixed elsewhere */
	if (!argv[1]){
		return NULL;
	}

	if (strcmp(argv[1], "x11") == 0){
		state->mode = LAUNCH_X11;
	}
	else if (strcmp(argv[1], "tui") == 0){
		state->mode = LAUNCH_TUI;
	}
	else if (strcmp(argv[1], "wl") == 0 || strcmp(argv[1], "wayland") == 0){
		state->mode = LAUNCH_WL;
	}
	else if (strcmp(argv[1], "arcan") == 0){
		state->mode = LAUNCH_SHMIF;
	}
	else if (strcmp(argv[1], "vt100") == 0){
		state->mode = LAUNCH_VT100;
	}

	return NULL;
}

/* need a better helper for this that would respect env and so on */
static char* get_decode_bin()
{
	struct stat statbuf;
	if (-1 != stat("/usr/local/bin/afsrv_decode", &statbuf))
		return "/usr/local/bin/afsrv_decode";

	if (-1 != stat("/usr/bin/afsrv_decode", &statbuf))
		return "/usr/bin/afsrv_decode";

	return "afsrv_decode";
}

static void drop_descriptor(uintptr_t tag)
{
	close(tag);
}

static struct ext_cmd* cmd_open(
	struct cli_state* state, char** argv, ssize_t* ofs, char** err)
{
/* should be able to leverage afsrv_decode probe more here to figure out
 * if / what the best way to decode would be */
	if (!argv[1])
		return NULL;

	char* bin = get_decode_bin();

	int fd = open(argv[1], O_RDONLY);
	if (-1 == fd){
/* some error code propagation here? */
		return NULL;
	}

/* setup ARCAN_ARG=proto=media:fd=%d */
	char** env = malloc(sizeof(char*) * 1);
	if (!env){
		close(fd);
		return NULL;
	}
	env[0] = env[1] = NULL;

	struct ext_cmd* res = malloc(sizeof(struct ext_cmd));
	*res = (struct ext_cmd){
		.flags = 0xf, /* detach and null stdios */
		.env = env,
		.mode = LAUNCH_SHMIF,
	};

	res->argv = malloc(sizeof(char*) * 2);
	if (!res->argv){
		close(fd);
		free(res->env);
		free(res);
		return NULL;
	}

	res->argv[0] = strdup(bin);
	res->argv[1] = NULL;

	asprintf(&env[0], "ARCAN_ARG=proto=media:fd=%d", fd);
	res->closure = drop_descriptor;
	res->closure_tag = (uintptr_t) fd;

	return res;
}

static struct ext_cmd* cmd_exit(
	struct cli_state* state, char** argv, ssize_t* ofs, char** err)
{
	state->alive = false;
	return NULL;
}

/* this should really be an option that sets up a debug subsegment that
 * chainloads the real binary with gdb attached like the preload tool we have */
static struct ext_cmd* cmd_debugstall(
	struct cli_state* state, char** argv, ssize_t* ofs, char** err)
{
	if (state->in_debug)
		return state->in_debug = NULL, NULL;

	state->in_debug = strdup("ARCAN_FRAMESERVER_DEBUGSTALL=10");
	return NULL;
}

/*
 * these all lack the completion interface, underlying UI path still
 * in progress
 */
struct cli_command commands[] = {
	{
		.name = "cd",
		.exec = cmd_cd
	},
	{
		.name = "mode",
		.exec = cmd_mode
	},
	{
		.name = "open",
		.exec = cmd_open
	},
	{
		.name = "exit",
		.exec = cmd_exit
	},
	{
		.name = "debugstall",
		.exec = cmd_debugstall
	}
};

struct cli_command* cli_get_builtin(const char* cmd)
{
	if (!cmd || strlen(cmd) == 0)
		return NULL;

	for (size_t i = 0; i < COUNT_OF(commands); i++){
		if (strcmp(cmd, commands[i].name) == 0)
			return &commands[i];
	}

	return NULL;
}
