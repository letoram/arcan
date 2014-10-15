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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
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

#ifndef REALLOC_STEP
#define REALLOC_STEP 32
#endif

static bool db_init = false;

#define DDL_TARGET "CREATE TABLE target ("\
	"tgtid INTEGER PRIMARY KEY,"\
	"name STRING UNIQUE NOT NULL,"\
	"executable TEXT NOT NULL,"\
	"uid INTEGER DEFAULT -1,"\
	"gid INTEGER DEFAULT -1,"\
	"bfmt INTEGER NOT NULL"\
	")"

#define DDL_TGT_ARGV "CREATE TABLE target_argv ("\
	"argnum INTEGER PRIMARY KEY,"\
	"arg STRING NOT NULL,"\
	"target INTEGER NOT NULL,"\
	"FOREIGN KEY (target) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_CONFIG "CREATE TABLE config ("\
	"cfgid INTEGER PRIMARY KEY,"\
	"name STRING UNIQUE NOT NULL,"\
	"passed_counter INTEGER,"\
	"failed_counter INTEGER,"\
	"target INTEGER NOT NULL,"\
	"FOREIGN KEY (target) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_CFG_ARGV "CREATE TABLE config_argv ("\
	"argnum INTEGER PRIMARY KEY,"\
	"arg STRING NOT NULL,"\
	"config INTEGER NOT NULL,"\
	"FOREIGN KEY (config) REFERENCES config(cfgid) ON DELETE CASCADE )"

#define DDL_TGT_KV "CREATE TABLE target_kv ("\
	"key STRING UNIQUE NOT NULL,"\
	"val STRING NOT NULL,"\
	"target INT NOT NULL,"\
	"FOREIGN KEY (target) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_CFG_KV "CREATE TABLE config_kv ("\
	"key STRING UNIQUE NOT NULL,"\
	"val STRING NOT NULL,"\
	"config INT NOT NULL,"\
	"FOREIGN KEY (config) REFERENCES config(cfgid) ON DELETE CASCADE )"

#define DDL_TGT_ENV "CREATE TABLE target_env ("\
	"key STRING UNIQUE NOT NULL,"\
	"val STRING NOT NULL,"\
	"target INT NOT NULL,"\
	"FOREIGN KEY (target) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_CFG_ENV "CREATE TABLE config_env ("\
	"key STRING UNIQUE NOT NULL,"\
	"val STRING NOT NULL,"\
	"config INT NOT NULL,"\
	"FOREIGN KEY (config) REFERENCES target(tgtid) ON DELETE CASCADE )"

#define DDL_TGT_LIBS "CREATE TABLE target_libs ("\
	"libname STRING UNIQUE NOT NULL,"\
	"target INT NOT NULL,"\
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

#define DI_INSKV_TARGET "INSERT OR REPLACE INTO "\
	"target_kv(key, val, target) VALUES(?, ?, ?);"

#define DI_INSKV_CONFIG "INSERT OR REPLACE INTO "\
	"config_kv(key, val, config) VALUES(?, ?, ?);"

#define DI_INSKV_CONFIG_ENV "INSERT OR REPLACE INTO "\
	"config_env(key, val, config) VALUES(?, ?, ?);"

#define DI_INSKV_TARGET_ENV "INSERT OR REPLACE INTO "\
	"target_env(key, val, target) VALUES(?, ?, ?);"

#define DI_INSKV_TARGET_LIBV "INSERT OR REPLACE INTO "\
	"target_libs(key, val, target) VALUES(?, ?, ?);"

struct arcan_dbh {
	sqlite3* dbh;

/* cached appl name used for the DBHandle, although
 * some special functions may use a different one, none outside _db.c should */
	char* applname;
	char* akv_update;
	char* akv_get;

	size_t akv_upd_sz;
	size_t akv_get_sz;

	enum DB_KVTARGET ttype;
	union arcan_dbtrans_id trid;
	sqlite3_stmt* transaction;
};

/*
 * any query that just returns a list of strings,
 * pack into a dbres (or append to an existing one)
 */
static struct arcan_dbres db_string_query(struct arcan_dbh* dbh,
	sqlite3_stmt* stmt, struct arcan_dbres* opt)
{
	struct arcan_dbres res = {.kind = 0};

	if (!opt) {
		res.strarr = arcan_alloc_mem(sizeof(char**) * 8,
			ARCAN_MEM_STRINGBUF, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);
		res.limit = 8;
	}
	else
		res = *opt;

	bool added = false;

/* we stop one step short of full capacity before
 * resizing to have both a valid count and a NULL terminated array */
	while (sqlite3_step(stmt) == SQLITE_ROW){
		const char* arg = (const char*) sqlite3_column_text(stmt, 0);
		res.strarr[res.count++] = (arg ? strdup(arg) : NULL);

		if (res.count == res.limit-1){
			char** newbuf = arcan_alloc_mem(
				(res.limit + REALLOC_STEP) * sizeof(char*),
				ARCAN_MEM_STRINGBUF, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL
			);

/* grow by REALLOC_STEP */
			memcpy(newbuf, res.strarr, res.limit * sizeof(char*));
			arcan_mem_free(res.strarr);
			res.strarr = newbuf;
			res.limit += REALLOC_STEP;
		}
	}

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
static inline void db_void_query(struct arcan_dbh* dbh, const char* qry)
{
	sqlite3_stmt* stmt = NULL;
	if (!qry || !dbh)
		return;

	int rc = sqlite3_prepare_v2(dbh->dbh, qry, strlen(qry), &stmt, NULL);
	if (rc == SQLITE_OK){
		rc = sqlite3_step(stmt);
	}

	if (rc != SQLITE_OK && rc != SQLITE_DONE){
/*
 * arcan_warning("db_void_query(failed) on %s -- reason: %d(%s)\n",
 *		qry, rc, sqlite3_errmsg(dbh->dbh));
 */
	}

	sqlite3_finalize(stmt);
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

	if (dbh->akv_update)
		arcan_mem_free(dbh->akv_update);

/* cache key insert into app specific table */
	assert(sizeof(kv_get) < sizeof(kv_ddl));
	size_t ddl_sz = strlen(applname) + sizeof(kv_ddl);
	dbh->akv_update = arcan_alloc_mem(
		ddl_sz, ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);
	dbh->akv_upd_sz = snprintf(dbh->akv_update, ddl_sz, kv_ddl, applname);

/* cache key retrieve into app specific table */
	ddl_sz = strlen(applname) + sizeof(kv_get);
	dbh->akv_get = arcan_alloc_mem(
		ddl_sz, ARCAN_MEM_STRINGBUF, 0, ARCAN_MEMALIGN_NATURAL);
	dbh->akv_get_sz = snprintf(dbh->akv_get, ddl_sz, kv_get, applname);

/* create the actual table */
	char wbuf[ sizeof(ddl) + strlen(applname) ];
	snprintf(wbuf, sizeof(wbuf)/sizeof(wbuf[0]), ddl, applname);

	db_void_query(dbh, wbuf);
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
	const char* identifier, const char* exec,
	const char* argv[], size_t sz, enum DB_BFORMAT bfmt)
{
	static const char ddl[] = "INSERT OR REPLACE INTO "
		"	target(tgtid, name, executable, bfmt) VALUES "
		"((select tgtid FROM target where name = ?), ?, ?, ?)";

	sqlite3_stmt* stmt;
	int rc = sqlite3_prepare_v2(dbh->dbh, ddl, sizeof(ddl)-1, &stmt, NULL);

	sqlite3_bind_text(stmt, 1, identifier, -1, SQLITE_STATIC);
	sqlite3_bind_text(stmt, 2, identifier, -1, SQLITE_STATIC);
	sqlite3_bind_text(stmt, 3, exec, -1, SQLITE_STATIC);
	sqlite3_bind_int(stmt, 4, bfmt);

	rc = sqlite3_step(stmt);
	sqlite3_finalize(stmt);

	arcan_targetid newid = sqlite3_last_insert_rowid(dbh->dbh);

/* delete previous arguments */
	static const char drop_argv[] = "DELETE FROM target_argv WHERE target = ?;";
	rc = sqlite3_prepare_v2(dbh->dbh, drop_argv,
		sizeof(drop_argv) - 1, &stmt, NULL);
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
		"((select cfgid FROM config where name = ?), ?, ?, ?, ?)";

	sqlite3_stmt* stmt;
	int rc = sqlite3_prepare_v2(dbh->dbh, ddl, sizeof(ddl)-1, &stmt, NULL);

	sqlite3_bind_text(stmt, 1, identifier, -1, SQLITE_STATIC);
	sqlite3_bind_text(stmt, 2, identifier, -1, SQLITE_STATIC);
	sqlite3_bind_int(stmt, 3, 0);
	sqlite3_bind_int(stmt, 4, 0);
	sqlite3_bind_int(stmt, 5, id);

	rc = sqlite3_step(stmt);
	sqlite3_finalize(stmt);

	arcan_configid newid = sqlite3_last_insert_rowid(dbh->dbh);

/* delete previous arguments */
	static const char drop_argv[] = "DELETE FROM config_argv WHERE config = ?;";
	rc = sqlite3_prepare_v2(dbh->dbh, drop_argv,
		sizeof(drop_argv) - 1, &stmt, NULL);
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

	int rc = sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, identifier, -1, SQLITE_STATIC);

	if (SQLITE_ROW == sqlite3_step(stmt))
		rid = sqlite3_column_int64(stmt, 0);

	sqlite3_finalize(stmt);
	return rid;
}

arcan_targetid arcan_db_cfgtarget(struct arcan_dbh* dbh, arcan_configid cfg)
{
	static const char dql[] = "SELECT target FROM config WHERE cfgid = ?;";
	sqlite3_stmt* stmt;
	int rc = sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
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

	int rc = sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, config, strlen(config), SQLITE_STATIC);
	sqlite3_bind_int(stmt, 2, target);

	if (SQLITE_ROW == sqlite3_step(stmt))
		cid = sqlite3_column_int64(stmt, 0);

	sqlite3_finalize(stmt);
	return cid;
}

