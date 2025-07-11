/* internal interfaces for implementing directory server / client */

#ifndef HAVE_DIRECTORY
#define HAVE_DIRECTORY

#define SIG_PUBK_SZ 32
#define SIG_PRIVK_SZ 64
#define SIG_VAL_SZ 64

struct anet_dirsrv_opts {
	struct a12_context_options* a12_cfg;
	int basedir;
	struct appl_meta dir;
	size_t dir_count;

	bool allow_tunnel;
	bool discover_beacon;
	bool runner_process;
	bool flush_on_report;

	char* allow_src;
	char* allow_dir;
	char* allow_appl;
	char* allow_ctrl;
	char* allow_ares;
	char* allow_admin;
	char* allow_monitor;
	char* allow_applhost;
	char* allow_install;

	char* resource_path;
	int resource_dfd;

	char* appl_server_path; /* hosting server-side appl controller */
	int appl_server_dfd;

	char* appl_server_datapath; /* set if the controller is allowed datastore */
	int appl_server_datadfd;

	char* appl_logpath;
	char* applhost_path; /* used with allow_applhost */

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
	bool applhost;         /* request that the server hosts the appl (req perm) */
	int monitor_mode;

	char ident[16]; /* name to identify as (a-z0-9) */
	const char* sign_tag;

/* callback handler for sinking a directory server registered source */
	void (*dir_source)(struct a12_state*, struct a12_dynreq req, void* tag);
	void *dir_source_tag;
	uint16_t source_port;

/* filled if an upload (store) operation is requested */
	struct appl_meta outapp;
	bool outapp_install;
	bool outapp_ctrl;
	const char* build_appl;
	int build_appl_dfd;

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
	bool in_monitor;
	char identity[16]; /* msggroup identifier (no ctrl) */
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

/* slot for callback handler registration in config.lua script */
	intptr_t lua_cb;

/* authentication public key and whether it is approved or not */
	uint8_t pubk[32];
	bool authenticated;
	bool in_admin;
	bool dir_link;
	int admin_fdout;

/* initially {0}, only updated after REKEY in A12 */
	uint8_t pubk_sign[SIG_PUBK_SZ];

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
	bool cast;
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

enum {
	DIRLUA_EVENT_LOST
};

struct dirlua_event {
	int kind;
	const char* msg;
};

void anet_directory_lua_event(struct dircl*, struct dirlua_event*);

/*
 * dir_srv.c
 * only run once.
 */
void anet_directory_srv_scan(struct anet_dirsrv_opts* opts);

void anet_directory_srv(
	struct a12_context_options*, struct anet_dirsrv_opts, int fdin, int fdout);

/*
 * shmif connection to map to a thread for coordination with the privsep worker
 * if [link] is set the worker act as a linked directory and transfer requests
 * that can't be solved locally propagate.
 */
struct dircl* anet_directory_shmifsrv_thread(
	struct shmifsrv_client*, struct a12_state*, bool link);

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

/*
 * Verify the contents of an in-memory appl and check signatures against
 * header. Signatures are optional, so if there isn't one in the pkg validation
 * will still go through.
 *
 *  Insig_pk :- the signature of the supplier
 * Outsig_pk :- the output signature in the header
 *
 * nullsig = uint8_t[static SIG_PUBK_SZ]
 */
char* verify_appl_pkg(
	char* buf, size_t buf_sz,
	uint8_t insig_pk[static SIG_PUBK_SZ],
	uint8_t outsig_pk[static SIG_PUBK_SZ],
	const char** errmsg);

/*
 * If a signtag is provided, the keystore needs to be open
 */
bool build_appl_pkg(
	const char* name, struct appl_meta* dst, int dirfd, const char* signtag);

bool extract_appl_pkg(FILE* fin, int dirfd, const char* basename, const char** msg);

FILE* file_to_membuf(FILE* applin, char** out, size_t* out_sz);

struct ioloop_shared;
struct ioloop_shared {
	int fdin;
	int fdout;
	int userfd;
	int userfd2;
	int wakeup;

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

void anet_directory_random_ident(char* dst, size_t nb);

/* build the global- lua context and tie to a sqlite database represented by fd */
bool anet_directory_lua_init(struct global_cfg* cfg);

/* directory is scanned and ready */
void anet_directory_lua_ready(struct global_cfg* cfg);

void anet_directory_lua_update(struct appl_meta* appl, int newappl);

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
bool anet_directory_lua_spawn_runner(
	struct appl_meta* appl, bool external);

/*
 * request to send signal [no] to process or thread associated with appl-runner
 */
bool anet_directory_signal_runner(struct appl_meta* appl, int no);

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

void anet_directory_tunnel_thread(struct ioloop_shared* ios, uint8_t chid);

struct ioloop_shared* anet_directory_ioloop_current();
void anet_directory_ioloop(struct ioloop_shared* S);

/*
 * [LOCKED]
 *  trigger any config queued auto- controller launches
 */
void anet_directory_lua_trigger_auto(struct appl_meta* appl);

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
	MULTIPART_BAD_MSG   = 3,
	MULTIPART_BAD_EVENT = 4
};

/*
 * logging and keystore access need exclusive locks
 */
void dirsrv_global_lock(const char* file, int line);
void dirsrv_global_unlock(const char* file, int line);

struct global_cfg* dirsrv_static_opts();

/*
 * handle EVENT_EXTERNAL_MESSAGE and TARGET_COMMAND_MESSAGE multipart merging,
 * provide either [arg_arr] or an [outchar] to specify if the output is intended
 * to be treated as
 */
bool anet_directory_merge_multipart(
	struct arcan_event* ev, struct arg_arr**, char**, int* err);

int anet_directory_link(
	const char* keytag,
	struct anet_options* netcfg,
	struct anet_dirsrv_opts srvcfg,
	bool reference
);

/*
 * Take a file descriptor covering a directory server content index and
 * unpack into a dynamically allocated linked list of appls suitable for
 * forwarding to a12int_set_directory.
 */
struct appl_meta* dir_unpack_index(int fd);

enum {
	BREQ_LOAD = false,
	BREQ_STORE = true
};

/*
 * Used by a directory worker to [synchronous, blocking, non-reentrant]
 * retrieve a descriptor from the parent for the specified resource in
 * for input or output.
 *
 * [pending] will be populated with dynamically allocated (and for
 * descrevents, dup:ed) events that were received while waiting for the
 * response as with dir_block_synch_request.
 *
 * It's the caller responsibility to process/free/close this.
 */
struct evqueue_entry;
struct evqueue_entry {
	struct arcan_event ev;
	struct evqueue_entry* next;
};

/*
 * wrapper around BCHUNK_ + dir_block_synch_request, updates pending.
 */
bool dir_request_resource(
	struct arcan_shmif_cont* C, size_t ns, const char* id, int mode,
	struct evqueue_entry* pending
);

/*
 * only useful from srv-side-ctrl to lua-side-ctrl mapping
 */
struct dircl* dirsrv_find_cl_ident(int appid, const char* name);

/*
 * Enqueue [outev] to [C] and enter a blocking wait loop for a matching reply,
 * any other inbound events received in the interim will get queued into
 * [reply]. Trigger conditions for successful (=true) result is an event of
 * [category_ok, kind_ok] and for unsuccessful (=false) [category_fail,
 * kind_fail].
 */
bool dir_block_synch_request(
	struct arcan_shmif_cont* C, struct arcan_event outev,
	struct evqueue_entry* pending,
	int category_ok, int kind_ok,
	int category_fail, int kind_fail);

/*
 * Mark a source arriving with pubk[..] as belonging to [appid] and possibly
 * [name] (if set).
 */
void dirsrv_set_source_mask(
	uint8_t pubk[static 32], int appid,
	char identity[static 16], uint8_t dstpubk[static 32]);

/* [EXPECT_LOCKED]
 * Collect and merge all debug dumps from clients, care should be taken to
 * validate the actual contents as each is provided raw from a potentially
 * untrusted source.
 */
int dirsrv_build_report(const char* appl);

/* [EXPECT_LOCKED]
 * Unlink all debug dumps on [appl] from clients
 */
void dirsrv_flush_report(const char* appl);

/*
 * Spin up a new ephemeral source process for connecting and registering in a
 * directory. Specify applid (> 0) and/or [dst] to limit visibility and access
 * to a single client.
 */
struct arcan_strarr;
bool anet_directory_dirsrv_exec_source(
	struct dircl* dst, uint16_t applid, const char* ident,
	char* exec, struct arcan_strarr* argv, struct arcan_strarr* envv);

#endif
