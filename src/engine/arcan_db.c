/*
 * Copyright 2014-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <sqlite3.h>
#include <assert.h>
#include <string.h>
#include <inttypes.h>

#include <sys/types.h>
#include <unistd.h>

#include "arcan_math.h"
#include "arcan_general.h"
#include "arcan_db.h"

#ifdef ARCAN_DB_STANDALONE
static const char* ARCAN_TBL = "arcan";
#else
static const char* ARCAN_TBL =
#ifdef ARCAN_LWA
"arcan_lwa"
#else
 "arcan"
#endif
;
#endif

static bool db_init = false;

#define DB_VERSION_NUM "4"

#define DDL_TARGET "CREATE TABLE target ("\
	"tgtid INTEGER PRIMARY KEY,"\
	"tag STRING NOT NULL,"\
	"name STRING UNIQUE NOT NULL,"\
	"executable TEXT NOT NULL,"\
	"user_id STRING DEFAULT NULL,"\
	"user_group STRING DEFAULT NULL,"\
	"bfmt INTEGER NOT NULL"\
	")"

#define DDL_TGT_ARGV "CREATE TABLE target_argv ("\
	"argnum INTEGER PRIMARY KEY,"\
	"arg STRING NOT NULL,"\
	"target INTEGER NOT NULL,"\
	"FOREIGN KEY (target) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_CONFIG "CREATE TABLE config ("\
	"cfgid INTEGER PRIMARY KEY,"\
	"name STRING NOT NULL,"\
	"passed_counter INTEGER,"\
	"failed_counter INTEGER,"\
	"target INTEGER NOT NULL,"\
	"UNIQUE (name, target),"\
	"FOREIGN KEY (target) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_CFG_ARGV "CREATE TABLE config_argv ("\
	"argnum INTEGER PRIMARY KEY,"\
	"arg STRING NOT NULL,"\
	"config INTEGER NOT NULL,"\
	"FOREIGN KEY (config) REFERENCES config(cfgid) ON DELETE CASCADE )"

#define DDL_TGT_KV "CREATE TABLE target_kv ("\
	"key STRING NOT NULL,"\
	"val STRING NOT NULL,"\
	"target INT NOT NULL,"\
	"UNIQUE (key, target), "\
	"FOREIGN KEY (target) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_CFG_KV "CREATE TABLE config_kv ("\
	"key STRING NOT NULL,"\
	"val STRING NOT NULL,"\
	"config INT NOT NULL,"\
	"UNIQUE (key, config), "\
	"FOREIGN KEY (config) REFERENCES config(cfgid) ON DELETE CASCADE )"

#define DDL_TGT_ENV "CREATE TABLE target_env ("\
	"key STRING NOT NULL,"\
	"val STRING NOT NULL,"\
	"target INT NOT NULL,"\
	"UNIQUE (key, target), "\
	"FOREIGN KEY (target) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_CFG_ENV "CREATE TABLE config_env ("\
	"key STRING NOT NULL,"\
	"val STRING NOT NULL,"\
	"config INT NOT NULL,"\
	"UNIQUE (key, config),"\
	"FOREIGN KEY (config) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_TGT_LIBS "CREATE TABLE target_libs ("\
	"libnum INTEGER PRIMARY KEY,"\
	"libname STRING NOT NULL,"\
	"libnote STRING NOT NULL,"\
	"target INT NOT NULL,"\
	"UNIQUE (libname, target),"\
	"FOREIGN KEY (target) REFERENCES target(tgtid) ON DELETE CASCADE )"

static const char* ddls[] = {
	DDL_TARGET,   DDL_CONFIG,
	DDL_TGT_ARGV, DDL_CFG_ARGV,
	DDL_TGT_KV,   DDL_CFG_KV,
	DDL_TGT_ENV,  DDL_CFG_ENV,
	DDL_TGT_LIBS
};

#define DI_INSARG_TARGET "INSERT INTO target_argv(target, arg) VALUES(?, ?);"
#define DI_INSARG_CONFIG "INSERT INTO config_argv(config, arg) VALUES(?, ?);"

#define DI_DROPKV_TARGET "DELETE FROM target_kv WHERE val=\"\";"

#define DI_INSKV_TARGET "INSERT OR REPLACE INTO "\
	"target_kv(key, val, target) VALUES(?, ?, ?);"

#define DI_INSKV_CONFIG "INSERT OR REPLACE INTO "\
	"config_kv(key, val, config) VALUES(?, ?, ?);"

#define DI_DROPKV_CONFIG "DELETE FROM config_kv WHERE val=\"\";"

#define DI_INSKV_CONFIG_ENV "INSERT OR REPLACE INTO "\
	"config_env(key, val, config) VALUES(?, ?, ?);"

#define DI_INSKV_TARGET_ENV "INSERT OR REPLACE INTO "\
	"target_env(key, val, target) VALUES(?, ?, ?);"

#define DI_INSKV_TARGET_LIBV "INSERT OR REPLACE INTO "\
	"target_libs(libname, libnote, target) VALUES(?, ?, ?);"

struct arcan_dbh {
	sqlite3* dbh;

/* cached appl name used for the DBHandle, although
 * some special functions may use a different one, none outside _db.c should */
	char* applname;
	char* akv_update;
	char* akv_get;
	char* akv_clean;

	size_t akv_upd_sz;
	size_t akv_get_sz;
	size_t akv_clean_sz;

	enum DB_KVTARGET ttype;
	union arcan_dbtrans_id trid;
	bool trclean;
	sqlite3_stmt* transaction;
};

