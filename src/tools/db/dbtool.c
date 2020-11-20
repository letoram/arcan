/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>
#include <ctype.h>

#include <string.h>
#include <assert.h>

#include "arcan_mem.h"
#include "arcan_db.h"

#include "../frameserver/util/utf8.c"

void arcan_warning(const char*, ...);
char* platform_dbstore_path();

static void usage()
{
	printf("usage: arcan_db [-d dbfile] command args\n\n"
	"Available data creation / manipulation commands: \n"
	"  add_target      \tname (-tag) bfrm executable argv\n"
	"  add_target_kv   \ttarget key value\n"
	"  add_target_env  \ttarget key value\n"
	"  add_target_lib  \ttarget libstr\n"
	"  add_config      \ttarget argv\n"
	"  add_config_kv   \ttarget config key val\n"
	"  add_config_env  \ttarget config key val\n"
	"  add_appl_kv     \tappl key value\n"
	"  drop_appl_key   \tappl\n"
	"  drop_config     \ttarget config\n"
	"  drop_all_configs\ttarget\n"
	"  drop_target    \tname\n"
	"  drop_appl      \tname\n"
	"\nAvailable data extraction commands: \n"
	"  list_targets   \n"
	"  list_tags      \n"
	"  list_appls     \n"
	"  show_target    \tname\n"
	"  show_config    \ttargetname configname\n"
	"  show_appl      \tapplname\n"
	"  show_exec      \ttargetname configname\n"
	"Accepted keys are restricted to the set [a-Z0-9_+=/]\n\n"
	"alternative (scripted) usage: arcan_db dbfile -\n"
 	"above commands are supplied using STDIN, tab as arg separator, linefeed \n"
	"as command submit. Close stdin to terminate execution.\n"
	);
}

static bool validate_key(const char* key)
{
/* accept 0-9 and base64 valid values */
	while(*key){
		if (!isalnum(*key) && *key != '_'
			&& *key != '+' && *key != '/' && *key != '=')
			return false;
		key++;
	}

	return true;
}

static bool valid_str(const char* msg)
{
	uint32_t state = 0, codepoint = 0, len = 0;
	while(msg[len])
		if (UTF8_REJECT == utf8_decode(&state, &codepoint,(uint8_t)(msg[len++])))
			return false;

	return state == UTF8_ACCEPT;
}

static int add_target(struct arcan_dbh* dst, int argc, char** argv)
{
	enum DB_BFORMAT bfmt;

	if (argc < 3){
		printf("add_target(name (-tag) bfmt executable argv) unexpected "
			"number of arguments, (%d) vs 3+.\n\t accepted bfmts:"
			" BIN, LWA, GAME, SHELL, EXTERN\n", argc);

		return EXIT_FAILURE;
	}

	int fi = 1;
	const char* tag = "default";
	if (argv[1][0] == '-'){
		tag = &argv[1][1];
		fi++;
	}

	if (strcmp(argv[fi], "BIN") == 0)
		bfmt = BFRM_BIN;
	else if (strcmp(argv[fi], "LWA") == 0)
		bfmt = BFRM_LWA;
	else if (strcmp(argv[fi], "GAME") == 0)
		bfmt = BFRM_GAME;
	else if (strcmp(argv[fi], "SHELL") == 0)
		bfmt = BFRM_SHELL;
	else if (strcmp(argv[fi], "EXTERNAL") == 0)
		bfmt = BFRM_EXTERN;
	else {
		printf("add_target(name (-tag) *bfrm* executable argv\n"
			"unknown bfrm, %s - accepted (BIN, LWA, GAME, SHELL, EXTERNAL).\n", argv[fi]);

		return EXIT_FAILURE;
	}

	if (!valid_str(argv[0])){
		printf("add_target(name), invalid/incomplete UTF8 sequence in name\n");
		return EXIT_FAILURE;
	}

	arcan_targetid tid = arcan_db_addtarget(
		dst, argv[0], tag, argv[fi+1], (const char**) &argv[fi+2], argc-fi-2, bfmt);

	if (tid == BAD_TARGET){
		printf("couldn't add target (%s)\n", argv[0]);
		return EXIT_FAILURE;
	}

	arcan_db_addconfig(dst, tid, "default", NULL, 0);

	return EXIT_SUCCESS;
}

