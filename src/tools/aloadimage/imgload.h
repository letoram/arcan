/*
 * some insane mapping size (mb), just overcommit and truncate
 */
extern int image_size_limit_mb;

/*
 * if we happen to link with libcs or parsers that break the current
 * set of filters, it helps setting this to help figure things out
 */
extern bool disable_syscall_flt;

/* mmaped block for write-out */
struct img_data {
	bool ready, animated, vector;
	size_t buf_sz;
	int w,h;
	int x,y;
	uint8_t msg[48];
	uint8_t _Alignas(64) buf[];
};

/* container for fork-load img */
struct img_state {
/* SETUP_SET */
	const char* fname;
	int fd;
	int sigfd;
	bool is_stdin;
	int life;
	float density;
	bool stereo_right;

/* SETUP_GET */
	bool broken;
	size_t buf_lim;
	pid_t proc;
	uint8_t msg[48];
	volatile struct img_data* out;
};

void debug_message(const char*, ...);

/*
 * fork() into an img- loader process that builds/populates img_state.
 * only keep one [is_stdin=true] pending at a time (else they fight eachother)
 *
 * the [prio_d] can be used to set the priority of the new process
 *
 * returns false if we couldn't spawn a new process
 * (out of memory, file descriptors or pids)
 */
bool imgload_spawn(struct arcan_shmif_cont*, struct img_state*, int prio_d);

/*
 * Check if [tgt] has finished working, set timeout to wait/kill if the task
 * is not finished within [timeout] miliseconds.
 *
 * returns [true] if [tgt] has terminated and was collected, [false] otherwise.
 */
bool imgload_poll(struct img_state* tgt);

/*
 * Drop the resources bound to an imgload_spawn call, if the decode process
 * hasn't finished, it will be killed off.
 */
void imgload_reset(struct img_state* tgt);
