struct mstate {
	union {
		struct {
			int32_t ax, ay, lx, ly;
			uint8_t rel : 1;
			uint8_t inrel : 1;
		};
		uint8_t state[ASHMIF_MSTATE_SZ];
	};
};

enum support_states {
	SUPPORT_EVENT_VSIGNAL,
	SUPPORT_EVENT_POLL,
	SUPPORT_EVENT_EXIT
};

struct shmif_hidden {
	struct arg_arr* args;
	char* last_words;

	shmif_trigger_hook_fptr video_hook;
	void* video_hook_data;

	void (*support_window_hook)(struct arcan_shmif_cont* c, int state);
	void* support_window_hook_data;

	uint8_t vbuf_ind, vbuf_cnt;
	bool vbuf_nbuf_active;
	uint64_t vframe_id;
	shmif_pixel* vbuf[ARCAN_SHMIF_VBUFC_LIM];

	shmif_trigger_hook_fptr audio_hook;
	void* audio_hook_data;
	uint8_t abuf_ind, abuf_cnt;
	shmif_asample* abuf[ARCAN_SHMIF_ABUFC_LIM];

	shmif_reset_hook_fptr reset_hook;
	void* reset_hook_tag;

/* Initial contents gets dropped after first valid !initial call after open,
 * otherwise we will be left with file descriptors in the process that might
 * not get used. What argues against keeping them after is that we also need
 * to track the descriptor carrying events and swap them out. The issue is
 * relevant when it comes to the subsegments that don't have a preroll phase. */
	struct arcan_shmif_initial initial;

/* The entire log mechanism is a bit dated, it was mainly for ARCAN_SHMIF_DEBUG
 * environment set, but forwarding that to stderr when we have a real channel
 * where it can be done, so this should be moved to the DEBUGIF mechanism */
	int log_event;

/* Previously this was passed as environment variables that we are gradually
 * moving away form. This is an opaque handle matching what the static build-
 * time keystore (currently only _naive which uses a directory tree). Using
 * device_node events can define this for us to pass on to arcan_net or used
 * for signing states that we want signed. */
	int keystate_store;

	bool valid_initial : 1;

/* "input" and "output" are poorly chosen names that stuck around for legacy,
 * but basically ENCODER segments receive buffer contents rather than send it. */
	bool output : 1;
	bool alive : 1;

/* By default, the 'pause' mechanism is a trigger for the server- side to
 * block in the calling thread into shmif functions until a resume- event
 * has been received */
	bool paused : 1;

/* When waiting for a descriptor to pair with an incoming event, if this is set
 * the next pairing will not be forwarded to the client but instead consumed
 * immediately. Main use is NEWSEGMENT for a forced DEBUG */
	bool autoclean : 1;

/* Track an 'alternate connection path' that the server can update with a call
 * to devicehint. A possible change here is for the alt_conn to be controlled
 * by the user via an environment variable */
	char* alt_conn;

/* The named key used to find the initial connection (if there is one) should
 * be unliked on use. For special cases (SHMIF_DONT_UNLINK) this can be deferred
 * and be left to the user. In these scenarios we need to keep the key around. */
	char* shm_key;

/* User- provided setup flags and segment types are kept / tracked in order
 * to re-issue events on a hard reset or migration */
	enum ARCAN_FLAGS flags;
	int type;
	enum shmif_ext_meta atype;
	uint64_t guid[2];

/* The ingoing and outgoing event queues */
	struct arcan_evctx inev;
	struct arcan_evctx outev;

/* Typically not used, but some multithreaded clients that need locking controls
 * have mutexes allocated and kept here, then we can log / warn / detect if a
 * resize or migrate call is performed when it is unsafe */
	pthread_mutex_t lock;
	bool in_lock, in_signal, in_migrate;
	pthread_t lock_id;
	pthread_t primary_id;

/* during automatic pause, we want displayhint and fonthint events to queue and
 * aggregate so we can return immediately on release, this pattern can be
 * re-used for more events should they be needed (possibly CLOCK..) */
	struct arcan_event dh, fh;
	int ph; /* bit 1, dh - bit 2 fh */

/* POSIX token passing is notoriously awful, in cases where we have to use the
 * socket descriptor passing mechanism, we need to pair the descriptor with the
 * corresponding event. This structure is used to track these states. */
	struct {
		bool gotev, consumed;
		bool handedover;
		arcan_event ev;
		file_handle fd;
	} pev;

/* When a NEWSEGMENT event has been provided (and descriptor- paired) the caller
 * still needs to map it via a normal _acquire call. If that doesn't happen, the
 * implementation of shmif is allowed to do whatever, thus we need to track the
 * data needed for acquire */
	struct {
		int epipe;
		char key[256];
	} pseg;

	char multipart[1024];
	size_t multipart_ofs;

	struct mstate mstate;

/* The 'guard' structure is used by a separate monitoring thread that will
 * track a pid or descriptor for aliveness. If the tracking fails, it will
 * unlock semaphores and trigger an at_exit- like handler. This is practically
 * necessary due to the poor multiplexation options for semaphores. */
	struct {
		bool active;

/* Fringe-wise, we need two DMSes, one set in shmpage and another using the
 * guard-thread, then both need to be checked after every semaphore lock */
		_Atomic bool local_dms;
		sem_handle semset[3];
		process_handle parent;
		int parent_fd;
		volatile uint8_t* _Atomic volatile dms;
		pthread_mutex_t synch;
		void (*exitf)(int val);
	} guard;
};
