/* internal interfaces for implementing directory server / client */

#ifndef HAVE_DIRECTORY
#define HAVE_DIRECTORY

struct anet_dirsrv_opts {
	struct a12_context_options* a12_cfg;
	volatile bool flag_rescan;
	int basedir;
	struct appl_meta dir;
	size_t dir_count;

	bool allow_tunnel;
	bool discover_beacon;

	char* allow_src;
	char* allow_dir;
	char* allow_appl;
	char* allow_ctrl;
	char* allow_ares;
	char* allow_admin;
	char* allow_monitor;

	char* resource_path;
	int resource_dfd;

	char* appl_server_path; /* hosting server-side appl controller */
	int appl_server_dfd;

	char* appl_logpath;

 /* Set when permitting dynamic controller push, takes precendence over
	* appl-server-path unless instructed to rollback. */
	char* appl_server_temp_path;
	int appl_server_temp_dfd;

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

enum monitor_mode {
	MONITOR_NONE     = 0,
	MONITOR_SIMPLE   = 1,
	MONITOR_DEBUGGER = 2,
	MONITOR_ADMIN    = 3
};

struct anet_dircl_opts {
/* where are appls loaded from? */
	int basedir;
	char basedir_path[PATH_MAX];

/* filled if an appl is requested */
	char* appl_runner;
	char applname[18];    /* identifier is max 18, but we user-code options
													 as characters, < for source, > for sink and |
													 prefix for tunnel only */
	uint16_t applid;

	bool die_on_list;
	bool reload;           /* reload / re-execute appl if changed on server */
	bool block_state;      /* don't try to save state */
	bool block_log;        /* stop appl_runner from logging */
	bool stderr_log;       /* forward appl_runner stderr */
	bool keep_appl;        /* don't unlink / erase appl after running */
	bool request_tunnel;   /* relay traffic through directory if necessary */
	int monitor_mode;

	char ident[16]; /* name to identify as (a-z0-9) */

/* callback handler for sinking a directory server registered source */
	void (*dir_source)(struct a12_state*, struct a12_dynreq req, void* tag);
	void *dir_source_tag;
	uint16_t source_port;

/* filled if an upload (store) operation is requested */
	struct appl_meta outapp;
	bool outapp_ctrl;

/* filled if an upload or download is requested */
	struct {
		char* name;
		char* path;
		char applname[16];
	} upload;

	struct {
		char* name;
		char* path;
		char applname[16];
	} download;

/* actions for [reserve space / unpack] -> [execute] */
	void* (*allocator)(struct a12_state*, struct directory_meta*);
	pid_t (*executor)(struct a12_state*,
		struct directory_meta*, const char*, void* tag, int* inf, int* outf);
};

/*
 * This struct regulates the connection and config between main, and worker.
 */
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

/* for file transfers, the first BCHUNKSTATE event is stored here, waiting
 * for the corresponding bstream command */
	arcan_event breq_pending;

	struct arcan_shmif_cont* C;
};


/*
 * This is used to track each discrete client >both< in main and worker. They
 * don't need to be synched between the two, each side tracks the information
 * they need.
 */
struct dircl;
struct dircl {
	int in_appl; /* have they joined an appl- controller? */

	char identity[16]; /* presentable source identifier */

	int type; /* source, sink or directory */

/* used to track request and pairing from a BCHUNKSTATE request for input and
 * the request to the parent to access the keystore */
	bool pending_stream;
	int pending_fd;
	uint16_t pending_id;

/* netstate event used to transfer keys, for the client and if there is a
 * tunnel request */
	arcan_event petname;
	arcan_event endpoint;

/* authentication public key and whether it is approved or not */
	uint8_t pubk[32];
	bool authenticated;
	bool in_admin;
	int admin_fdout;

/* accumulation buffer so that we don't permit forwarding unterminated
 * MESSAGE chains to appl-controller */
	char message_multipart[1024];
	size_t message_ofs;
	void* userdata;

/* the parent end handle to the worker */
	struct shmifsrv_client* C;

/* stored as a linked list */
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
	bool discover_synch; /* update keystore ip with most recently seen */

	size_t accept_n_pk_unknown;
	size_t backpressure;
	size_t backpressure_soft;
	int directory;
	struct anet_dirsrv_opts dirsrv;
	struct anet_dircl_opts dircl;
	struct anet_options meta;

	bool use_forced_remote_pubk;
	uint8_t forced_remote_pubk[32];

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

void anet_directory_lua_update(volatile struct appl_meta* appl, int newappl);

/* for config- specific custom implementation of an admin control channel */
bool anet_directory_lua_admin_command(struct dircl* C, const char* msg);

/* privsep process running server-side scripts for an appl */
void anet_directory_appl_runner();

void anet_directory_lua_unregister(struct dircl* C);

struct pk_response
	anet_directory_lua_register_unknown(
		struct dircl* C, struct pk_response base, const char* pubk);

void anet_directory_lua_register(struct dircl* C);

/*
 * called before the first anet_directory_lua_join, sets up the runner process
 * and VM for the current controller appl pointed to by [appl]. If [external]
 * is set this is done through execve()ing ourself (for sandbox and ASLR), if
 * it is not set it will run as a detached pthread.
 */
bool anet_directory_lua_spawn_runner(struct appl_meta* appl, bool external);

/* Theoretically it's possble for one C to be in multiple appls so the API
 * reflects that, even though right now that is constrained to 1:(0,1) in the
 * dir_srv.c side. Leave doesn't strictly happen here as the appl-runner
 * process handles that part of messaging. */
bool anet_directory_lua_join(struct dircl* C, struct appl_meta* appl);

/* Similar to a join, but it doesn't trigger an in-script action and any
 * messages on it are interpreted as debug/monitor commands rather than
 * actually directed messages. This joins with a12:kill=%d messages in order to
 * interrupt execution and break into monitor for remote debugging. */
bool anet_directory_lua_monitor(struct dircl* C, struct appl_meta* appl);

/* for post-transfer completion hooks to perform atomic rename / fileswaps etc. */
void anet_directory_lua_bchunk_completion(struct dircl* C, bool ok);

/* <0, reject
 * =0, don't-care / default
 *  1, accept
 */
int anet_directory_lua_filter_source(struct dircl* C, arcan_event* ev);

void anet_directory_tunnel_thread(struct ioloop_shared* ios, struct a12_state* S);
void anet_directory_ioloop(struct ioloop_shared* S);

/*
 * coalesce multipart- split EVENT_EXTERNAL_MESSAGE and treat as ARCAN_ARG
 * encoded (key=val:, substitute : for \t and block \t as it was meant for
 * regular grammar interactive CLI typing)
 *
 * Returns [true] when event chain is terminated and set *out to the parsed arg.
 * Returns [false] and sets *err to 0 when more events are required or *err to
 *                 corresponding enum error.
 *
 * as necessary. Returns true when [out] is parsed.
 *
 * This uses TLS+heap for internal buffering, call with a NULL ev on thread
 * termination to ensure cleanup with 1:1 source - unpacker.
 *
 * This does not set a cap, it will coalesce for as long as messages are fed
 * or OOM. Any cap limit should be dealt by the caller.
 */
enum multipart_fail {
	MULTIPART_OOM       = 1,
	MULTIPART_BAD_FMT   = 2,
	MULTIPART_BAD_MSG   = 3
};

/*
 * logging and keystore access need exclusive locks
 */
void dirsrv_global_lock(const char* file, int line);
void dirsrv_global_unlock(const char* file, int line);

bool anet_directory_merge_multipart(
	struct arcan_event* ev, struct arg_arr**, int* err);

#endif
