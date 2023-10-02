#ifndef HAVE_DIRECTORY
#define HAVE_DIRECTORY

/*
 * where is the basedir
 */
struct anet_dirsrv_opts {
	struct a12_context_options* a12_cfg;
	int basedir;
	struct appl_meta dir;
	size_t dir_count;
	const char* allow_src;
	const char* allow_dir;
	const char* allow_appl;
	const char* allow_ctrl;
	const char* allow_ares;
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
struct directory_meta;
struct anet_dircl_opts {
	int basedir;
	char applname[16];
	bool die_on_list;
	bool reload;
	bool block_state;
	bool block_log;
	bool keep_appl;

	char ident[16];
/*
 * set to source / exec an arcan-shmif client:
 *  /path/to/bin arg1 arg2 arg3, ...
 */
	size_t source_argc;
	char** source_argv;

	struct appl_meta outapp;

	void* (*allocator)(struct a12_state*, struct directory_meta*);
	pid_t (*executor)(struct a12_state*,
		struct directory_meta*, const char*, void* tag, int* inf, int* outf);
};

struct directory_meta {
	struct a12_state* S;
	struct anet_dircl_opts* clopt;

	bool in_transfer;
	uint32_t transfer_id;

	FILE* appl_out;
	bool appl_out_complete;
	int state_in;
	bool state_in_complete;

	struct arcan_shmif_cont* C;
};

/*
 * dir_srv.c
 */
void anet_directory_srv_rescan(struct anet_dirsrv_opts* opts);

void anet_directory_srv(
	struct a12_context_options*, struct anet_dirsrv_opts, int fdin, int fdout);

/*
 * shmif connection to map to a thread for coordination
 */
void anet_directory_shmifsrv_thread(struct shmifsrv_client*);
void anet_directory_shmifsrv_set(struct anet_dirsrv_opts* opts);

/*
 * dir_cl.c
 */
void anet_directory_cl(
	struct a12_state* S, struct anet_dircl_opts opts, int fdin, int fdout);

struct a12_bhandler_res anet_directory_cl_bhandler(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag);

/*
 * dir_supp.c
 *
 * handle a12 on fdin/fdout,
 * multiplex and trigger on incoming for usrfd_mask (typically shmif)
 * and forward on_event, on_directory, on_userfd
 */
extern bool g_shutdown;

bool build_appl_pkg(const char* name, struct appl_meta* dst, int dirfd);
FILE* file_to_membuf(FILE* applin, char** out, size_t* out_sz);

void anet_directory_ioloop
	(struct a12_state* S, void* tag,
	int fdin, int fdout,
	int usrfd,
	void (*on_event)(struct arcan_shmif_cont* cont, int chid, struct arcan_event*, void*),
	bool (*on_directory)(struct a12_state* S, struct appl_meta* dir, void*),
	void (*on_userfd)(struct a12_state* S, void*));

#endif