static int drop_appl(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 1){
		printf("drop_appl(appl) unexpected number of "
			"arguments (%d vs 1)\n", argc);
		return EXIT_FAILURE;
	}

	arcan_db_dropappl(dst, argv[0]);
	return EXIT_SUCCESS;
}

static int drop_target(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 1){
		printf("drop_target(target) unexpected number of "
			"arguments (%d vs 1)\n", argc);

		return EXIT_FAILURE;
	}

	arcan_targetid tid = arcan_db_targetid(dst, argv[0], NULL);

	if (tid == BAD_TARGET){
		printf("couldn't find a matching target for (%s).\n", argv[0]);
		return EXIT_FAILURE;
	}

	return arcan_db_droptarget(dst, tid) ? EXIT_SUCCESS : EXIT_FAILURE;
}

static int drop_config(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 2){
		printf("drop_config(target, config) unexpected number of "
			"arguments (%d vs 2)\n", argc);

		return EXIT_FAILURE;
	}

	arcan_targetid tid = arcan_db_targetid(dst, argv[0], NULL);

	if (tid == BAD_TARGET){
		printf("couldn't find a matching target for (%s).\n", argv[0]);
		return EXIT_FAILURE;
	}

	arcan_configid cid = arcan_db_configid(dst, tid, argv[1]);
	if (cid == BAD_CONFIG){
		printf("couldn't find a matching config for (%s).\n", argv[1]);
	}

	return arcan_db_dropconfig(dst, cid) ? EXIT_SUCCESS : EXIT_FAILURE;
}

static int drop_all_config(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 1){
		printf("drop_all_configs(target), invalid number "
			"of arguments (%d vs 1).\n", argc);
		return EXIT_FAILURE;
	}

	union arcan_dbtrans_id id;
	id.tid = arcan_db_targetid(dst, argv[0], NULL);
	struct arcan_strarr res = arcan_db_configs(dst, id.tid);
	if (!res.data){
		printf("drop_all_configs(target), no valid list returned.\n");
		return EXIT_FAILURE;
	}

	char** curr = res.data;
	while(*curr){
		arcan_configid cid = arcan_db_configid(dst, id.tid, *curr++);
		if (cid != BAD_CONFIG)
			arcan_db_dropconfig(dst, cid);
	}
	arcan_mem_freearr(&res);
	return EXIT_SUCCESS;
}

static int set_kv(struct arcan_dbh* dst,
	enum DB_KVTARGET tgt, union arcan_dbtrans_id id,
		char* key, char* val)
{
	arcan_db_begin_transaction(dst, tgt, id);
	arcan_db_add_kvpair(dst, key, strlen(val) > 0 ? val : NULL);
	arcan_db_end_transaction(dst);

	return EXIT_SUCCESS;
}

static int add_appl_kv(struct arcan_dbh* dst, int argc, char** argv)
{
	union arcan_dbtrans_id id;
	if (argc != 3){
		printf("add_appl_kv(appl, key, val) "
			"invalid number of arguments, %d vs 3\n", argc);

		return EXIT_FAILURE;
	}

	if (strlen(argv[0]) == 0){
		printf("invalid appl specified (0-length) \n");
		return EXIT_FAILURE;
	}

	if (!validate_key(argv[1])){
		printf("invalid key specified (restricted to [a-Z0-9_+/=])\n");
		return EXIT_FAILURE;
	}

	return arcan_db_appl_kv(dst, argv[0],
		argv[1], strlen(argv[2]) > 0 ? argv[2] : NULL) ?
		EXIT_SUCCESS : EXIT_FAILURE;
}

