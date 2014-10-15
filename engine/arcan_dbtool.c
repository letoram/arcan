/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA.
 *
 */
#include <stdlib.h>
#include <unistd.h>
#include <stdio.h>
#include <stdint.h>
#include <stdbool.h>

#include <string.h>
#include <assert.h>
#include "arcan_db.h"

void arcan_warning(const char*, ...);

static void usage()
{
printf("usage: arcan_db dbfile command args\n\n"
	"Available data creation / manipulation commands: \n"
	"  add_target     \tname executable argv\n"
	"  add_target_kv  \ttarget name key value\n"
	"  add_target_env \ttarget name key value\n"
	"  set_target_libs\ttarget name libstr\n"
	"  add_config     \ttarget name argv\n"
	"  add_config_kv  \ttarget config name key val\n"
	"  add_config_env \ttarget config name key val\n"
	"  drop_config    \ttarget config\n"
	"  drop_target    \tname\n"
	"\nAvailable data extraction commands: \n"
	"  dump_targets   \n"
	"  dump_target    \tname\n"
	"  dump_config    \ttargetname configname\n"
	"  dump_appl      \tapplname\n"
	"  dump_exec      \ttargetname configname\n\n"
	"alternative (scripted) usage: arcan_db dbfile -\n"
 	"    above commands are supplied using STDIN and linefeed as separator\n"
	"    empty line terminates execution."
	);
}

static int add_target(struct arcan_dbh* dst, int argc, char** argv)
{
	int type = BFRM_ELF;

	if (argc < 2){
		printf("unexpected numbver of arguments, (%d) vs at least 2.\n", argc);
		return EXIT_FAILURE;
	}

	arcan_targetid tid = arcan_db_addtarget(
		dst, argv[0], argv[1], (const char**) &argv[2], argc - 2, type);

	if (tid == BAD_TARGET){
		printf("couldn't add target (%s)\n", argv[0]);
		return EXIT_FAILURE;
	}

	arcan_db_addconfig(dst, tid, "default", NULL, 0);

	return EXIT_SUCCESS;

	printf("couldn't set target, expected targetname, path and optional "
		"binary format (accepted: ELF, LWA, RETRO)\n");
	return EXIT_FAILURE;
}

static int drop_target(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 1){
		printf("drop_target, unexpected number of arguments (%d vs 1)\n", argc);
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
		printf("drop_config, unexpected number of arguments (%d vs 2)\n", argc);
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
			"invalid number of arguments, %d vs 3", argc);

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
if (argc != 3){
		printf("add_target_lib (target, domain/order, soname) "
			"invalid number of arguments, %d vs 3", argc);

		return EXIT_FAILURE;
	}

	union arcan_dbtrans_id id;
	id.tid = arcan_db_targetid(dst, argv[0], NULL);

	if (id.tid == BAD_TARGET){
		printf("unknown target (%s) for add_target_libv\n", argv[0]);
		return EXIT_FAILURE;
	}

	return set_kv(dst, DVT_TARGET_LIBV, id, argv[1], argv[2]);
}

static int add_config(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc < 2){
		printf("add_config(target, identifier, argv) invalid number"
			" of arguments (%d vs at least 2).\n", argc);
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
	}

	id.cid = arcan_db_configid(dst, arcan_db_targetid(
		dst, argv[0], NULL), argv[1]);

	return set_kv(dst, DVT_CONFIG, id, argv[2], argv[3]);
}

static int add_config_env(struct arcan_dbh* dst, int argc, char** argv)
{
	union arcan_dbtrans_id id;
	if (argc != 4){
		printf("add_config_env(target, config, key, value) invalid number"
			"of arguments (%d vs 4).\n", argc);
		return EXIT_FAILURE;
	}

	id.cid = arcan_db_configid(dst, arcan_db_targetid(
		dst, argv[0], NULL), argv[1]);

	return set_kv(dst, DVT_CONFIG_ENV, id, argv[2], argv[3]);
}

static int dump_config(struct arcan_dbh* dst, int argc, char** argv)
{
	printf("stub\n");
	return EXIT_SUCCESS;
}

static int dump_exec(struct arcan_dbh* dst, int argc, char** argv)
{
	struct arcan_dbres env = {0};
	struct arcan_dbres outargv = {0};

	if (argc <= 0 || argc > 2){
		printf("dump_exec(target, [config]) invalid number"
			" of arguments (%d vs (1,2)).\n", argc);
		return EXIT_FAILURE;
	}

	arcan_configid cfgid = arcan_db_configid(dst, arcan_db_targetid(
		dst, argv[0], NULL), argc == 1 ? "default" : argv[1]);

	char* execstr = arcan_db_targetexec(dst, cfgid, &outargv, &env);
	if (!execstr){
		printf("couldn't generate execution string\n");
		return EXIT_FAILURE;
	}

	if (outargv.strarr){
		printf("ARGV:\n");
		char** curr = outargv.strarr;
		while(*curr)
			printf("\t%s\n", *curr++);
	}
	else
		printf("ARGV: empty\n");

	assert(env.kind == 0);
	if (env.strarr){
		printf("ENV:\n");
		char** curr = env.strarr;
		while(*curr)
			printf("\t%s\n", *curr++);
	}
	else
		printf("ENV: empty\n");

	return EXIT_SUCCESS;
}

static int dump_targets(struct arcan_dbh* dst, int argc, char** argv)
{
	struct arcan_dbres res = arcan_db_targets(dst);
	assert(res.kind == 0);
	if (!res.strarr){
		printf("dump_targets(), no valid list returned.\n");
		return EXIT_FAILURE;
	}

	char** curr = res.strarr;
	while(*curr)
		printf("%s\n", *curr++);

	return EXIT_SUCCESS;
}

static int dump_target(struct arcan_dbh* dst, int argc, char** argv)
{
	if (argc != 1){
		printf("dump_target(), missing target name argument\n");
		return EXIT_FAILURE;
	}

	arcan_targetid tid = arcan_db_targetid(dst, argv[0], NULL);

	struct arcan_dbres res = arcan_db_configs(dst, tid);
	assert(res.kind == 0);

	if (!res.strarr){
		printf("dump_targets(), no valid list returned.\n");
		return EXIT_FAILURE;
	}

	char** curr = res.strarr;
	while(*curr)
		printf("%s\n", *curr++);

	return EXIT_SUCCESS;
}

static int dump_appl(struct arcan_dbh* dst, int argc, char** argv)
{
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
		.key = "add_target_env",
		.fun = add_target_env
	},

	{
		.key = "dump_exec",
		.fun = dump_exec
	}
};

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

	for (size_t i=0; i < sizeof(dispatch) / sizeof(dispatch[0]); i++)
		if (strcmp(dispatch[i].key, argv[2]) == 0){
			int rc = dispatch[i].fun(dbhandle, argc-3, &argv[3]);
			arcan_db_close(&dbhandle);
			return rc;
		}

	usage();
	return EXIT_FAILURE;
}