static void setup_ddl(struct arcan_dbh* dbh);

static struct arcan_dbh* shared_handle;
struct arcan_dbh* arcan_db_get_shared(const char** dappl)
{
	if (dappl)
		*dappl = ARCAN_TBL;
	return shared_handle;
}

void arcan_db_set_shared(struct arcan_dbh* new)
{
	shared_handle = new;
}

/*
 * any query that just returns a list of strings,
 * pack into a dbres (or append to an existing one)
 */
static struct arcan_strarr db_string_query(struct arcan_dbh* dbh,
	sqlite3_stmt* stmt, struct arcan_strarr* opt, off_t ofs)
{
	struct arcan_strarr res = {.data = NULL};

	if (!opt) {
		res.data = arcan_alloc_mem(sizeof(char**) * 8,
			ARCAN_MEM_STRINGBUF, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		res.limit = 8;
		res.count = ofs;
	}
	else
		res = *opt;

/* we stop one step short of full capacity before
 * resizing to have both a valid count and a NULL terminated array */
	while (sqlite3_step(stmt) == SQLITE_ROW){
		if (res.count+1 >= res.limit)
			arcan_mem_growarr(&res);

		const char* arg = (const char*) sqlite3_column_text(stmt, 0);
		res.data[res.count++] = (arg ? strdup(arg) : NULL);
	}

	sqlite3_finalize(stmt);
	return res;
}

/*
 * any query where we're just interested in an integer value
 */
static int db_num_query(struct arcan_dbh* dbh, const char* qry, bool* status)
{
	sqlite3_stmt* stmt = NULL;
	if (status) *status = false;
	int count = -1;

	int code = sqlite3_prepare_v2(dbh->dbh, qry, strlen(qry), &stmt, NULL);
	if (SQLITE_OK == code){
		while (sqlite3_step(stmt) == SQLITE_ROW){
			count = sqlite3_column_int(stmt, 0);
			if (status) *status = true;
		}

		sqlite3_finalize(stmt);
	}
	else
		count = -1;

	return count;
}

/*
 * query that is just silently assumed to work
 */
static inline void db_void_query(struct arcan_dbh* dbh,
	const char* qry, bool suppr_err)
{
	sqlite3_stmt* stmt = NULL;
	if (!qry || !dbh)
		return;

	int rc = sqlite3_prepare_v2(dbh->dbh, qry, strlen(qry), &stmt, NULL);
	if (rc == SQLITE_OK){
		rc = sqlite3_step(stmt);
	}

	if (rc != SQLITE_OK && rc != SQLITE_DONE && !suppr_err){
		arcan_warning("db_void_query(failed) on %s -- reason: %d(%s)\n",
			qry, rc, sqlite3_errmsg(dbh->dbh));
	}

	sqlite3_finalize(stmt);
}

void arcan_db_dropappl(struct arcan_dbh* dbh, const char* appl)
{
	if (!appl || !dbh)
		return;

	size_t len = strlen(appl);
	if (0 == len)
		return;

	const char dropqry[] = "DELETE FROM appl_";
	char dropbuf[sizeof(dropqry) + len + 1];
	snprintf(dropbuf, sizeof(dropbuf), "%s%s;", dropqry, appl);

	db_void_query(dbh, dropbuf, true);

/* special case, reset version fields etc. */
	if (strcmp(appl, ARCAN_TBL) == 0){
		arcan_db_appl_kv(dbh, ARCAN_TBL, "dbversion", DB_VERSION_NUM);
	}
}

static void sqliteexit()
{
	sqlite3_shutdown();
}

/*
 * will be called every time the database is opened,
 * so we expect this to fail silently when the group already exists
 */
static void create_appl_group(struct arcan_dbh* dbh, const char* applname)
{
	const char ddl[] = "CREATE TABLE appl_%s "
		"(key TEXT UNIQUE, val TEXT NOT NULL);";
	const char kv_ddl[] = "INSERT OR REPLACE INTO "
		" appl_%s(key, val) VALUES(?, ?);";
	const char kv_get[] = "SELECT val FROM appl_%s WHERE key = ?;";
	const char kv_drop[] = "DELETE FROM appl_%s WHERE val = \"\";";

	if (dbh->akv_update)
		arcan_mem_free(dbh->akv_update);

	size_t len = applname ? strlen(applname) : 0;
	if (0 == len){
		arcan_warning("create_appl_group(), missing or broken applname\n");
		return;
	}

/* cache key insert into app specific table */
	assert(sizeof(kv_get) < sizeof(kv_ddl));
	size_t ddl_sz = len + sizeof(kv_ddl);
	dbh->akv_update = arcan_alloc_mem(
		ddl_sz, ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);
	dbh->akv_upd_sz = snprintf(dbh->akv_update, ddl_sz, kv_ddl, applname);

/* cache drop empty values from table */
	ddl_sz = len + sizeof(kv_drop);
	dbh->akv_clean = arcan_alloc_mem(
		ddl_sz, ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);
	dbh->akv_clean_sz = snprintf(dbh->akv_clean, ddl_sz, kv_drop, applname);

/* cache key retrieve into app specific table */
	ddl_sz = strlen(applname) + sizeof(kv_get);
	dbh->akv_get = arcan_alloc_mem(
		ddl_sz, ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);
	dbh->akv_get_sz = snprintf(dbh->akv_get, ddl_sz, kv_get, applname);

/* create the actual table */
	char wbuf[ sizeof(ddl) + strlen(applname) ];
	snprintf(wbuf, sizeof(wbuf)/sizeof(wbuf[0]), ddl, applname);

	db_void_query(dbh, wbuf, true);
}

#ifdef ARCAN_DB_STANDALONE
bool arcan_db_droptarget(struct arcan_dbh* dbh, arcan_targetid id)
{
/* should suffice from ON DELETE CASCADE relationship */
	static const char qry[]  = "DELETE FROM target WHERE tgtid = ?;";

	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, qry, sizeof(qry)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, id);
	sqlite3_step(stmt);
	sqlite3_finalize(stmt);

	return true;
}