static int drop_appl_key(struct arcan_dbh* dst, int argc, char** argv)
{
	union arcan_dbtrans_id id;
	if (argc != 2){
		printf("drop_appl_key(appl, key) "
			"invalid number of arguments, %d vs 2\n", argc);

		return EXIT_FAILURE;
	}

	if (strlen(argv[0]) == 0){
		printf("invalid appl specified (0-length) \n");
		return EXIT_FAILURE;
	}

	if (!validate_key(argv[1])){
		printf("invalid key specified (restricted to [a-Z0-9_+/=])\n");
		return EXIT_FAILURE;
	}

	return arcan_db_appl_kv(dst, argv[0], argv[1], NULL) ?
		EXIT_SUCCESS : EXIT_FAILURE;
}


static int add_target_kv(struct arcan_dbh* dst, int argc, char** argv)
{
	union arcan_dbtrans_id id;
	if (argc != 3){
		printf("add_target_kv(target, key, val) "
			"invalid number of arguments, %d vs 3\n", argc);

		return EXIT_FAILURE;
	}

	if (!validate_key(argv[1])){
		printf("invalid key specified (restricted to [a-Z0-9_+/=])\n");
		return EXIT_FAILURE;
	}

	id.tid = arcan_db_targetid(dst, argv[0], NULL);

	if (id.tid == BAD_TARGET){
		printf("unknown target (%s) for add_target_kv\n", argv[0]);
		return EXIT_FAILURE;
	}

	return set_kv(dst, DVT_TARGET, id, argv[1], argv[2]);
}

static int add_target_env(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 3){
		printf("add_target_env(target, key, val) "
			"invalid number of arguments, %d vs 3", argc);

		return EXIT_FAILURE;
	}

	union arcan_dbtrans_id id;
	id.tid = arcan_db_targetid(dst, argv[0], NULL);

	if (id.tid == BAD_TARGET){
		printf("unknown target (%s) for add_target_env\n", argv[0]);
		return EXIT_FAILURE;
	}

	return set_kv(dst, DVT_TARGET_ENV, id, argv[1], argv[2]);
}

static int add_target_libv(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 2){
		printf("add_target_lib (target, soname) "
			"invalid number of arguments, %d vs 2", argc);

		return EXIT_FAILURE;
	}

	union arcan_dbtrans_id id;
	id.tid = arcan_db_targetid(dst, argv[0], NULL);

	if (id.tid == BAD_TARGET){
		printf("unknown target (%s) for add_target_libv\n", argv[0]);
		return EXIT_FAILURE;
	}

	return set_kv(dst, DVT_TARGET_LIBV, id, argv[1], "");
}

static int add_config(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc < 2){
		printf("add_config(target, identifier, argv) invalid number"
			" of arguments (%d vs at least 2).\n", argc);
		return EXIT_FAILURE;
	}

	arcan_targetid tid = arcan_db_targetid(dst, argv[0], NULL);

	if (tid == BAD_TARGET){
		printf("couldn't find a matching target for (%s).\n", argv[0]);
		return EXIT_FAILURE;
	}

	if (!valid_str(argv[1])){
		printf("add_config(identifier), invalid/incomplete UTF8 sequence\n");
		return EXIT_FAILURE;
	}

	arcan_db_addconfig(dst, tid, argv[1], (const char**) &argv[2], argc - 2);

	return EXIT_SUCCESS;
}

static int add_config_kv(struct arcan_dbh* dst, int argc, char** argv)
{
	union arcan_dbtrans_id id;
	if (argc != 4){
		printf("add_config_kv(target, config, key, value) invalid number"
			" of arguments (%d vs 4).\n", argc);
		return EXIT_FAILURE;
	}

	if (!validate_key(argv[2])){
		printf("invalid key specified (restricted to [a-Z0-9_/+=])\n");
		return EXIT_FAILURE;
	}

	id.cid = arcan_db_configid(dst, arcan_db_targetid(
		dst, argv[0], NULL), argv[1]);

	return set_kv(dst, DVT_CONFIG, id, argv[2], argv[3]);
}

