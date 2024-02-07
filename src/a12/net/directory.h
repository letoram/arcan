#ifndef HAVE_DIRECTORY
#define HAVE_DIRECTORY

/*
 * where is the basedir
 */
struct anet_dirsrv_opts {
	struct a12_context_options* a12_cfg;
	volatile bool flag_rescan;
	int basedir;
	struct appl_meta dir;
	size_t dir_count;

	bool allow_tunnel;
	char* allow_src;
	char* allow_dir;
	char* allow_appl;
	char* allow_ctrl;
	char* allow_ares;

	char* resource_path;
	int resource_dfd;

	char* appl_server_path;
	char* appl_logpath;
	int appl_server_dfd;
	int appl_logdfd;
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
	char basedir_path[PATH_MAX];

	char* appl_runner;
	char applname[16];
	uint16_t applid;

	bool die_on_list;
	bool reload;
	bool block_state;
	bool block_log;
	bool stderr_log;
	bool keep_appl;
	bool request_tunnel;

	char ident[16];
	void (*dir_source)(struct a12_state*, struct a12_dynreq req, void* tag);
	void *dir_source_tag;
	uint16_t source_port;

	struct appl_meta outapp;

	void* (*allocator)(struct a12_state*, struct directory_meta*);
	pid_t (*executor)(struct a12_state*,
		struct directory_meta*, const char*, void* tag, int* inf, int* outf);
};

struct directory_meta {
	struct a12_state* S;
	struct anet_dircl_opts* clopt;

	char* secret;
	bool in_transfer;
	uint32_t transfer_id;

	FILE* appl_out;
	bool appl_out_complete;
	int state_in;
	bool state_in_complete;

	struct arcan_shmif_cont* C;
};

struct dircl;

struct dircl {
	int in_appl;

	char identity[16];

	int type;
	bool pending_stream;
	int pending_fd;
	uint16_t pending_id;

	arcan_event petname;
	arcan_event endpoint;

	uint8_t pubk[32];
	bool authenticated;

	char message_multipart[1024];
	size_t message_ofs;

	struct shmifsrv_client* C;
	struct dircl* next;
	struct dircl* prev;

/* [UAF-risk] 1:1 for now - always check this when removing a dircl */
	struct dircl* tunnel;
};

struct global_cfg {
	bool soft_auth;
	bool no_default;
	bool probe_only;
	bool keep_alive;
	size_t accept_n_pk_unknown;
	size_t backpressure;
	size_t backpressure_soft;
	int directory;
	struct anet_dirsrv_opts dirsrv;
	struct anet_dircl_opts dircl;
	struct anet_options meta;

	char* trust_domain;
	char* path_self;
	char* outbound_tag;
	char* config_file;
	char* db_file;
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
void anet_directory_shmifsrv_thread(struct shmifsrv_client*, struct a12_state*);
void anet_directory_shmifsrv_set(struct anet_dirsrv_opts* opts);

/*
 * dir_cl.c
 */
void anet_directory_cl(
	struct a12_state* S, struct anet_dircl_opts opts, int fdin, int fdout);

struct a12_bhandler_res anet_directory_cl_bhandler(
	struct a12_state* S, struct a12_bhandler_meta M, void* tag);

void dircl_source_handler(
	struct a12_state* S, struct a12_dynreq req, void* tag);

/*
 * dir_supp.c
 *
 * handle a12 on fdin/fdout,
 * multiplex and trigger on incoming for usrfd_mask (typically shmif)
 * and forward on_event, on_directory, on_userfd
 */
bool build_appl_pkg(const char* name, struct appl_meta* dst, int dirfd);
bool extract_appl_pkg(FILE* fin, int dirfd, const char* basename, const char** msg);

FILE* file_to_membuf(FILE* applin, char** out, size_t* out_sz);

struct ioloop_shared;
struct ioloop_shared {
	int fdin;
	int fdout;
	int userfd;
	int userfd2;

	struct arcan_shmif_cont shmif;
	struct arcan_shmif_cont* handover;

	pthread_mutex_t lock;
	struct a12_state *S;
	volatile bool shutdown;
	struct directory_meta* cbt;

/* interface mandated by a12, hence shared passed in tag */
	void (*on_event)(
		struct arcan_shmif_cont* cont, int chid,
		struct arcan_event*, void*);

	bool (*on_directory)(struct ioloop_shared* S, struct appl_meta* dir);
	void (*on_userfd)(struct ioloop_shared* S, bool ok);
	void (*on_userfd2)(struct ioloop_shared* S, bool ok);
	void (*on_shmif)(struct ioloop_shared* S, bool ok);
	void* tag;
};

/* build the global- lua context and tie to a sqlite database represented by fd */
bool anet_directory_lua_init(struct global_cfg* cfg);

/* privsep process running server-side scripts for an appl */
void anet_directory_appl_runner();

struct pk_response
	anet_directory_lua_register_unknown(struct dircl* C, struct pk_response base);
void anet_directory_lua_register(struct dircl* C);

/* Theoretically it's possble for one C to be in multiple appls so the API
 * reflects that, even though right now that is constrained to 1:(0,1) in the
 * dir_srv.c side. Leave doesn't strictly happen here as the appl-runner
 * process handles that part of messaging. */
bool anet_directory_lua_join(struct dircl* C, struct appl_meta* appl);

/* for post-transfer completion hooks to perform atomic rename / fileswaps etc. */
void anet_directory_lua_bchunk_completion(struct dircl* C, bool ok);

/* <0, reject
 * =0, don't-care / default
 *  1, accept
 */
int anet_directory_lua_filter_source(struct dircl* C, arcan_event* ev);

void anet_directory_tunnel_thread(struct ioloop_shared* ios, struct a12_state* S);
void anet_directory_ioloop(struct ioloop_shared* S);

#endif
