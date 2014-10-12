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

#ifndef _HAVE_ARCAN_DB

struct arcan_dbh;

enum DB_BFORMAT {
	BFRM_ELF = 0x00,   /* regular executable          */
	BFRM_LWA = 0x01,   /* lightweight_arcan loader    */
	BFRM_RETRO = 0x02  /* frameserver_libretro loader */

/* add more here to force interpreters and arguments */
};

/*
 * There are numerous key-value type stores in use here,
 * DVT_APPL / TARGET / CONFIG is for script/user defined data
 * the ENV / ARGV / LIBV groups are for generating the execution environment
 */
enum DB_KVTARGET {
	DVT_APPL        = 0,
	DVT_TARGET      = 1,
	DVT_TARGET_ENV  = 2,
	DVT_TARGET_LIBV = 3,
	DVT_CONFIG      = 10,
	DVT_CONFIG_ENV  = 11,
	DVT_ENDM = 5
};

typedef long arcan_targetid;
typedef long arcan_configid;

static const int BAD_TARGET = -1;
static const int BAD_CONFIG = -1;

struct arcan_dbres {
	char kind;
	unsigned int count;
	unsigned int limit;

	char** strarr;
};

/* Opens database and performs a sanity check,
 * Creates an entry for applname unless one already exists,
 * returns null IF fname can't be opened/read OR sanity check fails.
 */
struct arcan_dbh* arcan_db_open(const char* fname, const char* applname);

/*
 * Synchronize and flush possibly pending queries,
 * then free resources and reset the handle.
 * *dbh will be set to NULL.
 */
void arcan_db_close(struct arcan_dbh**);

/*
 * Define this to add database features that should
 * only be present in a standalone application
 * (as the running arcan session should NOT be able to
 * add new targets/configurations by itself)
 */
#ifdef ARCAN_DB_STANDALONE
/*
 * delete everything associated with a specific target or config,
 * including specific K/V store.
 */
bool arcan_db_droptarget(struct arcan_dbh* dbh, arcan_targetid);

/*
 * there will always be a 'default' config ID associated with any
 * target that can only be removed with the target itself.
 */
bool arcan_db_dropconfig(struct arcan_dbh* dbh, arcan_configid);

arcan_targetid arcan_db_addtarget(struct arcan_dbh* dbh,
	const char* identifier, /* unique, string identifier of the target */
	const char* exec,       /* executable identifier */
	const char* argv,       /* argument string that will be attached */
	enum DB_BFORMAT bfmt    /* defines how execution should be set up */
	);

arcan_configid arcan_db_addconfig(struct arcan_dbh* dbh,
	arcan_targetid,	const char* identifier, const char* argv);
#endif

/*
 * Append launch-status to the log.
 */
void arcan_db_launch_status(struct arcan_dbh*, int configid, bool failed);

/*
 * Lookup target based on string name.
 * If set, the default configuration and lookup status will also be returned
 */
arcan_targetid arcan_db_targetid(struct arcan_dbh*,
	const char* targetname, arcan_configid*);

arcan_configid arcan_db_configid(struct arcan_dbh*,
	arcan_targetid targetname, const char* configname);

/*
 * Generate the execution environment for a configuration identifier.
 * (returns exec-str, and a dbres for environment, arguments)
 */
char* arcan_db_targetexec(struct arcan_dbh*,
	arcan_configid configid,
	struct arcan_dbres* argv, struct arcan_dbres* env
);

/*
 * Retrieve a list of available targets
 */
struct arcan_dbres arcan_db_targets(struct arcan_dbh*);

/*
 * Retrieve a list of available configurations
 */
struct arcan_dbres arcan_db_configs(struct arcan_dbh*, arcan_targetid);

union arcan_dbtrans_id {
	arcan_configid cid;
	arcan_targetid tid;
	const char* applname;
};

void arcan_db_begin_transaction(struct arcan_dbh*, enum DB_KVTARGET,
	union arcan_dbtrans_id);
void arcan_db_add_kvpair(struct arcan_dbh*, const char* key, const char* val);
void arcan_db_end_transaction(struct arcan_dbh*);

char* arcan_db_getvalue(struct arcan_dbh*,
	enum DB_KVTARGET, int64_t id, const char* key);

/*
 * Returns true or false depending on if the requested targetid
 * exists or not.
 */
bool arcan_db_verifytarget(struct arcan_dbh* dbh, arcan_targetid);

/*
 * Synchronously store/retrieve a key-value pair,
 * set to empty value to delete.
 */
bool arcan_db_appl_kv(struct arcan_dbh* dbh, const char* appl,
	const char* key, const char* value);

/*
 * Retrieve the current value stored with key
 * caller is expected to mem_free string, can return NULL.
 */
char* arcan_db_appl_val(struct arcan_dbh* dbh,
	const char* appl, const char* key);

/*
 * Any function that returns an struct arcan_dbres should be explicitly
 * freed by calling this function.
 */
void arcan_db_free_res(struct arcan_dbh* dbh, struct arcan_dbres res);

#endif