static int add_config_env(struct arcan_dbh* dst, int argc, char** argv)
{
	union arcan_dbtrans_id id;
	if (argc != 4){
		printf("add_config_env(target config key value) invalid number"
			"of arguments (%d vs 4).\n", argc);
		return EXIT_FAILURE;
	}

	id.cid = arcan_db_configid(dst, arcan_db_targetid(
		dst, argv[0], NULL), argv[1]);

	return set_kv(dst, DVT_CONFIG_ENV, id, argv[2], argv[3]);
}

static int show_target(struct arcan_dbh* dbh, int argc, char** argv)
{
	if (argc != 1){
		printf("show_target(target), invalid number "
			"of arguments (%d vs 1).\n", argc);

		return EXIT_FAILURE;
	}

	union arcan_dbtrans_id id;
	id.tid = arcan_db_targetid(dbh, argv[0], NULL);

	struct arcan_strarr res = arcan_db_configs(dbh, id.tid);
	assert(res.data != NULL);

	if (!res.data){
		printf("show_target(), no valid target data returned.\n");
		return EXIT_FAILURE;
	}

	char* exec = arcan_db_execname(dbh, id.tid);
	char* tag = arcan_db_targettag(dbh, id.tid);

	printf("target (%s), tag: (%s)\nexecutable:%s\nconfigurations:\n", argv[0],
		tag, exec ? exec : "(none)");
	char** curr = res.data;
	while(*curr)
		printf("\t%s\n", *curr++);
	arcan_mem_freearr(&res);

	printf("\narguments: \n\t");
	res = arcan_db_target_argv(dbh, id.tid);
	curr = res.data;
	while(*curr)
		printf("%s ", *curr++);
	arcan_mem_freearr(&res);

	printf("\n\nkvpairs:\n");
	res = arcan_db_getkeys(dbh, DVT_TARGET, id);
	curr = res.data;
	while(*curr)
		printf("\t%s\n", *curr++);
	arcan_mem_freearr(&res);
	printf("\n");

	free(exec);
	return EXIT_SUCCESS;
}

static int show_config(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 2){
		printf("show_config(target, config) invalid number "
			"of arguments (%d vs 2).\n", argc);
		return EXIT_FAILURE;
	}

	union arcan_dbtrans_id tgt, cfg;
	tgt.tid = arcan_db_targetid(dst, argv[0], NULL);
	cfg.cid = arcan_db_configid(dst, tgt.tid, argv[1]);

	struct arcan_strarr res = arcan_db_config_argv(dst, cfg.cid);

	if (!res.data){
		printf("show_config(), no valid config data returned.\n");
		return EXIT_FAILURE;
	}

	printf("target (%s) config (%s)\narguments:\n", argv[0], argv[1]);

	int count = 1;
	char** curr = res.data;
	while(*curr)
		printf("%d\t%s \n", count++, *curr++);
	arcan_mem_freearr(&res);

	printf("\n\nkvpairs:\n");
	res = arcan_db_getkeys(dst, DVT_CONFIG, cfg);
	curr = res.data;
	while(*curr)
		printf("\t%s\n", *curr++);
	arcan_mem_freearr(&res);
	printf("\n");

	return EXIT_SUCCESS;
}