bool arcan_db_dropconfig(struct arcan_dbh* dbh, arcan_configid id)
{
	static const char qry[] = "DELETE FROM config WHERE cfgid = ?;";

	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, qry, sizeof(qry)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, id);
	sqlite3_step(stmt);
	sqlite3_finalize(stmt);

	return true;
}

arcan_targetid arcan_db_addtarget(struct arcan_dbh* dbh,
	const char* identifier, const char* group, const char* exec,
	const char* argv[], size_t sz, enum DB_BFORMAT bfmt)
{
	static const char ddl[] = "INSERT OR REPLACE INTO "
		"	target(tgtid, name, tag, executable, bfmt) VALUES "
		"((select tgtid FROM target where name = ?), ?, ?, ?, ?)";

	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, ddl, sizeof(ddl)-1, &stmt, NULL);

	sqlite3_bind_text(stmt, 1, identifier, -1, SQLITE_STATIC);
	sqlite3_bind_text(stmt, 2, identifier, -1, SQLITE_STATIC);
	sqlite3_bind_text(stmt, 3, group, -1, SQLITE_STATIC);
	sqlite3_bind_text(stmt, 4, exec, -1, SQLITE_STATIC);
	sqlite3_bind_int(stmt, 5, bfmt);

	sqlite3_step(stmt);
	sqlite3_finalize(stmt);

	arcan_targetid newid = sqlite3_last_insert_rowid(dbh->dbh);

/* delete previous arguments */
	static const char drop_argv[] = "DELETE FROM target_argv WHERE target = ?;";
	sqlite3_prepare_v2(dbh->dbh, drop_argv, sizeof(drop_argv) - 1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, newid);
	sqlite3_step(stmt);
	sqlite3_finalize(stmt);

/* add new ones */
	if (0 == sz)
		return newid;

	static const char add_argv[] = DI_INSARG_TARGET;
	for (size_t i = 0; i < sz; i++){
		sqlite3_prepare_v2(dbh->dbh, add_argv, sizeof(add_argv) - 1, &stmt, NULL);
		sqlite3_bind_int(stmt, 1, newid);
		sqlite3_bind_text(stmt, 2, argv[i], -1, SQLITE_STATIC);
		sqlite3_step(stmt);
		sqlite3_finalize(stmt);
	}

	return newid;
}