struct arcan_dbres arcan_db_targets(struct arcan_dbh* dbh)
{
	static const char dql[] = "SELECT name FROM target;";
	sqlite3_stmt* stmt;
	int rc = sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);

	return db_string_query(dbh, stmt, NULL);
}

char* arcan_db_targetexec(struct arcan_dbh* dbh,
	arcan_configid configid,
	struct arcan_dbres* argv,
	struct arcan_dbres* env)
{
	arcan_targetid tid = arcan_db_cfgtarget(dbh, configid);
	if (tid == BAD_TARGET)
		return NULL;

	sqlite3_stmt* stmt;
	static const char dql[] = "SELECT executable FROM target WHERE tgtid = ?;";
	int rc = sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql) - 1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tid);

	char* execstr = NULL;
	if (sqlite3_step(stmt) == SQLITE_ROW){
		execstr = (char*) sqlite3_column_text(stmt, 0);
	}

	if (execstr)
		execstr = strdup(execstr);

	sqlite3_finalize(stmt);

	static const char dql_tgt_argv[] = "SELECT arg FROM target_argv WHERE "
		"target = ? ORDER BY argnum ASC;";
	rc = sqlite3_prepare_v2(dbh->dbh, dql_tgt_argv,
		sizeof(dql_tgt_argv)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tid);
	*argv = db_string_query(dbh, stmt, NULL);

	static const char dql_cfg_argv[] = "SELECT arg FROM config_argv WHERE "
		"config = ? ORDER BY argnum ASC;";
	rc = sqlite3_prepare_v2(dbh->dbh, dql_tgt_argv,
		sizeof(dql_tgt_argv)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, configid);
	*argv = db_string_query(dbh, stmt, argv);

	*env = db_string_query(dbh, stmt, NULL);

