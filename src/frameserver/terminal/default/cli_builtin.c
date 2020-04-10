#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <string.h>
#include "cli_builtin.h"

static struct ext_cmd* cmd_cd(
	struct cli_state* state, char** argv, ssize_t* ofs, char** err)
{
	*ofs = -1;
	*err = NULL;

	return NULL;
}

struct cli_command commands[] = {
	{
		.name = "cd",
		.exec = cmd_cd
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
