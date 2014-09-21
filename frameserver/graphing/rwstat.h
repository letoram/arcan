/*
 * RW-Stat, packing transfer statistics into an Arcan-shmif buffer
 * for unpacking/rendering by an appl- side shader.
 *
 * It works by attaching monitoring inputs,
 * where each input represents a single source descriptor (or memcpy etc.)
 * that is populated with data using the built-in callbacks.
 *
 * Each channel occupies [4 rows] and will be binned to the width of the
 * shared segment (256-width minimum). Data in sizes / histogram are
 * stored as base-256 (LSB to MSB: A, R, G, B).
 *
 * Row [0] : transfer sizes
 * Row [1] : histogram
 * Row [2] : signal
 * Row [3] : patterns
 *
 * Channel-access is thread-safe
 */

static const int rwstat_row_ch = 5;

/*
 * row offsets
 */
enum rwstat_datarow {
	RW_DATA_SZ   = 0,
	RW_HISTOGRAM = 1,
	RW_SIGNAL    = 2,
	RW_PATTERN   = 3
};

/*
 * options that control channel behavior
 */
enum RWSTAT_CHOPTS {
	RWSTAT_CH_SYNCHRONOUS = 1,     /* buffers will only slide on clock ticks      */
	RWSTAT_CH_HISTOGRAM_GLOBAL = 2 /* histogram values will not be reset on ticks */
};

struct rwstat_ch {
	void (*ch_data)(struct rwstat_ch*, uint8_t* buf, size_t buf_sz);
	void (*ch_signal)(struct rwstat_ch*, uint32_t col, uint8_t ind);

	size_t bytes_in;
	size_t bytes_out;

	struct rwstat_ch_priv* priv;
};

/*
 * take control over dst (i.e. resize to fitting sizes)
 */
struct rwstat_ctx* rwstat_create(struct arcan_shmif_cont dst);

/*
 * create a new channel, may impose a segment resize
 * (hence blocking until acknowledged)
 */
struct rwstat_ch* rwstat_addch(struct rwstat_ctx*, enum RWSTAT_CHOPTS);
void rwstat_dropch(struct rwstat_ctx* ctx, struct rwstat_ch** src_ch);

/*
 * Add a byte-sequence to scan for, if found, signal[ind] will
 * be invoked. buf will be *copied* and the copy managed internally.
 *
 * To drop patterns, drop and rebuild the entire channel.
 */
bool rwstat_addpattern(struct rwstat_ch*,
	uint8_t slot, uint32_t col, void* buf, size_t sz);

/*
 * Drop channels (and if shmif_dealloc is set, close the
 * arcan connection for the segment).
 *
 * *ctx will be overwritten with NULL.
 */
void rwstat_free(struct rwstat_ctx**, bool shmif_dealloc);

/*
 * Specify a clock-tick for synchronous channels
 */
void rwstat_tick(struct rwstat_ctx*);