/*
 * platform- specific launch function gets the job of expanding
 * meta strings (e.g. [APPLPATH]/), preloading / injecting libraries etc.
 */

	return execstr;
}

struct arcan_dbres arcan_db_configs(
	struct arcan_dbh* dbh, arcan_targetid tgt)
{
	struct arcan_dbres res = {0};
	static const char dql[] = "SELECT name FROM config WHERE target = ?;";
	sqlite3_stmt* stmt;
	int rc = sqlite3_prepare_v2(dbh->dbh, dql, sizeof(dql)-1, &stmt, NULL);
	sqlite3_bind_int(stmt, 1, tgt);

	return db_string_query(dbh, stmt, NULL);
}

void arcan_db_begin_transaction(struct arcan_dbh* dbh,
	enum DB_KVTARGET kvt, union arcan_dbtrans_id id)
{
	if (dbh->transaction)
		arcan_fatal("arcan_db_appl_kv() called during a pending transaction\n");

	sqlite3_exec(dbh->dbh, "BEGIN;", NULL, NULL, NULL);

	switch (kvt){
	case DVT_APPL:
		sqlite3_prepare_v2(dbh->dbh, dbh->akv_update,
			dbh->akv_upd_sz, &dbh->transaction, NULL);
	break;

	case DVT_TARGET:
		sqlite3_prepare_v2(dbh->dbh, DI_INSKV_TARGET,
			strlen(DI_INSKV_TARGET)+1, &dbh->transaction, NULL);
	break;

	case DVT_CONFIG:
		sqlite3_prepare_v2(dbh->dbh, DI_INSKV_CONFIG,
			strlen(DI_INSKV_CONFIG)+1, &dbh->transaction, NULL);
	break;

	case DVT_CONFIG_ENV:
		sqlite3_prepare_v2(dbh->dbh, DI_INSKV_CONFIG_ENV,
			strlen(DI_INSKV_TARGET_ENV)+1, &dbh->transaction, NULL);
	break;

	case DVT_TARGET_ENV:
		sqlite3_prepare_v2(dbh->dbh, DI_INSKV_TARGET_ENV,
			strlen(DI_INSKV_TARGET_ENV)+1, &dbh->transaction, NULL);
	break;

	case DVT_TARGET_LIBV:
		sqlite3_prepare_v2(dbh->dbh, DI_INSKV_TARGET_LIBV,
			strlen(DI_INSKV_TARGET_LIBV)+1, &dbh->transaction, NULL);
	break;
	case DVT_ENDM:
	break;
	}

