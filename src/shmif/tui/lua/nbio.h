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
	bool eofm;
	bool lfstrip;
	off_t ofs;

	int fd; /* will be read from */

	size_t out_queued;
	size_t out_count;
	struct io_job* out_queue;
	struct io_job** out_queue_tail;

	intptr_t write_handler; /* callback when queue flushed */

	mode_t mode;
	char* unlink_fn;
	char* pending;

	bool data_rearmed;
	intptr_t data_handler; /* callback on_data_in */
	intptr_t ref; /* :self reference to block GC */

/* in line-buffered mode, this is used for input */
	char buf[4096];
};

/*
 * Add the metatable implementation for nonblockIO into a lua state,
 * as well as register hooks for job control.
 *
 * These hooks will be called whenever the implementation wants the
 * descriptor for an input or output stream to be added or removed for input
 * multiplexing. Map them to whatever poll-set is currently in use.
 *
 * Add or remove will be called individually for O_RDONLY and O_WRONLY
 * for a file that is both RW, with possibly different tags for each slot
 */
void alt_nbio_register(lua_State* ctx,
	bool (*add)(int fd, mode_t, intptr_t tag),
	bool (*remove)(int fd, mode_t, intptr_t* out)
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

/* mark the descriptor as non-blocking and close-on-exec */
void alt_nbio_nonblock_cloexec(int fd, bool socket);

/* connect to a domain socket, setting *out if a listening end is needed
 * for handling a DGRAM destination */
int alt_nbio_socket(const char* path, int ns, char** out);

/* The backing store is accepting new data, process buffer transfers and
 * update any possible queues / scheduled transfers. */
int alt_nbio_process_write(lua_State*, struct nonblock_io*);

void alt_nbio_data_in(lua_State*, intptr_t);
void alt_nbio_data_out(lua_State*, intptr_t);

/* Cancel / close / free all pending jobs. */
void alt_nbio_release();

/* Take ownership of a descriptor, bind to nbio and leave the userdata on top
 * of the stack of [L] - returns true if the import was successful, false if
 * not. If the import fails, the descriptor will still be closed.
 *
 * if unlink_fn is provided, the path will be unlinked when the object is
 * collected or closed. _import takes ownership of the string and will free it. */
bool alt_nbio_import(
	lua_State* L, int fd, mode_t mode, struct nonblock_io** dst,
	char** unlink_fn);

/* Manually close an imported nonblock_io, this is normally performed in the
 * Lua space directly or through the garbage collection */
int alt_nbio_close(lua_State* L, struct nonblock_io** ibb);

#endif
