#ifndef _HAVE_ARCAN_FRAMESERVER
#define _HAVE_ARCAN_FRAMESERVER

/*
 * possible archetype slots
 */
int arcan_frameserver_decode_run(struct arcan_shmif_cont*, struct arg_arr*);
int arcan_frameserver_encode_run(struct arcan_shmif_cont*, struct arg_arr*);
int arcan_frameserver_remoting_run(struct arcan_shmif_cont*, struct arg_arr*);
int arcan_frameserver_libretro_run(struct arcan_shmif_cont*, struct arg_arr*);
int arcan_frameserver_terminal_run(struct arcan_shmif_cont*, struct arg_arr*);
int arcan_frameserver_avfeed_run(struct arcan_shmif_cont*, struct arg_arr*);
int arcan_frameserver_net_client_run(struct arcan_shmif_cont*, struct arg_arr*);
int arcan_frameserver_net_server_run(struct arcan_shmif_cont*, struct arg_arr*);

#define LOG(...) (fprintf(stderr, __VA_ARGS__))
/* resolve 'resource', open and try to store it in one buffer,
 * possibly memory mapped, avoid if possible since the parent may
 * manipulate the frameserver file-system namespace and access permissions
 * quite aggressively */
void* frameserver_getrawfile(const char* resource, ssize_t* ressize);

/* similar to above, but use a preopened file-handle for the operation */
void* frameserver_getrawfile_handle(file_handle, ssize_t* ressize);

bool frameserver_dumprawfile_handle(const void* const sbuf, size_t ssize,
	file_handle, bool finalize);

/* block until parent has supplied us with a
 * file_handle valid in this process */
file_handle frameserver_readhandle(struct arcan_event*);

/* store buf in handle pointed out by file_handle,
 * ressize specifies number of bytes to store */
int frameserver_pushraw_handle(file_handle, void* buf, size_t ressize);

/* set currently active library for loading symbols */
bool frameserver_loadlib(const char* const);

/* look for a specific symbol in the current library (frameserver_loadlib),
 * or, if module == false, the global namespace (whatever that is) */
void* frameserver_requirefun(const char* const sym, bool module);

#endif