arcan_configid arcan_db_addconfig(struct arcan_dbh* dbh,
	arcan_targetid id,	const char* identifier, const char* argv[], size_t sz)
{
	if (!arcan_db_verifytarget(dbh, id))
		return BAD_CONFIG;

	static const char ddl[] = "INSERT OR REPLACE INTO config(cfgid, name, "
		"passed_counter, failed_counter, target) VALUES "
		"(NULL, ?, ?, ?, ?)";

	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, ddl, sizeof(ddl)-1, &stmt, NULL);

	sqlite3_bind_text(stmt, 1, identifier, -1, SQLITE_STATIC);
	sqlite3_bind_int(stmt, 2, 0);
	sqlite3_bind_int(stmt, 3, 0);
	sqlite3_bind_int(stmt, 4, id);

	sqlite3_step(stmt);
	sqlite3_finalize(stmt);

	arcan_configid newid = sqlite3_last_insert_rowid(dbh->dbh);

/* delete previous arguments */
	static const char drop_argv[] = "DELETE FROM config_argv WHERE config = ?;";
	sqlite3_prepare_v2(dbh->dbh, drop_argv, sizeof(drop_argv) - 1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, newid);
	sqlite3_step(stmt);
	sqlite3_finalize(stmt);

/* add new ones */
	if (0 == sz)
		return newid;

	static const char add_argv[] = DI_INSARG_CONFIG;
	for (size_t i = 0; i < sz; i++){
		sqlite3_prepare_v2(dbh->dbh, add_argv, sizeof(add_argv) - 1, &stmt, NULL);
		sqlite3_bind_int(stmt, 1, newid);
		sqlite3_bind_text(stmt, 2, argv[i], -1, SQLITE_STATIC);
		sqlite3_step(stmt);
		sqlite3_finalize(stmt);
	}

	return newid;
}

#endif

bool arcan_db_verifytarget(struct arcan_dbh* dbh, arcan_targetid id)
{
	static const char ddl[] = "SELECT COUNT(*) FROM target WHERE tgtid = ?;";

	sqlite3_stmt* stmt = NULL;
	if (SQLITE_OK == sqlite3_prepare_v2(
		dbh->dbh, ddl, sizeof(ddl)-1, &stmt, NULL)){
		sqlite3_bind_int(stmt, 1, id);
		sqlite3_step(stmt);
		return 1 == sqlite3_column_int(stmt, 0);
	}

	return false;
}

arcan_targetid arcan_db_targetid(struct arcan_dbh* dbh,
	const char* identifier, arcan_configid* defid)
{
	arcan_targetid rid = BAD_TARGET;
	static const char dql[] = "SELECT tgtid FROM target WHERE name = ?;";
	sqlite3_stmt* stmt;

	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, identifier, -1, SQLITE_STATIC);

	if (SQLITE_ROW == sqlite3_step(stmt))
		rid = sqlite3_column_int64(stmt, 0);

	sqlite3_finalize(stmt);
	return rid;
}

struct arcan_strarr arcan_db_list_appl(struct arcan_dbh* dbh)
{
	static const char dql[] = "SELECT name FROM sqlite_master WHERE "
		"type='table' and NAME like \"appl_%\"";
	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);

	return db_string_query(dbh, stmt, NULL, 0);
}

struct arcan_strarr arcan_db_config_argv(struct arcan_dbh* dbh,arcan_configid id)
{
	static const char dql[] = "SELECT arg FROM config_argv WHERE "
		"config = ? ORDER BY argnum ASC;";
	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, id);

	return db_string_query(dbh, stmt, NULL, 0);
}

struct arcan_strarr arcan_db_target_argv(struct arcan_dbh* dbh,arcan_targetid id)
{
	static const char dql[] = "SELECT arg FROM target_argv WHERE "
		"target = ? ORDER BY argnum ASC;";
	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, id);

	return db_string_query(dbh, stmt, NULL, 0);
}

arcan_targetid arcan_db_cfgtarget(struct arcan_dbh* dbh, arcan_configid cfg)
{
	static const char dql[] = "SELECT target FROM config WHERE cfgid = ?;";
	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, cfg);
	arcan_targetid tid = BAD_TARGET;

	if (SQLITE_ROW == sqlite3_step(stmt))
		tid = sqlite3_column_int64(stmt, 0);

	sqlite3_finalize(stmt);
	return tid;
}

arcan_configid arcan_db_configid(struct arcan_dbh* dbh,
	arcan_targetid target, const char* config)
{
	static const char dql[] = "SELECT cfgid FROM config"
		"	WHERE name = ? AND target = ?;";
	sqlite3_stmt* stmt;
	arcan_configid cid = BAD_CONFIG;

	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, config, strlen(config), SQLITE_STATIC);
	sqlite3_bind_int(stmt, 2, target);

	if (SQLITE_ROW == sqlite3_step(stmt))
		cid = sqlite3_column_int64(stmt, 0);

	sqlite3_finalize(stmt);
	return cid;
}

struct arcan_strarr arcan_db_target_tags(struct arcan_dbh* dbh)
{
	sqlite3_stmt* stmt;
	static const char dql[] = "SELECT DISTINCT tag FROM target;";
	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	return db_string_query(dbh, stmt, NULL, 0);
}