static int show_exec(struct arcan_dbh* dst, int argc, char** argv)
{
	struct arcan_strarr env = {0};
	struct arcan_strarr outargv = {0};
	struct arcan_strarr libs = {0};

	if (argc != 2){
		printf("show_exec(target, config) invalid number"
			" of arguments (%d vs 2).\n", argc);
		return EXIT_FAILURE;
	}

	arcan_configid cfgid = arcan_db_configid(dst, arcan_db_targetid(
		dst, argv[0], NULL), argv[1]);

	enum DB_BFORMAT bfmt;
	char* execstr = arcan_db_targetexec(dst, cfgid, &bfmt, &outargv, &env, &libs);
	if (!execstr){
		printf("show_exec() couldn't generate execution string\n");
		return EXIT_FAILURE;
	}

	if (outargv.data){
		printf("ARGV:\n");
		char** curr = outargv.data;
		while(*curr)
			printf("\t%s\n", *curr++);
	}
	else
		printf("ARGV: empty\n");

	if (env.data){
		printf("ENV:\n");
		char** curr = env.data;
		while(*curr)
			printf("\t%s\n", *curr++);
	}
	else
		printf("ENV: empty\n");

	return EXIT_SUCCESS;
}

static int list_targets(struct arcan_dbh* dst, int argc, char** argv)
{
	struct arcan_strarr res = arcan_db_targets(dst, NULL);
	if (!res.data){
		printf("list_targets(), no valid list of targets returned.\n");
		return EXIT_FAILURE;
	}

	char** curr = res.data;
	while(*curr)
		printf("%s\n", *curr++);
	arcan_mem_freearr(&res);

	return EXIT_SUCCESS;
}

static int list_tags(struct arcan_dbh* dst, int argc, char** argv)
{
	struct arcan_strarr res = arcan_db_target_tags(dst);
	if (!res.data){
		printf("list_tags(), no valid list of tags returned.\n");
		return EXIT_FAILURE;
	}

	char** curr = res.data;
	while (*curr)
		printf("%s\n", *curr++);
	arcan_mem_freearr(&res);

	return EXIT_SUCCESS;
}

static int list_appls(struct arcan_dbh* dst, int argc, char** argv)
{
	struct arcan_strarr res = arcan_db_list_appl(dst);
	if (!res.data){
		printf("list_tags(), no valid list of tags returned.\n");
		return EXIT_FAILURE;
	}

/* always prefixed appl_ */
	char** curr = res.data;
	while (*curr){
		printf("%s\n", &(*curr)[5]);
		curr++;
	}
	arcan_mem_freearr(&res);

	return EXIT_SUCCESS;
}

static int show_appl(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc <= 0){
		printf("show_appl(), no appl name specified.\n");
		return EXIT_FAILURE;
	}

	const char* ptn = argc > 1 ? argv[1] : "%";

	struct arcan_strarr res = arcan_db_applkeys(dst, argv[0], ptn);
	if (!res.data){
		printf("show_appl(), no valid list returned");
		return EXIT_FAILURE;
	}

	char** curr = res.data;
	while(*curr)
		printf("%s\n", *curr++);

	arcan_mem_freearr(&res);
	return EXIT_SUCCESS;
}

struct {
	const char* key;
	int (*fun)(struct arcan_dbh*, int, char**);
} dispatch[] = {
	{
		.key = "add_target",
		.fun = add_target
	},
	{
		.key = "drop_target",
		.fun = drop_target
	},
	{
		.key = "show_appl",
		.fun = show_appl
	},
	{
		.key = "show_config",
		.fun = show_config
	},

	{
		.key = "show_target",
		.fun = show_target
	},

	{
		.key = "list_targets",
		.fun = list_targets
	},

	{
		.key = "list_tags",
		.fun = list_tags
	},
	{
		.key = "list_appls",
		.fun = list_appls
	},
	{
		.key = "add_config_env",
		.fun = add_config_env
	},

	{
		.key = "add_appl_kv",
		.fun = add_appl_kv
	},

	{
		.key = "drop_appl_key",
		.fun = drop_appl_key
	},

	{
		.key = "add_target_kv",
		.fun = add_target_kv
	},

	{
		.key = "add_config_kv",
		.fun = add_config_kv
	},

	{
		.key = "add_config",
		.fun = add_config
	},

	{
		.key = "drop_config",
		.fun = drop_config
	},
	{
		.key = "drop_appl",
		.fun = drop_appl
	},
	{
		.key = "drop_all_configs",
		.fun = drop_all_config
	},

	{
		.key = "add_target_env",
		.fun = add_target_env
	},

	{
		.key = "add_target_lib",
		.fun = add_target_libv
	},
	{
		.key = "show_exec",
		.fun = show_exec
	}
};

