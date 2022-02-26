#ifndef HAVE_ALT_NBIO

#ifndef LUACTX_OPEN_FILES
#define LUACTX_OPEN_FILES 64
#endif

struct io_job;
struct io_job {
	char* buf;
	size_t sz;
	size_t ofs;
	struct io_job* next;
};

struct nonblock_io {
/* in line-buffered mode, this is used for input */
	char buf[4096];
	bool eofm;
	bool lfstrip;
	off_t ofs;

	int fd; /* will be read from */

	struct io_job* out_queue;
	intptr_t write_handler; /* callback when queue flushed */

	mode_t mode;
	char* unlink_fn;
	char* pending;

	bool data_rearmed;
	intptr_t data_handler; /* callback on_data_in */
	intptr_t ref; /* :self reference to block GC */
};

/*
 * Add the metatable implementation for nonblockIO into a lua state,
 * as well as register hooks for job control.
 *
 * These hooks will be called whenever the implementation wants the a
 * descriptor for an input or output stream to be added or removed for input
 * multiplexing. Map them to whatever poll-set is currently in use.
 */
void alt_nbio_register(lua_State* ctx,
	bool (*add)(int fd, mode_t, intptr_t tag),
	bool (*remove)(int fd, intptr_t* out)
);

/*
 * Read and forward inbound data from the referenced nonblock_io struct into
 * its respective handler. the 'nonbuf' state indicates if line-buffering is
 * desired.
 *
 * If line-buffering is set, the type of the top argument will determine
 * the line processing behaviour:
 *
 *  table    : append (n-indexed)
 *  function : callback(line, eof)
 *  else     : return line, alive
 *
 * The object property lfstrip will provide the strings without linefeeds
 * if set. This is to reduce excessive copying / postprocessing.
 */
int alt_nbio_process_read(
	lua_State*, struct nonblock_io*, bool nonbuf);

/*
 * Normally part of the Lua-side API for resolving a resource string to a
 * file, socket or pipe - as well as configuring input modes and callback
 * handlers.
 *
 * This will return a valid file-descriptor or -1 on error.
 */
int alt_nbio_open(lua_State*);

/* The backing store is accepting new data, process buffer transfers and
 * update any possible queues / scheduled transfers. */
int alt_nbio_process_write(lua_State*, struct nonblock_io*);

void alt_nbio_data_in(lua_State*, intptr_t);
void alt_nbio_data_out(lua_State*, intptr_t);

/* Cancel / close / free all pending jobs. */
void alt_nbio_release();

/* Take ownership of a descriptor, bind to nbio and leave the userdata on top
 * of the stack of [L] - returns true if the import was successful, false if
 * not. If the import fails, the descriptor will still be closed. */
bool alt_nbio_import(lua_State* L, int fd, mode_t mode, struct nonblock_io** dst);

/* Manually close an imported nonblock_io, this is normally performed in the
 * Lua space directly or through the garbage collection */
int alt_nbio_close(lua_State* L, struct nonblock_io** ibb);

#endif