struct arcan_strarr arcan_db_targets(struct arcan_dbh* dbh, const char* tag)
{
	sqlite3_stmt* stmt;
	if (!tag){
		static const char dql[] = "SELECT name FROM target;";
		sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	}
	else {
		static const char dql[] = "SELECT name FROM target WHERE tag=?;";
		sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
		sqlite3_bind_text(stmt, 1, tag, strlen(tag), SQLITE_STATIC);
	}
	return db_string_query(dbh, stmt, NULL, 0);
}

char* arcan_db_targettag(struct arcan_dbh* dbh, arcan_targetid tid)
{
	static const char dql[] = "SELECT tag FROM target WHERE tgtid = ?;";
	char* resstr = NULL;
	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);

	sqlite3_bind_int(stmt, 1, tid);
	if (sqlite3_step(stmt) == SQLITE_ROW){
		resstr = (char*) sqlite3_column_text(stmt, 0);
	}

	if (resstr)
		resstr = strdup(resstr);

	sqlite3_finalize(stmt);
	return resstr;
}

char* arcan_db_targetexec(struct arcan_dbh* dbh,
	arcan_configid configid, enum DB_BFORMAT* bfmt,
	struct arcan_strarr* argv, struct arcan_strarr* env,
	struct arcan_strarr* libs)
{
	arcan_targetid tid = arcan_db_cfgtarget(dbh, configid);
	if (tid == BAD_TARGET)
		return NULL;

	sqlite3_stmt* stmt;
	static const char dql[] = "SELECT executable, bfmt "
		"FROM target WHERE tgtid = ?;";

	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql) - 1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tid);

	char* execstr = NULL;
	if (sqlite3_step(stmt) == SQLITE_ROW){
		execstr = (char*) sqlite3_column_text(stmt, 0);
		*bfmt = (int) sqlite3_column_int64(stmt, 1);
	}

	if (execstr)
		execstr = strdup(execstr);

	sqlite3_finalize(stmt);

	static const char dql_tgt_argv[] = "SELECT arg FROM target_argv WHERE "
		"target = ? ORDER BY argnum ASC;";
	sqlite3_prepare_v2(dbh->dbh, dql_tgt_argv,
		sizeof(dql_tgt_argv)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tid);

	*argv = db_string_query(dbh, stmt, NULL, 1);
	argv->data[0] = strdup(execstr ? execstr : "");

	static const char dql_cfg_argv[] = "SELECT arg FROM config_argv WHERE "
		"config = ? ORDER BY argnum ASC;";
	sqlite3_prepare_v2(dbh->dbh, dql_cfg_argv,
		sizeof(dql_cfg_argv)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, configid);
	*argv = db_string_query(dbh, stmt, argv, 0);

	static const char dql_tgt_env[] = "SELECT key || '=' || val "
		"FROM target_env WHERE target = ?";
	sqlite3_prepare_v2(dbh->dbh, dql_tgt_env,
		sizeof(dql_tgt_env)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tid);
	*env = db_string_query(dbh, stmt, NULL, 0);

	static const char dql_cfg_env[] = "SELECT key || '=' || val "
		"FROM config_env WHERE config = ?";
	sqlite3_prepare_v2(dbh->dbh, dql_cfg_env,
		sizeof(dql_cfg_env)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tid);
	db_string_query(dbh, stmt, env, 0);

	static const char dql_tgt_lib[] = "SELECT libname FROM target_libs WHERE "
		"target = ?;";
	sqlite3_prepare_v2(dbh->dbh, dql_tgt_lib,
		sizeof(dql_tgt_lib)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tid);
	*libs = db_string_query(dbh, stmt, NULL, 0);

	return execstr;
}

void arcan_db_launch_status(struct arcan_dbh* dbh, arcan_configid cid, bool s)
{
	static const char dql_ok[] = "UPDATE passed_counter SET "
		"passed_counter = passed_counter + 1 WHERE config = ?;";

	static const char dql_fail[] = "UPDATE failed_counter SET "
		"failed_counter = failed_counter + 1 WHERE config = ?;";

	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh,
		(s ? dql_ok : dql_fail), sizeof(dql_ok)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, cid);
	sqlite3_step(stmt);
	sqlite3_finalize(stmt);
}

struct arcan_strarr arcan_db_configs(struct arcan_dbh* dbh, arcan_targetid tid)
{
	static const char dql[] = "SELECT name FROM config WHERE target = ?;";
	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tid);

	return db_string_query(dbh, stmt, NULL, 0);
}

char* arcan_db_execname(struct arcan_dbh* dbh, arcan_targetid tid)
{
	static const char dql[] = "SELECT executable FROM target WHERE tgtid = ?;";
	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tid);

	char* res = NULL;
	if (sqlite3_step(stmt) == SQLITE_ROW) {
		const unsigned char* arg = sqlite3_column_text(stmt, 0);
		res = arg ? strdup((char*)arg) : NULL;
	}

	sqlite3_finalize(stmt);
	return res;
}

