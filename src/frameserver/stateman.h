/*
 * Setup state- tracking,
 * state_sz defines block size
 * limit sets upper memory bounds in frames (limit( < 0)) or bytes
 * when reached, new frames will be added at the cost of old ones.
 */
struct stateman_ctx* stateman_setup(size_t state_sz,
	ssize_t limit, int precision);

/*
 * Attach a new state at the end of the current,
 * If timestamp is not monotonic, subsequent states will be pruned
 * This handles the situation where new states are created as a
 * branch after seeking backwards.
 */
void stateman_feed(struct stateman_ctx*, int tstamp, void* inbuf);

/*
 * Reconstruct the state closest to, timestamp. If Rel is set,
 * tstamp moves backward from the latest entry.
 */
bool stateman_seek(struct stateman_ctx*, void* dstbuf, int tstamp, bool rel);

/*
 * Drop a previously allocated staterecord
 */
void stateman_drop(struct stateman_ctx**);
