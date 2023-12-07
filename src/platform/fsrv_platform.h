/*
 * Copyright 2014-2017, Björn Ståhl
 * License: 3-Clause BSD, see COPYING file in arcan source repository.
 * Reference: http://arcan-fe.com
 * Description: This header covers the platform part of frameserver management,
 * and act as a backend to both the engine/arcan_frameserver and the
 * shmif/arcan_shmif_server libraries.
 */
#ifndef HAVE_FSRV_PLATFORM_HEADER
#define HAVE_FSRV_PLATFORM_HEADER
#include <sys/stat.h>
/*
 * Setup a frameserver that is idle until an external party connects through a
 * listening socket using [key], then behaves as an avfeed- style frameserver.
 * The optional [auth] requires an authentication password before permitting a
 * client to connect. Set [fd] to something other than BADFD(-1) if you have a
 * prepared socket to use (typically in the case of adoption handover during
 * pending listen).
 *
 * To process the resulting arcan_frameserver context, you should first
 * periodically run platform_fsrv_socketpoll() until it returns 0 or
 * -1 with EBADF as errno. On EBADF, the connection point has been consumed
 * and you need to re-allocate.
 *
 * Afterwards, even if you didn't set an auth- key, you should repeat the
 * process with platform_fsrv_socketauth(), with the same kind of error
 * handling.
 *
 * When both these steps have been completed successfully, the frameserver
 * is up and running to the point where normal event processing is working.
 */
struct arcan_event;
struct arcan_frameserver* platform_fsrv_listen_external(
	const char* key, const char* auth,	int fd, mode_t mode,
	size_t w, size_t h, uintptr_t tag);

/*
 * Build a frameserver context that can be used either in-process or forwarded
 * to a new process. Note that this will only prepare the context and resources
 * not control how connection primitives are transmitted, hence why the client
 * end of the socket is passed in [clsocket].
 *
 * NOTE: This socket is set to NONBLOCK and CLOSE_ON_EXEC.
 */
struct arcan_frameserver* platform_fsrv_spawn_server(
	int segid, size_t w, size_t h, uintptr_t tag, int* clsocket);

/*
 * Build a frameserver over an existing client socket, this will be in a
 * preauthenticated/preconnected state. It works similar to platform_
 * fsrv_spawn_server excluding the bind/listen and need for poll to change to a
 * connected state.
 */
struct arcan_frameserver* platform_fsrv_preset_server(
	int sockin, int segid, size_t w, size_t h, uintptr_t tag);

/*
 * perform a resynchronization (resize) operation where negotiated buffer
 * buffer counts, formats and possible substructures are reset.
 *
 * returns:
 *-1 if the backing store was corrupted, couldn't be mapped or invalid,
 * 0 if no changes are committed or the following bitmap:
 * 1 - backing store was resized / remapped
 * 2 - subprotocol state was reset
 */
int platform_fsrv_resynch(struct arcan_frameserver* src);

/*
 * Allocate a new frameserver segment, bind it to the same process and
 * communicate the necessary IPC arguments (key etc.) using the pre-existing
 * eventqueue of the frameserver controlled by (ctx).
 *
 * [hints] correspond to any segment content hints provided by the client
 * in the corresonding NEWSEGMENT request or hints on rendering defined by
 * the server side in a push setup.
 *
 * [hintw, hinth] ultimately comes from the window manager
 *
 * [tag] is a caller defined pointer- or virtual- VM resource reference
 * for pairing the context to some other resource.
 *
 * [reqid] corresponds to the identifier provided by the client in a
 * NEWSEGMENT request, or 0 if the allocation is server-initiated.
 *
 * If all hints correspond to expectations, the segment should be working
 * without any round-trips.
 */
struct arcan_frameserver* platform_fsrv_spawn_subsegment(
	struct arcan_frameserver* ctx, int ARCAN_SEGID, int hints,
	size_t hintw, size_t hinth, uintptr_t tag, uint32_t reqid);

/*
 * Used with a pending external connection where the socket has been bound
 * but no connections have been accepted yet. Will return -1 and set errno
 * to:
 *
 * EBADF - socket died or connection error, explicit restart required
 * EAGAIN - no client, try again later.
 *
 * or 0 and set src->dpipe in the case of a successful connection..
 */
int platform_fsrv_socketpoll(struct arcan_frameserver* src);

/*
 * Wait until an (optional) key based authentication session has been passed.
 * when authentication has been completed, this function will send the
 * necessary shm-mapping primitives.
 *
 * Return 0 on completion, or -1 and set errno to:
 *
 * EBADF - socket died or authentication error, explicit restart required
 * EAGAIN - need more data to authenticate, try again later.
 */
int platform_fsrv_socketauth(struct arcan_frameserver* src);

/*
 * Act as a criticial section, with jmp_buf being invocated on significant
 * but recoverable errors. Use _enter/_leave when accessing the shared
 * memory parts of _frameserver internals.
 */
#include <setjmp.h>
void platform_fsrv_enter(struct arcan_frameserver*, jmp_buf ctx);
void platform_fsrv_leave(void);
size_t platform_fsrv_clock(void);

/*
 * disconnect, clean up resources, free. The connection should be considered
 * alive (not just _alloc call) or it will return false. State of *src is
 * undefined after this call (will be free:d)
 */
bool platform_fsrv_destroy(struct arcan_frameserver* src);

/*
 * clean up in-process resources only - this is for the edge condition where
 * you have forked and wish the connection to be alive inside of the child
 */
bool platform_fsrv_destroy_local(struct arcan_frameserver* src);

/*
 * Allocate shared and heap memory, reset all members to an empty state and
 * then enforce defaults, returns NULL on failure.  You rarely need to access
 * this yourself, the _listen_external, spawn_subsegment and simiar functions
 * do this for you.
 */
struct arcan_frameserver* platform_fsrv_alloc(void);

/*
 * copy the supplied event to outgoing queue of the frameserver. If the event
 * is also bound to a file descriptor, the platform_fsrv_pushfd function
 * should be used in stead.
 */
int platform_fsrv_pushevent(struct arcan_frameserver*, struct arcan_event*);

/*
 * Determine if the connected end is still alive or not,
 * this is treated as a poll -> state transition
 */
bool platform_fsrv_validchild(struct arcan_frameserver*);

/*
 * similar to pushevent, but used when there is a descriptor that should be
 * paired with the event.
 */
int platform_fsrv_pushfd(struct arcan_frameserver*, struct arcan_event*, int);

/*
 * Update the static / shared default audio buffer size that is provided if
 * the client doesn't request a specific one. Returns the previous value.
 */
size_t platform_fsrv_default_abufsize(size_t new_sz);

/*
 * Update the number of permitted displays for frameservers that have been
 * given access to the color ramp subprotocol.
 */
size_t platform_fsrv_display_limit(size_t new_sz);

/*
 * Try and populate [dst] with the contents of the frameserver last words.
 * Requires [n] > 0 and sizeof(dst) to be at least [n].
 */
bool platform_fsrv_lastwords(struct arcan_frameserver*, char* dst, size_t n);

/*
 * Release any shared memory resources associated with the frameserver
 */
void platform_fsrv_dropshared(struct arcan_frameserver* ctx);
#endif