void arcan_db_begin_transaction(struct arcan_dbh* dbh,
	enum DB_KVTARGET kvt, union arcan_dbtrans_id id)
{
	if (dbh->transaction)
		arcan_fatal("arcan_db_begin_transaction()"
			"	called during a pending transaction\n");

	sqlite3_exec(dbh->dbh, "BEGIN;", NULL, NULL, NULL);
	int code = SQLITE_OK;

	switch (kvt){
	case DVT_APPL:
		code = sqlite3_prepare_v2(dbh->dbh, dbh->akv_update,
			dbh->akv_upd_sz, &dbh->transaction, NULL);
	break;

	case DVT_TARGET:
		code = sqlite3_prepare_v2(dbh->dbh, DI_INSKV_TARGET,
			strlen(DI_INSKV_TARGET)+1, &dbh->transaction, NULL);
	break;

	case DVT_CONFIG:
		code = sqlite3_prepare_v2(dbh->dbh, DI_INSKV_CONFIG,
			strlen(DI_INSKV_CONFIG)+1, &dbh->transaction, NULL);
	break;

	case DVT_CONFIG_ENV:
		code = sqlite3_prepare_v2(dbh->dbh, DI_INSKV_CONFIG_ENV,
			strlen(DI_INSKV_TARGET_ENV)+1, &dbh->transaction, NULL);
	break;

	case DVT_TARGET_ENV:
		code = sqlite3_prepare_v2(dbh->dbh, DI_INSKV_TARGET_ENV,
			strlen(DI_INSKV_TARGET_ENV)+1, &dbh->transaction, NULL);
	break;

	case DVT_TARGET_LIBV:
		code = sqlite3_prepare_v2(dbh->dbh, DI_INSKV_TARGET_LIBV,
			strlen(DI_INSKV_TARGET_LIBV)+1, &dbh->transaction, NULL);
	break;
	case DVT_ENDM:
	break;
	}

	if (code != SQLITE_OK){
		arcan_warning("arcan_db_begin_transaction(), failed: %s\n",
			sqlite3_errmsg(dbh->dbh));
	}

	dbh->trid = id;
	dbh->ttype = kvt;
}

struct arcan_strarr arcan_db_getkeys(struct arcan_dbh* dbh,
	enum DB_KVTARGET tgt, union arcan_dbtrans_id id)
{
#define GET_KV_TGT "SELECT key || '=' || val FROM target_kv WHERE target = ?;"
	static const char* const queries[] = {
		GET_KV_TGT,
		"SELECT key || '=' || val FROM config_kv WHERE config = ?"
	};

	const char* qry = NULL;
	if (tgt >= DVT_TARGET && tgt < DVT_CONFIG)
		qry = queries[0];
	else
		qry = queries[1];

	sqlite3_stmt * stmt;
	sqlite3_prepare_v2(dbh->dbh, qry, sizeof(GET_KV_TGT)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tgt>=DVT_TARGET && tgt<DVT_CONFIG ? id.tid:id.cid);

#undef GET_KV_TGT
	return db_string_query(dbh, stmt, NULL, 0);
}

struct arcan_strarr arcan_db_applkeys(struct arcan_dbh* dbh,
	const char* applname, const char* pattern)
{
#define MATCH_APPL "SELECT key || '=' || val FROM appl_%s WHERE key LIKE ?;"

	size_t mk_sz = sizeof(MATCH_APPL) + strlen(applname);
	char mk_buf[ mk_sz ];
	ssize_t nw = snprintf(mk_buf, mk_sz, MATCH_APPL, applname);

	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, mk_buf, mk_sz-1, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT);

	return db_string_query(dbh, stmt, NULL, 0);
#undef MATCH_KEY_APPL
}

struct arcan_strarr arcan_db_matchkey(struct arcan_dbh* dbh,
	enum DB_KVTARGET tgt, const char* pattern)
{
#define MATCH_KEY_TGT "SELECT tgtid ||':'|| value"\
	" FROM target_kv WHERE key LIKE ?;"

	static const char* const queries[] = {
		MATCH_KEY_TGT,
		"SELECT cfgid || ':' || value FROM config_kv WHERE key LIKE ?;"
	};

	const char* qry = NULL;
	if (tgt >= DVT_TARGET && tgt < DVT_CONFIG)
		qry = queries[0];
	else
		qry = queries[1];

	sqlite3_stmt* stmt;
	sqlite3_prepare_v2(dbh->dbh, qry, sizeof(MATCH_KEY_TGT)-1, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, pattern, -1, SQLITE_TRANSIENT);

	return db_string_query(dbh, stmt, NULL, 0);
}

