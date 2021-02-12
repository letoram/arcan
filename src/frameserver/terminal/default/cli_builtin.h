#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))

enum launch_mode {
	LAUNCH_UNSET = 0,
	LAUNCH_VT100 = 1,
	LAUNCH_TUI   = 2,
	LAUNCH_WL    = 3,
	LAUNCH_X11   = 4,
	LAUNCH_SHMIF = 5
};

struct ext_cmd {
	uint32_t id;
	int flags;
	char** argv;
	char** env;
	char* wd;
	enum launch_mode mode;
	bool stall;
	void(*closure)(uintptr_t);
	uintptr_t closure_tag;
};

struct cli_state {
	char** env;
	char* cwd;
	enum launch_mode mode;
	bool alive;
	uint8_t bgalpha;

/* set alive to false when last pending ext_cmd has been finished */
	bool die_on_finish;

	uint32_t id_counter;
	struct ext_cmd pending[4];
	bool blocked;
	char* in_debug;
	struct tui_cell* prompt;
	size_t prompt_sz;
};

struct cli_command {
	const char* name;
	struct ext_cmd* (*exec)(
		struct cli_state* state, char** argv, ssize_t* ofs, char** err);

/* expect for the first argument, this follows the structure of tui cli_command
 * for help with completion / expansion */
	int (*cli_command)(struct cli_state* state,
		const char** const argv, size_t n_elem, int command,
		const char** feedback, size_t* n_results);
};

/*
 * return the built-in CLI command matching (exec)
 */
struct cli_command* cli_get_builtin(const char* cmd);

/*
 * split up message into a dynamically allocated array of dynamic
 * strings according to the following rules:
 *
 * global-state:
 *  \ escapes next character
 *    ends argument
 *
 * group_tbl (string of possible group characters, e.g. "'`),
 *           ends with an empty group (.enter == 0)
 *
 * character in group_tbl begins and ends a nested expansion that
 * will be expanded according to the expand callback and the group.
 *
 * the returned string will be added to the resulting string table
 * verbatim.
 */
struct group_ent;
struct group_ent {
	char enter;
	char leave;
	bool leave_eol;
	char* (*expand)(struct group_ent*, const char*);
};

struct argv_parse_opt {
	size_t prepad;
	struct group_ent* groups;
	char sep;
};

char** extract_argv(const char* message,
	struct argv_parse_opt opts, ssize_t* err_ofs);