	dbh->trid = id;
	dbh->ttype = kvt;
/* STUB */
}

char* arcan_db_getvalue(struct arcan_dbh* dbh,
	enum DB_KVTARGET tgt, int64_t id, const char* key)
{
	char* res = NULL;
/* must match enum */
	assert(DVT_ENDM == 5);

	const char* queries[] = {
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
		sqlite3_prepare_v2(dbh->dbh, queries[tgt], qry_sz, &stmt, NULL);
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

void arcan_db_add_kvpair(struct arcan_dbh* dbh,
	const char* key, const char* val)
{
	if (!dbh->transaction)
		arcan_fatal("arcan_db_add_kvpair() "
			"called without any open transaction.");

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

	sqlite3_step(dbh->transaction);
}

void arcan_db_end_transaction(struct arcan_dbh* dbh)
{
	if (!dbh->transaction)
		arcan_fatal("arcan_db_end_transaction() "
			"called without any open transaction.");

	sqlite3_finalize(dbh->transaction);
	sqlite3_exec(dbh->dbh, "COMMIT;", NULL, NULL, NULL);
	dbh->transaction = NULL;
}

bool arcan_db_appl_kv(struct arcan_dbh* dbh, const char* applname,
	const char* key, const char* value)
{
	bool rv = false;

	if (dbh->transaction)
		arcan_fatal("arcan_db_appl_kv() called during a pending transaction\n");

	if (!dbh || !key || !value)
		return rv;

	const char ddl_insert[] = "INSERT OR REPLACE "
		"INTO appl_%s(key, val) VALUES(?, ?);";

	size_t upd_sz = sizeof(ddl_insert) + strlen(applname);
	char upd_buf[ upd_sz ];
	ssize_t nw = snprintf(upd_buf, upd_sz, ddl_insert, applname);

	sqlite3_stmt* stmt = NULL;
	sqlite3_prepare_v2(dbh->dbh, upd_buf, nw, &stmt, NULL);
	sqlite3_bind_text(stmt, 1, key,   -1, SQLITE_TRANSIENT);
	sqlite3_bind_text(stmt, 2, value, -1, SQLITE_TRANSIENT);

	rv = sqlite3_step(stmt) == SQLITE_DONE;
/*
 * if (!rv)
		arcan_warning("add kv failed %s reason: (%s)\n",
		upd_buf,  sqlite3_errmsg(dbh->dbh));
 */

	sqlite3_finalize(stmt);

	return rv;
}

char* arcan_db_appl_val(struct arcan_dbh* dbh,
	const char* applname, const char* key)
{
	if (!dbh || !key)
		return NULL;

	const char qry[] = "SELECT val FROM appl_%s WHERE key = ?;";

	size_t wbuf_sz = strlen(applname) + sizeof(qry);
	char wbuf[ wbuf_sz ];
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

void arcan_db_free_res(struct arcan_dbh* dbh, struct arcan_dbres res)
{
	if (!dbh || res.kind == -1)
		return;

	if (res.kind == 0) {
		char** cptr = (char**) res.strarr;
		while (cptr && *cptr)
			arcan_mem_free(*cptr++);

		arcan_mem_free(res.strarr);
	}
	else;

	res.kind = -1;
}

static void setup_ddl(struct arcan_dbh* dbh)
{
	create_appl_group(dbh, "arcan");
	arcan_db_appl_kv(dbh, "arcan", "dbversion", "3");

	for (size_t i = 0; i < sizeof(ddls)/sizeof(ddls[0]); i++)
		db_void_query(dbh, ddls[i]);
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
	char* valstr = arcan_db_appl_val(dbh, "arcan", "dbversion");
	unsigned vnum = valstr ? strtoul(valstr, NULL, 10) : 0;

	switch (vnum){
		case 0:
		case 1:
		case 2:
			arcan_warning("Using old / deprecated database format,please rebuild.\n");
			return false;
	}

	return true;
}

void arcan_db_close(struct arcan_dbh** ctx)
{
	if (!ctx)
		return;

	sqlite3_close((*ctx)->dbh);
	arcan_mem_free((*ctx)->akv_update);
	arcan_mem_free((*ctx)->akv_get);
	arcan_mem_free(*ctx);
	*ctx = NULL;
}

struct arcan_dbh* arcan_db_open(const char* fname, const char* applname)
{
	sqlite3* dbh;
	int rc = 0;

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

	if ((rc = sqlite3_open_v2(fname, &dbh, SQLITE_OPEN_READWRITE, NULL))
		== SQLITE_OK){
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

		db_void_query(res, "PRAGMA foreign_keys=ON;");
		db_void_query(res, "PRAGMA synchronous=OFF;");

		return res;
	}
	else
		;

	return NULL;
}
