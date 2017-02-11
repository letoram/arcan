/*
 * some insane mapping size (mb), just overcommit and truncate
 */
#define MAX_IMAGE_BUFFER_SIZE 32

/* mmaped block for write-out */
struct img_data {
	bool ready;
	size_t buf_sz;
	int w,h;
	int x,y;
	uint8_t _Alignas(64) buf[];
};

/* container for fork-load img */
struct img_state {
/* SETUP_SET */
	const char* fname;
	bool is_stdin;

/* SETUP_GET */
	bool broken;
	size_t buf_lim;
	pid_t proc;
	volatile struct img_data* out;
};

/*
 * fork() into an img- loader process that builds/populates img_state.
 * only keep one [is_stdin=true] pending at a time (else they fight eachother)
 *
 * returns false if we couldn't spawn a new process
 * (out of memory, file descriptors or pids)
 */
bool imgload_spawn(struct arcan_shmif_cont* con, struct img_state* tgt);

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
