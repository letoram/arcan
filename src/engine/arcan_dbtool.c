/*
 * Copyright 2014-2015, Björn Ståhl
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

void arcan_warning(const char*, ...);

static void usage()
{
printf("usage: arcan_db dbfile command args\n\n"
	"Available data creation / manipulation commands: \n"
	"  add_target      \tname executable bfrm argv\n"
	"  add_target_kv   \ttarget name key value\n"
	"  add_target_env  \ttarget name key value\n"
	"  add_target_lib  \ttarget name libstr\n"
	"  add_config      \ttarget name argv\n"
	"  add_config_kv   \ttarget config name key val\n"
	"  add_config_env  \ttarget config name key val\n"
	"  drop_config     \ttarget config\n"
	"  drop_all_configs\ttarget\n"
	"  drop_target    \tname\n"
	"  drop_appl      \tname\n"
	"\nAvailable data extraction commands: \n"
	"  dump_targets   \n"
	"  dump_target    \tname\n"
	"  dump_config    \ttargetname configname\n"
	"  dump_appl      \tapplname\n"
	"  dump_exec      \ttargetname configname\n"
	"Accepted keys are restricted to the set [a-Z0-9_]\n\n"
	"alternative (scripted) usage: arcan_db dbfile -\n"
 	"above commands are supplied using STDIN, tab as arg separator, linefeed \n"
	"as command submit. Close stdin to terminate execution.\n"
	);
}

static bool validate_key(const char* key)
{
	while(*key){
		if (!isalnum(*key) && *key++ != '_')
			return false;
	}

	return true;
}

static int add_target(struct arcan_dbh* dst, int argc, char** argv)
{
	enum DB_BFORMAT bfmt;

	if (argc < 3){
		printf("add_target(name executable bfmt argv) unexpected "
			"number of arguments, (%d) vs 3+.\n", argc);

		return EXIT_FAILURE;
	}

	if (strcmp(argv[2], "BIN") == 0)
		bfmt = BFRM_BIN;
	else if (strcmp(argv[2], "LWA") == 0)
		bfmt = BFRM_LWA;
	else if (strcmp(argv[2], "RETRO") == 0)
		bfmt = BFRM_RETRO;
	else if (strcmp(argv[2], "EXTERN") == 0)
		bfmt = BFRM_EXTERN;
	else {
		printf("add_target(name executable bfmt argv) unknown bfmt specified, "
			" accepted (BIN, LWA, RETRO).\n");

		return EXIT_FAILURE;
	}

	arcan_targetid tid = arcan_db_addtarget(
		dst, argv[0], argv[1], (const char**) &argv[3], argc - 3, bfmt);

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

	arcan_db_dropappl(dst, argv[1]);
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

	if (strcmp(argv[1], "default") == 0){
		printf("drop_config, deleting 'default' configuration is not permitted.\n");
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
	arcan_db_add_kvpair(dst, key, val);
	arcan_db_end_transaction(dst);

	return EXIT_SUCCESS;
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
		printf("invalid key specified (restricted to [a-Z0-9_])\n");
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
		printf("invalid key specified (restricted to [a-Z0-9_])\n");
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

static int dump_target(struct arcan_dbh* dbh, int argc, char** argv)
{
	if (argc != 1){
		printf("dump_target(target), invalid number "
			"of arguments (%d vs 1).\n", argc);

		return EXIT_FAILURE;
	}

	union arcan_dbtrans_id id;
	id.tid = arcan_db_targetid(dbh, argv[0], NULL);

	struct arcan_strarr res = arcan_db_configs(dbh, id.tid);
	assert(res.data != NULL);

	if (!res.data){
		printf("dump_targets(), no valid list returned.\n");
		return EXIT_FAILURE;
	}

	char* exec = arcan_db_execname(dbh, id.tid);

	printf("target (%s)\nexecutable:%s\nconfigurations:\n", argv[0],
		exec ? exec : "(none)");
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

static int dump_config(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 2){
		printf("dump_config(target, config) invalid number "
			"of arguments (%d vs 2).\n", argc);
		return EXIT_FAILURE;
	}

	union arcan_dbtrans_id tgt, cfg;
	tgt.tid = arcan_db_targetid(dst, argv[0], NULL);
	cfg.cid = arcan_db_configid(dst, tgt.tid, argv[1]);

	struct arcan_strarr res = arcan_db_config_argv(dst, tgt.cid);

	if (!res.data){
		printf("dump_targets(), no valid list returned.\n");
		return EXIT_FAILURE;
	}

	printf("target (%s) config (%s)\narguments:\n\t", argv[0], argv[1]);

	char** curr = res.data;
	while(*curr)
		printf("%s \n", *curr++);
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

static int dump_exec(struct arcan_dbh* dst, int argc, char** argv)
{
	struct arcan_strarr env = {0};
	struct arcan_strarr outargv = {0};
	struct arcan_strarr libs = {0};

	if (argc <= 0 || argc > 2){
		printf("dump_exec(target, [config]) invalid number"
			" of arguments (%d vs (1,2)).\n", argc);
		return EXIT_FAILURE;
	}

	arcan_configid cfgid = arcan_db_configid(dst, arcan_db_targetid(
		dst, argv[0], NULL), argc == 1 ? "default" : argv[1]);

	enum DB_BFORMAT bfmt;
	char* execstr = arcan_db_targetexec(dst, cfgid, &bfmt, &outargv, &env, &libs);
	if (!execstr){
		printf("couldn't generate execution string\n");
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

static int dump_targets(struct arcan_dbh* dst, int argc, char** argv)
{
	struct arcan_strarr res = arcan_db_targets(dst);
	if (!res.data){
		printf("dump_targets(), no valid list returned.\n");
		return EXIT_FAILURE;
	}

	char** curr = res.data;
	while(*curr)
		printf("%s\n", *curr++);
	arcan_mem_freearr(&res);

	return EXIT_SUCCESS;
}

static int dump_appl(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc <= 0){
		printf("dump_appl(), no appl name specified.\n");
		return EXIT_FAILURE;
	}

	const char* ptn = argc > 1 ? argv[1] : "%";

	struct arcan_strarr res = arcan_db_applkeys(dst, argv[0], ptn);
	if (!res.data){
		printf("dump_appl(), no valid list returned");
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
		.key = "dump_appl",
		.fun = dump_appl
	},
	{
		.key = "dump_config",
		.fun = dump_config
	},

	{
		.key = "dump_target",
		.fun = dump_target
	},

	{
		.key = "dump_targets",
		.fun = dump_targets
	},

	{
		.key = "add_config_env",
		.fun = add_config_env
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
		.key = "dump_exec",
		.fun = dump_exec
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
	if (argc < 3){
		usage();
		return EXIT_FAILURE;
	}

	struct arcan_dbh* dbhandle = arcan_db_open(argv[1], "arcan");
	if (!dbhandle){
		arcan_warning("database (%s) not found, creating.\n", argv[1]);
		FILE* fpek = fopen(argv[1], "w+");
		if (fpek)
			fclose(fpek);
		dbhandle = arcan_db_open(argv[1], "arcan");
		if (!dbhandle){
			arcan_warning("couldn't create database (%s).\n", argv[1]);
			return EXIT_FAILURE;
		}
	}

	if (strcmp(argv[2], "-") == 0){
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
		if (strcmp(dispatch[i].key, argv[2]) == 0){
			int rc = dispatch[i].fun(dbhandle, argc-3, &argv[3]);
			arcan_db_close(&dbhandle);
			return rc;
		}

	usage();
	return EXIT_FAILURE;
}
