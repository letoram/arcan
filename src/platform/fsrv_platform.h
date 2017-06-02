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

/*
 * Setup a frameserver that is idle until an external party connects through a
 * listening socket using [key], then behaves as an avfeed- style frameserver.
 * The optional [auth] requires an authentication password before permitting a
 * client to connect. Set [fd] to something other than BADFD(-1) if you have a
 * prepared socket to use (typically in the case of adoption handover during
 * pending listen).
 *
 * To process the resulting arcan_frameserver context, you should first
 * periodically run arcan_frameserver_socketpoll() until it returns 0 or
 * -1 with EBADF as errno. On EBADF, the connection point has been consumed
 * and you need to re-allocate.
 *
 * Afterwards, even if you didn't set an auth- key, you should repeat the
 * process with arcan_frameserver_socketauth(), with the same kind of error
 * handling.
 *
 * When both these steps have been completed successfully, the frameserver
 * is up and running to the point where normal event processing is working.
 */
struct arcan_frameserver* arcan_frameserver_listen_external(
	const char* key, const char* auth, int fd, mode_t mode);

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
int arcan_frameserver_resynch(struct arcan_frameserver* src);

/*
 * Allocate a new frameserver segment, bind it to the same process
 * and communicate the necessary IPC arguments (key etc.) using
 * the pre-existing eventqueue of the frameserver controlled by (ctx)
 */
struct arcan_frameserver* arcan_frameserver_spawn_subsegment(
	struct arcan_frameserver* ctx, int ARCAN_SEGID,
	int hintw, int hinth, int tag);

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
int arcan_frameserver_socketpoll(struct arcan_frameserver* src);

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
int arcan_frameserver_socketauth(struct arcan_frameserver* src);

/*
 * Act as a criticial section, with jmp_buf being invocated on significant
 * but recoverable errors. Use _enter/_leave when accessing the shared
 * memory parts of _frameserver internals.
 */
#include <setjmp.h>
void arcan_frameserver_enter(struct arcan_frameserver*, jmp_buf ctx);
void arcan_frameserver_leave();

/*
 * disconnect, clean up resources, free. The connection should be considered
 * alive (not just _alloc call) or it will return false. State of *src is
 * undefined after this call (will be free:d)
 */
bool arcan_frameserver_destroy(struct arcan_frameserver* src);

/*
 * Allocate shared and heap memory, reset all members to an empty state and
 * then enforce defaults, returns NULL on failure.  You rarely need to access
 * this yourself, the _listen_external, spawn_subsegment and simiar functions
 * do this for you.
 */
struct arcan_frameserver* arcan_frameserver_alloc();

/*
 * Update the static / shared default audio buffer size that is provided if
 * the client doesn't request a specific one. Returns the previous value.
 */
size_t arcan_frameserver_default_abufsize(size_t new_sz);

/*
 * Update the number of permitted displays for frameservers that have been
 * given access to the color ramp subprotocol.
 */
size_t arcan_frameserver_display_limit(size_t new_sz);

/*
 * Release any shared memory resources associated with the frameserver
 */
void arcan_frameserver_dropshared(struct arcan_frameserver* ctx);
#endif
