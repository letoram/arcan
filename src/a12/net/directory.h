#ifndef HAVE_DIRECTORY
#define HAVE_DIRECTORY

/*
 * where is the basedir
 */
struct anet_dirsrv_opts {
	int basedir;
	struct appl_meta dir;
	size_t dir_count;
};

/*
 * A config file for the modes is kindof needed at this point:
 *
 *   - where is the appltemp
 *   - delete on shutdown?
 *   - continuous reload / update
 *   - block saves
 *   - send reports
 *   - force fontpath
 *   - block afsrv(dec,enc,term,net)
 *   - custom afsrv set
 *   - synch db k/v as state (arcan_db show_appl ...)
 *
 * Which again ties into some need to be able to inject events into shmif
 */
struct anet_dircl_opts {
	int basedir;
	const char* applname;
	bool die_on_list;
	bool reload;
	bool block_state;
	bool block_log;
	bool keep_appl;
};

void anet_directory_srv_rescan(struct anet_dirsrv_opts* opts);

void anet_directory_srv(
	struct a12_state* S, struct anet_dirsrv_opts opts, int fdin, int fdout);

void anet_directory_cl(
	struct a12_state* S, struct anet_dircl_opts opts, int fdin, int fdout);

#endif