char* arcan_db_getvalue(struct arcan_dbh* dbh,
	enum DB_KVTARGET tgt, int64_t id, const char* key)
{
	char* res = NULL;
/* must match enum */
	assert(DVT_ENDM == 5);

	static const char* queries[] = {
		"SELECT val FROM target_kv WHERE key = ? AND tgtid = ? LIMIT 1;",
		"SELECT val FROM config_kv WHERE key = ? AND cfgid = ? LIMIT 1;"
	};

	const char* qry = NULL;
	if (tgt >= DVT_TARGET && tgt < DVT_CONFIG)
		qry = queries[0];
	else
		qry = queries[1];

/* assume they all are the same length */
	static size_t qry_sz;
	if (qry_sz == 0)
		qry_sz = strlen(queries[1]);

	sqlite3_stmt* stmt = NULL;

	if (tgt == DVT_APPL){
		sqlite3_prepare_v2(dbh->dbh, dbh->akv_get, dbh->akv_get_sz, &stmt, NULL);
	}
	else {
		sqlite3_prepare_v2(dbh->dbh, qry, qry_sz, &stmt, NULL);
		sqlite3_bind_text(stmt, 1, key, -1, SQLITE_STATIC);
		sqlite3_bind_int(stmt, 2, id);
	}

	if (SQLITE_ROW == sqlite3_step(stmt)){
		const char* row = (const char*) sqlite3_column_text(stmt, 0);
		if (row)
			res = strdup(row);
	}

	sqlite3_finalize(stmt);
	return res;
}

void arcan_db_add_kvpair(
	struct arcan_dbh* dbh, const char* key, const char* val)
{
	if (!dbh->transaction)
		arcan_fatal("arcan_db_add_kvpair() "
			"called without any open transaction.");

	if (!val){
		dbh->trclean = true;
		return;
	}

	if (val[0] == 0)
		dbh->trclean = true;

	sqlite3_bind_text(dbh->transaction, 1, key, -1, SQLITE_TRANSIENT);
	sqlite3_bind_text(dbh->transaction, 2, val, -1, SQLITE_TRANSIENT);

	switch (dbh->ttype){
	case DVT_APPL:
	case DVT_ENDM:
	break;

	case DVT_TARGET:
	case DVT_TARGET_ENV:
	case DVT_TARGET_LIBV:
		sqlite3_bind_int(dbh->transaction, 3, dbh->trid.tid);
	break;

	case DVT_CONFIG:
	case DVT_CONFIG_ENV:
		sqlite3_bind_int(dbh->transaction, 3, dbh->trid.cid);
	break;
	}

	int rc = sqlite3_step(dbh->transaction);
	if (SQLITE_DONE != rc)
		arcan_warning("arcan_db_addkvpair(%s=%s), %d failed: %s\n",
			key, val, rc, sqlite3_errmsg(dbh->dbh));
	else {
		sqlite3_clear_bindings(dbh->transaction);
		sqlite3_reset(dbh->transaction);
	}
}

void arcan_db_end_transaction(struct arcan_dbh* dbh)
{
	if (!dbh->transaction)
		arcan_fatal("arcan_db_end_transaction() "
			"called without any open transaction.");

	sqlite3_finalize(dbh->transaction);

	if (dbh->trclean){
		switch (dbh->ttype){
		case DVT_APPL:
			sqlite3_exec(dbh->dbh, dbh->akv_clean, NULL, NULL, NULL);
		break;
		case DVT_TARGET:
			sqlite3_exec(dbh->dbh, DI_DROPKV_TARGET, NULL, NULL, NULL);
		break;
		case DVT_CONFIG:
			sqlite3_exec(dbh->dbh, DI_DROPKV_CONFIG, NULL, NULL, NULL);
		break;
		default:
		break;
		}
		dbh->trclean = false;
	}

	if (SQLITE_OK != sqlite3_exec(dbh->dbh, "COMMIT;", NULL, NULL, NULL)){
		arcan_warning("arcan_db_end_transaction(), failed: %s\n",
			sqlite3_errmsg(dbh->dbh));
	}

	dbh->transaction = NULL;
}

bool arcan_db_appl_kv(struct arcan_dbh* dbh,
	const char* applname, const char* key, const char* value)
{
	bool rv = false;

	if (dbh->transaction)
		arcan_fatal("arcan_db_appl_kv() called during a pending transaction\n");

	if (!applname || !dbh || !key)
		return rv;

	const char ddl_insert[] = "INSERT OR REPLACE "
		"INTO appl_%s(key, val) VALUES(?, ?);";
	const char k_drop[] = "DELETE FROM appl_%s WHERE key=?;";

	size_t upd_sz = 0;
	const char* dqry = ddl_insert;

	if (!value){
		upd_sz = sizeof(k_drop) + strlen(applname);
		dqry = k_drop;
	}
	else
		upd_sz = sizeof(ddl_insert) + strlen(applname);

	char upd_buf[ upd_sz ];
	ssize_t nw = snprintf(upd_buf, upd_sz, dqry, applname);

	sqlite3_stmt* stmt = NULL;
	sqlite3_prepare_v2(dbh->dbh, upd_buf, nw, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, key,   -1, SQLITE_TRANSIENT);
	sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT);

	rv = sqlite3_step(stmt) == SQLITE_DONE;
	sqlite3_finalize(stmt);

	return rv;
}

