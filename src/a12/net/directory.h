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

struct directory_meta {
	struct appl_meta* dir;
	struct a12_state* S;
	struct anet_dircl_opts* clopt;
	FILE* appl_out;
	bool appl_out_complete;
	int state_in;
	bool state_in_complete;
};

void anet_directory_srv_rescan(struct anet_dirsrv_opts* opts);

void anet_directory_srv(
	struct a12_state* S, struct anet_dirsrv_opts opts, int fdin, int fdout);

void anet_directory_cl(
	struct a12_state* S, struct anet_dircl_opts opts, int fdin, int fdout);

/*
 * handle a12 on fdin/fdout,
 * multiplex and trigger on incoming for usrfd_mask (typically shmif)
 * and forward on_event, on_directory, on_userfd
 */
void anet_directory_ioloop
	(struct a12_state* S, void* tag,
	int fdin, int fdout,
	int usrfd,
	void (*on_event)(struct arcan_shmif_cont* cont, int chid, struct arcan_event*, void*),
	bool (*on_directory)(struct a12_state* S, struct appl_meta* dir, void*),
	void (*on_userfd)(struct a12_state* S, void*));

#endif
