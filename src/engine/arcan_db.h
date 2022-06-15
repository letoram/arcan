/*
 * Copyright 2014-2016, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 */

#ifndef HAVE_ARCAN_DB
#define HAVE_ARCAN_DB

struct arcan_dbh;

enum DB_BFORMAT {
	BFRM_SHELL  = 0x00,   /* shell script (/bin/sh)      */
	BFRM_BIN    = 0x01,   /* normal executable           */
	BFRM_LWA    = 0x02,   /* lightweight_arcan loader    */
	BFRM_GAME   = 0x03,   /* afsrv_game loader           */
	BFRM_EXTERN = 0x04    /* external launch             */

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

/* Opens database and performs a sanity check,
 * Creates an entry for applname unless one already exists,
 * returns null IF fname can't be opened/read OR sanity check fails.
 */
struct arcan_dbh* arcan_db_open(const char* fname, const char* applname);

/*
 * [THREAD UNSAFE]
 * accessor functions to a shared static database handle
 * applv- refers to the reserved namespace (e.g. ARCAN_APPL
 */
struct arcan_dbh* arcan_db_get_shared(const char** appl);
void arcan_db_set_shared(struct arcan_dbh*);

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
	const char* group,      /* sorting / grouping tag, non-enforced */
	const char* exec,       /* executable identifier */
	const char* argv[],     /* argument string that will be attached */
	size_t nargs,
	enum DB_BFORMAT bfmt    /* defines how execution should be set up */
	);

arcan_configid arcan_db_addconfig(struct arcan_dbh* dbh,
	arcan_targetid, const char* identifier, const char* argv[],
	size_t nargs);
#endif

/*
 * Append launch-status (pass, true or fail false) to the log.
 */
void arcan_db_launch_status(struct arcan_dbh*, arcan_configid, bool);

/*
 * Lookup target based on string name.
 * If set, the default configuration and lookup status will also be returned
 */
arcan_targetid arcan_db_targetid(struct arcan_dbh*,
	const char* targetname, arcan_configid*);

/*
 * Retrieve the tag associated with a specific target
 */
char* arcan_db_targettag(struct arcan_dbh*, arcan_targetid targetname);

arcan_configid arcan_db_configid(struct arcan_dbh*,
	arcan_targetid targetname, const char* configname);

/*
 * Generate the execution environment for a configuration identifier.
 * BFMT defines which loading / execution mechanism should be used,
 * i.e. LWA (arcan-in-arcan package), regular ELF, etc.
 *
 * Expansion rules, mechanisms for making sure functions in libs
 * intercept native ones etc. are up to the underlying platform
 * implementation.
 */
char* arcan_db_targetexec(struct arcan_dbh*,
	arcan_configid configid,
	enum DB_BFORMAT* bfmt,
	struct arcan_strarr* argv,
	struct arcan_strarr* env,
	struct arcan_strarr* libs
);

/*
 * retrieve a list of unique target tags that have been used
 */
struct arcan_strarr arcan_db_target_tags(struct arcan_dbh*);

/*
 * Provided primarily for debugging / tool reasons, this data
 * comes implied with the _exec functions
 */
struct arcan_strarr arcan_db_target_argv(struct arcan_dbh*, arcan_targetid);
struct arcan_strarr arcan_db_config_argv(struct arcan_dbh*, arcan_configid);

/*
 * Retrieve a list of available targets
 * Optionally filtered using [tag]
 */
struct arcan_strarr arcan_db_targets(struct arcan_dbh*, const char* tag);

/*
 * Retrieve a list of available configurations
 */
struct arcan_strarr arcan_db_configs(struct arcan_dbh*, arcan_targetid);

union arcan_dbtrans_id {
	arcan_configid cid;
	arcan_targetid tid;
	const char* applname;
};

/*
 * Storage operations on a key- store are marked as transactions,
 * i.e. begin_transaction to specify the type then repeatedly call add_kvpair
 * and finalize with end_transaction. While inside a transaction, the
 * only valid db operation is add_kvpair and end_transaction.
 */
void arcan_db_begin_transaction(struct arcan_dbh*, enum DB_KVTARGET,
	union arcan_dbtrans_id);

/*
 * if val is set to NULL, all entries with an 0-length string will be dropped
 * in the transaction target.
 */
void arcan_db_add_kvpair(struct arcan_dbh*, const char* key, const char* val);
void arcan_db_end_transaction(struct arcan_dbh*);

/*
 * Retrieve a value from the specified keystore (id will be ignored
 * if it's an appl- specific keystore that is requested)
 */
char* arcan_db_getvalue(struct arcan_dbh*,
	enum DB_KVTARGET, int64_t id, const char* key);

/*
 * dump all kv pairs as key=value for a specific
 * target or configuration
 */
struct arcan_strarr arcan_db_getkeys(struct arcan_dbh*,
	enum DB_KVTARGET, union arcan_dbtrans_id);

/*
 * get a copy of the executable associated with a specific target
 */
char* arcan_db_execname(struct arcan_dbh* dbh, arcan_targetid tid);

/*
 * return a list of id:value strings for configurations or targets
 * that match pattern.
 */
struct arcan_strarr arcan_db_matchkey(struct arcan_dbh*, enum DB_KVTARGET,
	const char* pattern);

/*
 * return a key=value list for appl- specific keys matching pattern
 */
struct arcan_strarr arcan_db_applkeys(struct arcan_dbh*,
	const char* appl, const char* pattern);

/*
 * return a list of valid appl names
 */
struct arcan_strarr arcan_db_list_appl(struct arcan_dbh* dbh);

/*
 * Returns true or false depending on if the requested targetid
 * exists or not.
 */
bool arcan_db_verifytarget(struct arcan_dbh* dbh, arcan_targetid);

/*
 * Quick- reset settings / specific keys
 */
void arcan_db_dropappl(struct arcan_dbh* dbh, const char* appl);

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
	const char* const appl, const char* const key);

/*
 * Any function that returns an struct arcan_strarr should be explicitly
 * freed by calling this function.
 */
void arcan_db_free_res(struct arcan_strarr* res);

#endif