static char* grow(char* inp, size_t* outsz)
{
	*outsz += 64;
	char* res = realloc(inp, *outsz);
	if (!res){
		free(inp);
		*outsz = 0;
		return NULL;
	}

	return res;
}

static inline void process_line(char* in, struct arcan_dbh* dbh)
{
	char* argv[64] = {0};
	int argc = 0;

	char* work = strtok(in, "\t");
	while (work && argc < 63){
    argv[argc++] = work;
    work = strtok(NULL, "\t");
  }

	for (size_t i=0; i < sizeof(dispatch) / sizeof(dispatch[0]); i++)
		if (strcmp(dispatch[i].key, argv[0]) == 0){
			if (EXIT_SUCCESS == dispatch[i].fun(dbh, argc-1, &argv[1]))
				fprintf(stderr, "OK\n");
			else
				fprintf(stderr, "FAIL\n");
		}
}

int main(int argc, char* argv[])
{
	if (argc < 2){
		usage();
		return EXIT_FAILURE;
	}

	char* dbfile = NULL;
	int startind = 1;

#ifdef __OpenBSD__
	pledge("stdio cpath rpath wpath flock", "");
#endif

	if (strcmp(argv[1], "-d") == 0){
		if (argc < 3){
			arcan_warning("got -d but missing database file argument\n");
			usage();
			return EXIT_FAILURE;
		}

		for (int i = 0; i < sizeof(dispatch)/sizeof(dispatch[0]); i++)
			if (strcmp(argv[2], dispatch[i].key) == 0){
				arcan_warning("got command (%s) in database filename slot\n");
				usage();
				return EXIT_FAILURE;
		}

		dbfile = argv[2];
		startind = 3;
		if (argc < 4){
			usage();
			return EXIT_FAILURE;
		}
	}
	else
		dbfile = platform_dbstore_path();

/* early out on --help or -h */
	for (size_t i = 1; i < argc; i++){
		if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0){
			usage();
			return EXIT_SUCCESS;
		}
	}

	struct arcan_dbh* dbhandle = arcan_db_open(dbfile, "arcan");
	if (!dbhandle){
		arcan_warning("database (%s) could not be opened/created.\n", dbfile);
		return EXIT_FAILURE;
	}

	if (strcmp(argv[startind], "-") == 0){
		char* inbuf = NULL;
		size_t bufsz = 0, bufofs = 0;
		inbuf = grow(inbuf, &bufsz);

		while(!feof(stdin)){
			int ch = fgetc(stdin);

			if (bufofs == bufsz - 1)
				if (!( inbuf = grow(inbuf, &bufsz)) ){
					fprintf(stderr, "couldn't grow input buffer\n");
					return EXIT_FAILURE;
				}

			if (-1 == ch)
				continue;

			if ('\n' == ch || '\0' == ch){
				inbuf[bufofs] = '\0';
				process_line(inbuf, dbhandle);
				bufofs = 0;
			}
			else
				inbuf[bufofs++] = ch;
		}

		if (bufofs == bufsz)
			if (!( inbuf = grow(inbuf, &bufsz)) )
				return EXIT_FAILURE;

		if (bufofs > 0){
			inbuf[bufofs] = '\0';
			process_line(inbuf, dbhandle);
		}
		free(inbuf);

		return EXIT_SUCCESS;
	}

	for (size_t i=0; i < sizeof(dispatch) / sizeof(dispatch[0]); i++)
		if (strcmp(dispatch[i].key, argv[startind]) == 0){
			int rc = dispatch[i].fun(dbhandle, argc-startind-1, &argv[startind+1]);
			arcan_db_close(&dbhandle);
			return rc;
		}

	usage();
	return EXIT_FAILURE;
}