char* arcan_db_appl_val(struct arcan_dbh* dbh,
	const char* const applname, const char* const key)
{
	if (!dbh || !key)
		return NULL;

	const char qry[] = "SELECT val FROM appl_%s WHERE key = ?;";

	size_t wbuf_sz = strlen(applname) + sizeof(qry);
	char wbuf[ wbuf_sz ];
	memset(wbuf, '\0', wbuf_sz);
	snprintf(wbuf, wbuf_sz, qry, applname);

	sqlite3_stmt* stmt = NULL;
	sqlite3_prepare_v2(dbh->dbh, wbuf, wbuf_sz, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, (char*) key, -1, SQLITE_TRANSIENT);

	char* rv = NULL;
	int rc = sqlite3_step(stmt);

	if (rc == SQLITE_ROW){
		const unsigned char* rowt;

		if ( (rowt = sqlite3_column_text(stmt, 0)) != NULL)
			rv = strdup((const char*) rowt);
	}

	sqlite3_finalize(stmt);

	return rv;
}

static void setup_ddl(struct arcan_dbh* dbh)
{
	create_appl_group(dbh, "arcan");
	create_appl_group(dbh, "arcan_lwa");
	arcan_db_appl_kv(dbh, "arcan", "dbversion", DB_VERSION_NUM);
	arcan_db_appl_kv(dbh, "arcan_lwa", "dbversion", DB_VERSION_NUM);

	for (size_t i = 0; i < sizeof(ddls)/sizeof(ddls[0]); i++)
		db_void_query(dbh, ddls[i], false);
}

/* to detect old databases and upgrade if possible */
static bool dbh_integrity_check(struct arcan_dbh* dbh){
	int tablecount = db_num_query(dbh, "SELECT Count(*) "
		"FROM sqlite_master WHERE type='table';", NULL);

/* empty database */
	if (tablecount <= 0){
		arcan_warning("Empty database encountered, running default DDL queries.\n");
		setup_ddl(dbh);

		return true;
	}

/* check for descriptor table, missing?
 * that means we have a first- version database, push upgrade */
	char* valstr = arcan_db_appl_val(dbh, ARCAN_TBL, "dbversion");
	unsigned vnum = valstr ? strtoul(valstr, NULL, 10) : 0;

	switch (vnum){
		case 0:
		case 1:
		case 2:
			arcan_warning("DB version (< 3) unsupported, rebuild necessary\n");
			return false;
		case 3:
			arcan_warning("DB version (< 4) found, rebuild suggested\n");
	}

	arcan_mem_free(valstr);
	return true;
}

void arcan_db_close(struct arcan_dbh** ctx)
{
	if (!ctx)
		return;

	sqlite3_close((*ctx)->dbh);
	arcan_mem_free((*ctx)->applname);
	arcan_mem_free((*ctx)->akv_update);
	arcan_mem_free((*ctx)->akv_get);
	arcan_mem_free(*ctx);
	*ctx = NULL;
}

struct arcan_dbh* arcan_db_open(const char* fname, const char* applname)
{
	sqlite3* dbh;

	if (!fname)
		return NULL;

	if (!db_init) {
		int rv = sqlite3_initialize();
		db_init = true;

		if (rv != SQLITE_OK)
			return NULL;

		atexit(sqliteexit);
	}

	if (!applname)
		applname = "_default";

	if (sqlite3_open_v2(fname, &dbh,
		SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL) == SQLITE_OK){
		struct arcan_dbh* res = arcan_alloc_mem(
			sizeof(struct arcan_dbh), ARCAN_MEM_EXTSTRUCT,
			ARCAN_MEM_SENSITIVE | ARCAN_MEM_BZERO, ARCAN_MEMALIGN_PAGE
		);

		res->dbh = dbh;
		assert(dbh);

		if ( !dbh_integrity_check(res) ){
			sqlite3_close(dbh);
			arcan_mem_free(res);
			return NULL;
		}

		res->applname = strdup(applname);
		create_appl_group(res, res->applname);

		db_void_query(res, "PRAGMA foreign_keys=ON;", false);
		db_void_query(res, "PRAGMA synchronous=OFF;", false);

		return res;
	}
	else
		;

	return NULL;
}
