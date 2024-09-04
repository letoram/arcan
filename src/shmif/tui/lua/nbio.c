/*
 * Copyright: Björn Ståhl
 * License: BSDv3, see COPYING file in arcan source repsitory.
 * Reference: https://arcan-fe.com
 * Description:
 * This is vendored from arcan/src/engine/alt/nbio* with the WANT_ARCAN_BASE
 * parts left out as those require frameserver (=external process control).
 * That should eventually be provided, but in a simplified form that
 * supports handling TUI clients specifically.
 * The tui_nbio_local pulls in stubbed / simplified implementations of
 * allocation/tracing and namespace lookup functions.
 */
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <ctype.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/un.h>
#include <sys/poll.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "nbio.h"
#include "nbio_local.h"

#if LUA_VERSION_NUM == 501
	#define lua_rawlen(x, y) lua_objlen(x, y)
#endif

#ifdef WANT_ARCAN_BASE
#define arcan_fatal(...) do { alt_fatal( __VA_ARGS__); } while(0)
#endif

static struct nonblock_io open_fds[LUACTX_OPEN_FILES];
/* open_nonblock and similar functions need to register their fds here as they
 * are force-closed on context shutdown, this is necessary with crash recovery
 * and scripting errors. The limit is set based on the same open limit imposed
 * by arcan_event_ sources. */
static bool (*add_job)(int fd, mode_t mode, intptr_t tag);
static bool (*remove_job)(int fd, mode_t mode, intptr_t* out);
static void (*trigger_error)(lua_State* L, int fd, intptr_t tag, const char*);

static bool lookup_registry(lua_State* L, intptr_t tag, int type, const char* src)
{
	lua_rawgeti(L, LUA_REGISTRYINDEX, tag);
	if (lua_type(L, -1) != type){
		trigger_error(L, -1, tag, src);

		lua_pop(L, 1);
		return false;
	}
	return true;
}

static void unref_registry(lua_State* L, intptr_t tag, int type, const char* src)
{
#ifdef _DEBUG
	if (lookup_registry(L, tag, type, src)){
		lua_pop(L, 1);
	}
	else
		return;
#endif
	luaL_unref(L, LUA_REGISTRYINDEX, tag);
}

void alt_nbio_nonblock_cloexec(int fd, bool socket)
{
#ifdef __APPLE__
	if (socket){
		int val = 1;
		setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &val, sizeof(int));
	}
#endif

	int flags = fcntl(fd, F_GETFL);
	if (-1 != flags)
		fcntl(fd, F_SETFL, flags | O_NONBLOCK);

	if (-1 != (flags = fcntl(fd, F_GETFD)))
		fcntl(fd, F_SETFD, flags | FD_CLOEXEC);
}

/* this symbol comes parasitically with arcan-shmif and used inside the tui
 * implementation, thus it is not particularly nice to rely on it - on the
 * other hand vendoring in the code is also annoying */
extern unsigned long long arcan_timemillis();

static bool ensure_flush(lua_State* L, struct nonblock_io* ib, size_t timeout)
{
	bool rv = true;
	struct pollfd fd = {
		.fd = ib->fd,
		.events = POLLOUT | POLLERR | POLLHUP | POLLNVAL
	};

/* since poll doesn't give much in terms of feedback across calls some crude
 * timekeeping is needed to make sure we don't exceed a timeout by too much */
	unsigned long long current = arcan_timemillis();
	int status;

/* writes can fail.. */
	while ((status = alt_nbio_process_write(L, ib)) == 0){

		if (timeout > 0){
			unsigned long long now = arcan_timemillis();
			if (now > current)
				timeout -= now - current;
			current = now;

			if (timeout <= 0){
				rv = false;
				break;
			}
		}

/* dst can die while waiting for write-state */
		int rv = poll(&fd, 1, timeout);

		if (-1 == rv && (errno == EAGAIN || errno == EINTR))
				continue;

		if (fd.revents & (POLLERR | POLLHUP | POLLNVAL)){
			rv = false;
			break;
		}
	}

	if (status < 0)
		rv = false;

	return rv;
}

static int connect_trypath(const char* local, const char* remote, int type)
{
/* always the risk of this expanding to something too large as well, fsck
 * the socket api design, really. So first bind to the local path */
	int fd = socket(AF_UNIX, type, 0);
	if (-1 == fd)
		return fd;

	struct sockaddr_un addr_local = {
		.sun_family = AF_UNIX
	};
	snprintf(addr_local.sun_path, COUNT_OF(addr_local.sun_path), "%s", local);
	struct sockaddr_un addr_remote = {
		.sun_family = AF_UNIX
	};
	snprintf(addr_remote.sun_path, COUNT_OF(addr_remote.sun_path), "%s", remote);

	int rv = bind(fd, (struct sockaddr*) &addr_local, sizeof(addr_local));
	if (-1 == rv){
		close(fd);
		return -1;
	}

/* the other option here is to allow the allocation to go through and treat
 * it as a 'reconnect on operation' in order to deal with normal failures
 * during connection as well, but start conservative */
	alt_nbio_nonblock_cloexec(fd, true);

	if (-1 == connect(fd, (struct sockaddr*) &addr_remote, sizeof(addr_remote))){
		unlink(local);
		close(fd);
		return -1;
	}

	return fd;
}

int alt_nbio_socket(const char* path, int ns, char** out)
{
/* we still need to bind a path that we can then unlink after connection */
	char* local_path = NULL;
	int retry = 3;

/* find a temporary name to use in the appl-temp namespace, with a fail
 * retry counter to counteract the rare collision vs. permanent problem */
	do {
		char tmpname[32];
		long rnd = random();
		snprintf(tmpname, sizeof(tmpname), "/tmp/_sock%ld_%d", rnd, getpid());
		char* tmppath = arcan_find_resource(tmpname, ns, ARES_FILE, NULL);
		if (!tmppath){
			local_path = arcan_expand_resource(tmpname, ns);
		}
		else
			free(tmppath);
	} while (!local_path && retry--);

	if (!local_path)
		return -1;

/* This should eventually respect IPC marked user defined namespaces,
 * as it might be useful for some other things - wpa_supplicant like
 * application interfaces being one example. If so, the namespace.c
 * prefix check function should be reused and explicitly resolve the
 * ns prefix to see it supports it. */
	int fd = connect_trypath(local_path, path, SOCK_STREAM);

/* so it might be a dgram socket */
	if (-1 == fd){
		if (errno == EPROTOTYPE){
			fd = connect_trypath(local_path, path, SOCK_DGRAM);
		}
		if (-1 == fd){
			unlink(local_path);
			arcan_mem_free(local_path);
		}
/* and if it is, we need to defer unlinking or the other side can't respond */
		else {
			*out = local_path;
		}
	}
	else {
		unlink(local_path);
		arcan_mem_free(local_path);
	}

	return fd;
}

int alt_nbio_process_write(lua_State* L, struct nonblock_io* ib)
{
	struct io_job* job = ib->out_queue;

	while (job){
		ssize_t nw = write(ib->fd, &job->buf[job->ofs], job->sz - job->ofs);
		if (-1 == nw){
			if (errno == EINTR || errno == EAGAIN)
				return 0;
			return -1;
		}

		job->ofs += nw;
		ib->out_count += nw;

/* slide on completion */
		if (job->ofs == job->sz){
			ib->out_queued -= job->sz;
			ib->out_queue = job->next;
			arcan_mem_free(job->buf);
			arcan_mem_free(job);
			job = ib->out_queue;

/* edge case, all jobs have been finished and the tail is dropped */
			if (!job)
				ib->out_queue_tail = &ib->out_queue;
		}
	}

/* when no more jobs, return true -> trigger callback */
	return 1;
}

static void drop_all_jobs(struct nonblock_io* ib)
{
	struct io_job* job = ib->out_queue;
	while (job){
		struct io_job* cur = job;
		job = job->next;
		arcan_mem_free(cur->buf);
		arcan_mem_free(cur);
	}
	ib->out_queue = NULL;
	ib->out_queue_tail = &(ib->out_queue);
	ib->out_queued = 0;
	ib->out_count = 0;
}

static struct io_job* queue_out(struct nonblock_io* ib, const char* buf, size_t len)
{
	struct io_job* res = malloc(sizeof(struct io_job));
	if (!res)
		return NULL;

/* prepare new write job */
	*res = (struct io_job){0};
	res->buf = malloc(len);
	if (!res->buf){
		free(res);
		return NULL;
	}

/* copy out so lua can drop the buffer */
	memcpy(res->buf, buf, len);
	res->sz = len;
	ib->out_queued += len;

/* remember tail so next queue is faster */
	if (!ib->out_queue_tail){
		ib->out_queue_tail = &ib->out_queue;
	}

/* append and step tail */
	*(ib->out_queue_tail) = res;
	ib->out_queue_tail = &(res->next);

	return res;
}

int alt_nbio_close(lua_State* L, struct nonblock_io** ibb)
{
	struct nonblock_io* ib = *ibb;
	int fd = ib->fd;
	if (fd > 0)
		close(fd);

/* another safety option would be to have a rename_lock and rename_to stage for
 * atomic commit / swap on close to avoid possible partial outputs from queued
 * data handlers */
	if (ib->unlink_fn){
		unlink(ib->unlink_fn);
		arcan_mem_free(ib->unlink_fn);
	}

	free(ib->pending);
	drop_all_jobs(ib);

	if (ib->data_handler != LUA_NOREF){
		unref_registry(L, ib->data_handler, LUA_TFUNCTION, "nbio_close_dh");
		ib->data_handler = LUA_NOREF;
	}

	if (ib->write_handler != LUA_NOREF){
		unref_registry(L, ib->write_handler, LUA_TFUNCTION, "nbio_close_wh");
		ib->write_handler = LUA_NOREF;
	}

/* no-op if nothing registered */
	intptr_t tag;
	if (remove_job(fd, O_RDONLY, &tag)){
		unref_registry(L, tag, LUA_TUSERDATA, "nbio_close_rdmeta");
	}
	if (remove_job(fd, O_WRONLY, &tag)){
		unref_registry(L, tag, LUA_TUSERDATA, "nbio_close_wrmeta");
	}

	free(ib);
	*ibb = NULL;

/* remove the entry, close will be called from nbio_close, and any current
 * event handlers and triggers will be removed through drop_all_jobs */
	for (size_t i = 0; i < LUACTX_OPEN_FILES; i++){
		if (open_fds[i].fd == fd){
			open_fds[i] = (struct nonblock_io){
				.data_handler = LUA_NOREF,
				.write_handler = LUA_NOREF
			};
			break;
		}
	}

	return 0;
}

/*
 * same function, just different lookup strings for the Lua- udata types
 */
static int nbio_closer(lua_State* L)
{
	LUA_TRACE("open_nonblock:close");
	struct nonblock_io** ib = luaL_checkudata(L, 1, "nonblockIO");
	if (!(*ib))
		LUA_ETRACE("open_nonblock:close", "already closed", 0);

/* arbitrary timeout though we should not really hit this and the alternatives
 * are all practically worse - the only other 'saving' grace' would be to fire
 * the job in its own thread or fork() and let it timeout or die .. */
	ensure_flush(L, *ib, 1000);
	alt_nbio_close(L, ib);

	LUA_ETRACE("open_nonblock:close", NULL, 0);
}

static int nbio_datahandler(lua_State* L)
{
	LUA_TRACE("open_nonblock:data_handler");
	struct nonblock_io** ib = luaL_checkudata(L, 1, "nonblockIO");
	if (!(*ib))
		LUA_ETRACE("open_nonblock:data_handler", "already closed", 0);

/* always remove the last known handler refs */
	if ((*ib)->data_handler != LUA_NOREF){
		unref_registry(L, (*ib)->data_handler, LUA_TFUNCTION, "nbio-dh-reset");
		(*ib)->data_handler = LUA_NOREF;
	}

/* tracking to ensure that we detect nbio_data_in -> cb ->data_handler */
	(*ib)->data_rearmed = true;

/* the same goes for the reference used to tag events */
	intptr_t out;
	if (remove_job((*ib)->fd, O_RDONLY, &out)){
		unref_registry(L, out, LUA_TUSERDATA, "nbio-rdonly-meta-reset");
	}

/* update the handler field in ib, then we get the reference to ib and
 * send to the source - but also remove any previous one */
	if (lua_type(L, 2) == LUA_TFUNCTION){
		intptr_t ref = luaL_ref(L, LUA_REGISTRYINDEX);
		(*ib)->data_handler = ref;

/* now get the reference to the userdata and attach that to the event-source,
 * this is so that we can later trigger on the event and access the userdata */
		ref = luaL_ref(L, LUA_REGISTRYINDEX);

/* luaL_ pops the stack so make sure it is balanced */
		lua_pushvalue(L, 1);
		lua_pushvalue(L, 1);

/* the job can fail to queue if a set amount of read_handler descriptors
 * are exceeded */
		if (!add_job((*ib)->fd, O_RDONLY, ref)){
			unref_registry(L, ref, LUA_TUSERDATA, "nbio-rdonly-meta-fail");
			lua_pushboolean(L, false);
		}

		lua_pushboolean(L, true);

		return 1;
	}
	else if (lua_type(L, 2) == LUA_TNIL){
/* do nothing */
	}
	else {
		arcan_fatal("open_nonblock:data_handler "
			"argument error, expected function or nil");
	}

	lua_pushboolean(L, true);
	return 1;
}

static int nbio_socketclose(lua_State* L)
{
	LUA_TRACE("open_nonblock:close");
	struct nonblock_io** ib = luaL_checkudata(L, 1, "nonblockIOs");
	if (!(*ib))
		LUA_ETRACE("open_nonblock:close", "already closed", 0);

	alt_nbio_close(L, ib);
	LUA_ETRACE("open_nonblock:close", NULL, 0);
}

static int nbio_socketaccept(lua_State* L)
{
	LUA_TRACE("open_nonblock:accept");

	struct nonblock_io** ib = luaL_checkudata(L, 1, "nonblockIOs");
	if (!(*ib))
		LUA_ETRACE("open_nonblock:accept", "already closed", 0);

	struct nonblock_io* is = *ib;
	int newfd = accept(is->fd, NULL, NULL);
	if (-1 == newfd)
		LUA_ETRACE("open_nonblock:accept", NULL, 0);

	int flags = fcntl(newfd, F_GETFL);
	if (-1 != flags)
		fcntl(newfd, F_SETFL, flags | O_NONBLOCK);

	if (-1 != (flags = fcntl(newfd, F_GETFD)))
		fcntl(newfd, F_SETFD, flags | FD_CLOEXEC);

	struct nonblock_io* conn = arcan_alloc_mem(
		sizeof(struct nonblock_io), ARCAN_MEM_BINDING, 0, ARCAN_MEMALIGN_NATURAL);

	(*conn) = (struct nonblock_io){
		.fd = newfd,
		.mode = O_RDWR,
		.data_handler = LUA_NOREF,
		.write_handler = LUA_NOREF,
		.lfch = '\n'
	};

	if (!conn){
		close(newfd);
		LUA_ETRACE("open_nonblock:accept", "out of memory", 0);
	}

	uintptr_t* dp = lua_newuserdata(L, sizeof(uintptr_t));
	if (!dp){
		close(newfd);
		arcan_mem_free(conn);
		LUA_ETRACE("open_nonblock:accept", "couldn't alloc UD", 0);
	}

	*dp = (uintptr_t) conn;
	luaL_getmetatable(L, "nonblockIO");
	lua_setmetatable(L, -2);
	LUA_ETRACE("open_nonblock:accept", NULL, 1);
}

static int nbio_writequeue(lua_State* L)
{
	LUA_TRACE("open_nonblock:writequeue");
	struct nonblock_io** ib = luaL_checkudata(L, 1, "nonblockIO");
	if (!(*ib)){
		lua_pushnumber(L, 0);
		lua_pushnumber(L, 0);
		LUA_ETRACE("open_nonblock:writequeue", "already closed", 2);
	}

	struct nonblock_io* iw = *ib;
	if (!iw->out_queue){
		lua_pushnumber(L, 0);
		lua_pushnumber(L, 0);
	}
	else {
		lua_pushnumber(L, iw->out_count);
		lua_pushnumber(L, iw->out_queued);
	}

	LUA_ETRACE("open_nonblock:writequeue", NULL, 2);
}

static int nbio_write(lua_State* L)
{
	LUA_TRACE("open_nonblock:write");
	struct nonblock_io** ud = luaL_checkudata(L, 1, "nonblockIO");
	struct nonblock_io* iw = *ud;

	if (!iw)
		LUA_ETRACE("open_nonblock:close", "already closed", 0);

	if (iw->mode == O_RDONLY)
		LUA_ETRACE("open_nonblock:write", "invalid mode (r) for write", 0);

	size_t len = 0;
	const char* buf = NULL;

	if (lua_type(L, 2) == LUA_TSTRING){
		buf = luaL_checklstring(L, 2, &len);
		if (!len)
			LUA_ETRACE("open_nonblock:write", "no data", 0);
	}
	else if (lua_type(L, 2) == LUA_TTABLE){
/* handled later */
	}
	else
		arcan_fatal("open_nonblock:write(data, cb) unexpected data type (str or tbl)");

/* special case for FIFOs that aren't hooked up on creation */
	if (-1 == iw->fd && iw->pending){
		iw->fd = open(iw->pending, O_NONBLOCK | O_WRONLY | O_CLOEXEC);

/* but still make sure that we actually got a FIFO */
		if (-1 != iw->fd){
			struct stat fi;

/* and if not, don't try to write */
			if (-1 != fstat(iw->fd, &fi) && !S_ISFIFO(fi.st_mode)){
				lua_pushnumber(L, 0);
				lua_pushboolean(L, false);
				LUA_ETRACE("open_nonblock:write", NULL, 2);
			}
		}
	}

/* direct non-block output mode (legacy)
 * ignored in favour of using the queue even for 'immediate'
	if (lua_type(L, 3) != LUA_TFUNCTION && !iw->out_queue){
		int retc = 5;
		bool rc = true;
		while (retc && (len - of)){
			size_t nw = write(iw->fd, buf + of, len - of);

			if (-1 == nw){
				if (errno == EAGAIN || errno == EINTR){
					retc--;
					continue;
				}
				rc = false;
				break;
			}
			else
				of += nw;
		}

		lua_pushnumber(L, of);
		lua_pushboolean(L, rc);
		LUA_ETRACE("open_nonblock:write", NULL, 2);
	}
	* this means there's no immediate feedback if the write failed
	*/

/* might be swapping out one handler for another */
	if (lua_type(L, 3) == LUA_TFUNCTION){
		if (iw->write_handler != LUA_NOREF){
			unref_registry(L, iw->write_handler, LUA_TFUNCTION, "nbio-write-cb-chg");
			iw->write_handler = LUA_NOREF;
		}

		lua_pushvalue(L, 3);
		iw->write_handler = luaL_ref(L, LUA_REGISTRYINDEX);
	}

/* means we have a table, iterate and queue each entry */
	if (!len){
		int count = lua_rawlen(L, 2);
		for (ssize_t i = 0; i < count; i++){
			lua_rawgeti(L, 2, i+1);
			buf = lua_tolstring(L, -1, &len);
			if (!len){
				lua_pop(L, 1);
				continue;
			}
			if (!buf || !queue_out(iw, buf, len)){
				drop_all_jobs(iw);
				lua_pop(L, 1);
				lua_pushnumber(L, 0);
				lua_pushboolean(L, false);
				LUA_ETRACE("open_nonblock:write", "couldn't queue buffer", 2);
			}
			lua_pop(L, 1);
		}
	}
	else {
		if (!queue_out(iw, buf, len)){
			lua_pushnumber(L, 0);
			lua_pushboolean(L, false);
			LUA_ETRACE("open_nonblock:write", NULL, 2);
		}
	}

/* replace any existing job reference, but it might also be for the
 * first time so only unreference if it was actually removed */
	intptr_t ref;
	if (remove_job(iw->fd, O_WRONLY, &ref)){
		unref_registry(L, ref, LUA_TUSERDATA, "nbio-wrmeta-chg");
	}

/* register the ref and the write mode to some outer dispatch */
	lua_pushvalue(L, 1);
	ref = luaL_ref(L, LUA_REGISTRYINDEX);
	add_job(iw->fd, O_WRONLY, ref);

/* might be tempting to dispatch immediately but that would break
 * multiple sequential write()s
	alt_nbio_process_write(L, iw);
 */

	lua_pushnumber(L, len);
	lua_pushboolean(L, true);
	LUA_ETRACE("open_nonblock:write", NULL, 2);
}

static char* nextline(
	struct nonblock_io* ib,
	size_t start,  /* IN: offset from ib->buf to start processing from */
	bool eof,      /* IN: is the source alive? */
	size_t* nb,    /* INOUT: number of bytes to consume */
	size_t* step,  /* INOUT: number of bytes to skip, doesn't need to == nb */
	bool* gotline, /* OUT: did we retrieve a full line or capped by bufsz */
	char linech    /* IN: character used for separation */
	)
{

/* empty input buffer? early - out */
	if (!ib->ofs)
		return NULL;

	*step = 0;

/* consume each character in buffer */
	for (size_t i = start; i < ib->ofs; i++){

/* if we match linefeed at our current position we are done */
		if (ib->buf[i] == linech){

/* some callers want the character to remain, others will strip it */
			*nb = ib->lfstrip ? (i - start) : (i - start) + 1;
			*step = (i - start) + 1;
			*gotline = true;
			return &ib->buf[start];
		}
	}

/* we are full without separator or at end-of-source */
	if (eof || (!start && ib->ofs == COUNT_OF(ib->buf))){
		*gotline = false;

		if (ib->ofs < start){
			*nb = 0;
			*step = 0;
			ib->ofs = 0;
		}
		else {
			*nb = ib->ofs - start;
			*step = ib->ofs - start;
		}
		return ib->buf;
	}

	return NULL;
}

int alt_nbio_process_read(
	lua_State* L, struct nonblock_io* ib, bool nonbuffered)
{
	size_t buf_sz = COUNT_OF(ib->buf);
	char* ch = NULL;
	size_t len = 0, step = 0;

	if (!ib || ib->fd < 0)
		return 0;

/*
 * The normal ugly edge case is EOF when where is strings in the buffer
 * still pending and the caller wants returns per logical line to avoid
 * excess and expensive string processing.
 *
 * In such a case, read will first fail and EOF marker is set. Then the
 * nextline function will treat end of buffer as the last 'linefeed'.
 *
 * The 'eof' value witll propagate as the function return, indicating to
 * the caller that the descriptor can be closed.
 */
	bool eof = false;
	ssize_t nr = read(ib->fd, &ib->buf[ib->ofs], buf_sz - ib->ofs);

	if (0 == nr){
		eof = true;
	}

/*
 * For the old :read() -> line, ok form there is a case where we try to read,
 * manages to get a line, call a read again and it fails with valid data still
 * in buffer. In that case we fall through (ib->ofs set) and the normal nonbuf
 * or nextline approach will continue correctly.
 */
	else if (-1 == nr){
		if (errno == EAGAIN || errno == EINTR){
			if (!ib->ofs){
				lua_pushnil(L);
				lua_pushboolean(L, true);
				if (!ib->ofs)
					return 2;
			}
		}
		else
			eof = true;
	}
	else
		ib->ofs += nr;

	if (nonbuffered){
		if (ib->ofs)
			lua_pushlstring(L, ib->buf, ib->ofs);
		else
			lua_pushnil(L);
		lua_pushboolean(L, !eof || ib->ofs);
		ib->ofs = 0;
		return 2;
	}

/* three different transfer modes based on the top argument.
 * 1. just return the first string as a call result.
 * 2. append to table at -1.
 * 3. forward to the callback at -1.
 */
#define SLIDE(X) do{\
	if (ci <= ib->ofs){\
		memmove(ib->buf, &ib->buf[ci], ib->ofs - ci);\
		ib->ofs -= ci;\
}} while(0)
	bool gotline;

	if (lua_type(L, -1) == LUA_TFUNCTION){
		size_t ci = 0;

/* several invariants:
 * 1. normal lf -> string
 * 2. eof but multiple lines in buffer
 * 3. eof but no ending lf
 */
		bool cancel = false;
		while (
			!cancel &&
			(ch = nextline(ib, ci, eof, &len, &step, &gotline, ib->lfch))){
			lua_pushvalue(L, -1);
			lua_pushlstring(L, ch, len);
			lua_pushboolean(L, eof && !gotline);
			ci += step;
			alt_call(L, CB_SOURCE_NONE, 0, 2, 1, LINE_TAG":read_cb");

/* the caller doesn't want more data (right now) OR the offset has
 * been incremented past buffer constraints when there is <LF><EOF>
 * as step will be 1 <= step <= ofs could cause nextline called at
 * a start beyond end of buffer */
			cancel = lua_toboolean(L, -1) || ib->ofs <= ci;
			lua_pop(L, 1);
		}

		SLIDE();

		lua_pushnil(L);
		lua_pushboolean(L, !eof);
		return 2;
	}
	else if (lua_type(L, -1) == LUA_TTABLE){
		size_t ind = lua_rawlen(L, -1) + 1;
		size_t ci = 0;

/* let the table set ceiling on the number of lines per call, if the field
 * isnt't there count will be set to 0 and we just turn it into SIZET_MAX.
 * The use-case for this is to be able to yield cothreads between table
 * reads. */
		lua_getfield(L, -1, "read_cap");
		size_t count = lua_tonumber(L, -1);
		if (!count)
			count = (size_t) -1;
		lua_pop(L, 1);

	while (
			count &&
	/* same caveat as above, striplf mode can cause len == 0 with step+1
	 * at end-of-full buffer causing ci to overstep buffer cap */
			ci < ib->ofs,
			(ch = nextline(ib, ci, eof, &len, &step, &gotline, ib->lfch))){
			if (eof && len == 0 && step == 0)
				break;

			lua_pushinteger(L, ind++);
			lua_pushlstring(L, ch, len);
			lua_rawset(L, -3);
			count--;

			ci += step;
		}

		SLIDE();
		lua_pushnil(L);
		lua_pushboolean(L, !eof);
		return 2;
	}
	else {
		if ((ch = nextline(ib, 0, eof, &len, &step, &gotline, ib->lfch))){
			lua_pushlstring(L, ch, len);

			if (step < ib->ofs){
				memmove(ib->buf, &ib->buf[step], buf_sz - step);
				ib->ofs -= step;
			}
			else
				ib->ofs = 0;
		}
		else
			lua_pushnil(L);

		lua_pushboolean(L, !eof);
		return 2;
	}
}

lua_Number luaL_optbnumber(lua_State* L, int narg, lua_Number opt)
{
	if (lua_isnumber(L, narg))
		return lua_tonumber(L, narg);
	else if (lua_isboolean(L, narg))
		return lua_toboolean(L, narg);
	else
		return opt;
}

lua_Number luaL_checkbnumber(lua_State* L, int narg)
{
	lua_Number d = lua_tonumber(L, narg);
	if (d == 0 && !lua_isnumber(L, narg)){
		if (!lua_isboolean(L, narg))
			luaL_argerror(L, narg, "number or boolean");
		else
			d = lua_toboolean(L, narg);
	}
	return d;
}

static int nbio_lf(lua_State* L)
{
	LUA_TRACE("open_nonblock:lf_strip")
	struct nonblock_io** ib = luaL_checkudata(L, 1, "nonblockIO");
	struct nonblock_io* ir = *ib;

	ir->lfstrip = luaL_optbnumber(L, 2, 0);

	if (lua_type(L, 3) == LUA_TSTRING){
		const char* ch = lua_tostring(L, 3);
		ir->lfch = ch[0];
	}

	LUA_ETRACE("open_nonblock:lf_strip", NULL, 0);
}

static int nbio_read(lua_State* L)
{
	LUA_TRACE("open_nonblock:read");
	struct nonblock_io** ib = luaL_checkudata(L, 1, "nonblockIO");
	struct nonblock_io* ir = *ib;

	if (!ir)
		LUA_ETRACE("open_nonblock:read", "already closed", 0);

	if (ir->mode == O_WRONLY)
		LUA_ETRACE("open_nonblock:read", "invalid mode (w) for read", 0);

	bool nonbuffered = luaL_optbnumber(L, 2, 0);
	int	nr = alt_nbio_process_read(L, *ib, nonbuffered);

	LUA_ETRACE("open_nonblock:read", NULL, nr);
}

#ifdef WANT_ARCAN_BASE
static int opennonblock_tgt(lua_State* L, bool wr)
{
	arcan_vobject* vobj;
	arcan_vobj_id vid = luaL_checkvid(L, 1, &vobj);
	arcan_frameserver* fsrv = vobj->feed.state.ptr;

	if (vobj->feed.state.tag != ARCAN_TAG_FRAMESERV)
		arcan_fatal("open_nonblock(tgt), target must be a valid frameserver.");

/* overloaded form:
 *  open_nonblock(vid, r | w, type, nbio_ud)
 *
 *  This takes an existing userdata, extracts the descriptor and sends to the
 *  target, while disassociating the descriptor from the argument source.
 */
	const char* type = luaL_optstring(L, 3, "stream");
	struct arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = wr ? TARGET_COMMAND_BCHUNK_IN : TARGET_COMMAND_BCHUNK_OUT
	};
	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", type);
	if (lua_type(L, 4) == LUA_TUSERDATA){
		struct nonblock_io** ibb = luaL_checkudata(L, 4, "nonblockIO");
		struct nonblock_io* ib = *ibb;

		if (ib->fd > 0){
			platform_fsrv_pushfd(fsrv, &ev, ib->fd);
			close(ib->fd);
			ib->fd = -1;
		}

		return 0;
	}

/* WRITE mode = 'INPUT' in the client space */
	int outp[2];
	if (-1 == pipe(outp)){
		arcan_warning("open_nonblock(tgt), pipe-pair creation failed: %d\n", errno);
		return 0;
	}
	int dst = wr ? outp[0] : outp[1];
	int src = wr ? outp[1] : outp[0];

/* in any scenario where this would fail, "blocking" behavior is acceptable */
	alt_nbio_nonblock_cloexec(src, true);
	if (ARCAN_OK != platform_fsrv_pushfd(fsrv, &ev, dst)){
		close(dst);
		close(src);
		return 0;
	}
	close(dst);

	struct nonblock_io* conn = arcan_alloc_mem(sizeof(struct nonblock_io),
			ARCAN_MEM_BINDING, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	if (!conn){
		close(src);
		return 0;
	}

	conn->mode = wr ? O_WRONLY : O_RDONLY;
	conn->fd = src;
	conn->pending = NULL;
	conn->data_handler = LUA_NOREF;
	conn->write_handler = LUA_NOREF;

	uintptr_t* dp = lua_newuserdata(L, sizeof(uintptr_t));
	*dp = (uintptr_t) conn;
	luaL_getmetatable(L, "nonblockIO");
	lua_setmetatable(L, -2);

	return 1;
}
#endif

void alt_nbio_release()
{
/* make sure there are no registered event sources that would remain open
 * without any interpreter-space accessible recipients - the L context is
 * already dead or dying so ignore unref */
	for (size_t i = 0; i < LUACTX_OPEN_FILES; i++){
		struct nonblock_io* ent = &open_fds[i];
		if (ent->fd > 0){
			remove_job(ent->fd, O_RDONLY, NULL);
			remove_job(ent->fd, O_WRONLY, NULL);
			close(ent->fd);
		}
		drop_all_jobs(ent);
		open_fds[i] =
			(struct nonblock_io){
			.data_handler = LUA_NOREF,
			.write_handler = LUA_NOREF
		};
	}
}

struct pathfd {
	char* path;
	char* unlink;
	const char* err;
	const char* metatable;
	int fd;
	int wrmode;
};

static struct pathfd build_fifo_ipc(char* path, bool userns, bool expect_write)
{
	struct pathfd res = {
		.path = NULL,
		.fd = -1,
		.err = NULL
	};
	int ns = userns ? RESOURCE_NS_USER : RESOURCE_APPL_TEMP;

	char* workpath = arcan_expand_resource(path, ns);
	if (!workpath){
		res.err = "Couldn't expand FIFO path";
		return res;
	}

/* if it doesn't exist and we are the write end, create and try again */
	struct stat fi;
	if (-1 == stat(path, &fi)){
		if (expect_write){
			if (-1 == mkfifo(workpath, S_IRWXU)){
				arcan_mem_free(workpath);
				res.err = "Couldn't build FIFO";
				return res;
			}
			int fd = open(workpath, O_RDWR);
			if (-1 == fd){
				arcan_mem_free(workpath);
				res.err = "Couldn't bind FIFO";
				return res;
			}
			res.unlink = workpath;
			res.fd = fd;
			return res;
		}
		else {
			res.path = workpath;
			return res;
		}
	}

	int fd = open(workpath, expect_write ? O_WRONLY : O_RDONLY);
	arcan_mem_free(workpath);

	if (-1 == fd || -1 == fstat(fd, &fi) || S_ISFIFO(fi.st_mode)){
		close(fd);
		res.err = "Couldn't open as FIFO";
		return res;
	}

	int flags = fcntl(fd, F_GETFL);
	if (-1 != flags)
		fcntl(fd, F_SETFL, flags | O_NONBLOCK);

	if (-1 != (flags = fcntl(fd, F_GETFD)))
		fcntl(fd, F_SETFD, flags | FD_CLOEXEC);

	res.fd = fd;
	return res;
}

static struct pathfd build_socket_ipc(char* pathin, bool userns, bool srv)
{
	struct pathfd res = {.path = NULL, .fd = -1, .err = NULL};
	int ns = userns ? RESOURCE_NS_USER : RESOURCE_APPL_TEMP;

	if (srv){
		char* workpath = arcan_find_resource(pathin, ns, ARES_FILE, NULL);

		if (workpath){
			res.err = "EINVAL: Couldn't create socket";
			arcan_mem_free(workpath);
			return res;
		}

		workpath = arcan_expand_resource(pathin, ns);
		if (!workpath){
			res.err = "EINVAL: Couldn't build socket file";
			return res;
		}

		struct sockaddr_un addr = {
			.sun_family = AF_UNIX
		};
		size_t lim = COUNT_OF(addr.sun_path);
		if (strlen(workpath) > lim - 1){
			res.err = "ENAMETOOLONG: expanded socket doesn't fit sockaddr";
			arcan_mem_free(workpath);
			return res;
		}
		snprintf(addr.sun_path, lim, "%s", workpath);

		res.fd = socket(AF_UNIX, SOCK_STREAM, 0);
		if (-1 == res.fd){
			res.err = "EPERM: couldn't allocate socket";
			arcan_mem_free(workpath);
			return res;
		}
		fchmod(res.fd, S_IRWXU);

		if (-1 == bind(res.fd, (struct sockaddr*) &addr, sizeof(addr))){
			close(res.fd);
			arcan_mem_free(workpath);
			res.fd = -1;
			res.err = "ESOCKET: couldn't bind socket";
			return res;
		}

/* this one takes a different metatable to handle accept on connect */
		listen(res.fd, 5);
		res.unlink = workpath;
		res.metatable = "nonblockIOs";
		res.wrmode = O_RDWR;
	}
	else {
		char* workpath = arcan_find_resource(pathin, ns, ARES_FILE, NULL);

		if (!workpath){
			res.err = "EEXIST: Couldn't connect to socket";
			return res;
		}

		res.fd = alt_nbio_socket(workpath, ns, &res.unlink);
		res.wrmode = O_RDWR;
		res.metatable = "nonblockIO";

		if (-1 == res.fd){
			res.err = "EPERM: Couldn't bind to socket";
		}

		arcan_mem_free(workpath);
	}

	return res;
}

static struct pathfd build_new_file(char* path, bool userns)
{
	struct pathfd res = {
		.path = NULL,
		.fd = -1,
		.err = NULL,
		.metatable = "nonblockIO",
		.wrmode = O_RDWR
	};
	int ns = userns ? RESOURCE_NS_USER : RESOURCE_APPL_TEMP;

	char* userpath = arcan_find_resource(
		path, ns, ARES_FILE | ARES_CREATE, &res.fd);

#ifdef WANT_ARCAN_BASE
	if (lua_debug_level){
		arcan_warning("find_resource:ns=%d:%s\n", ns, path ? path : "[null]");
	}
#endif

	if (!path){
		res.err = "Couldn't create file in namespace";
	}
	else
		arcan_mem_free(userpath);

	return res;
}

static struct pathfd open_existing_file(char* path, bool userns)
{
	struct pathfd res = {
		.path = NULL,
		.err = NULL,
		.fd = -1,
		.wrmode = O_RDONLY,
		.metatable = "nonblockIO"
	};

	int ns = userns ? RESOURCE_NS_USER : DEFAULT_USERMASK;
	char* cpath = arcan_find_resource(path, ns, ARES_FILE, &res.fd);

#ifdef WANT_ARCAN_BASE
	if (lua_debug_level){
		arcan_warning(
			"find_resource:ns=%d:%s=%s\n", ns, path, cpath ? cpath : "[null]");
	}
#endif

	if (!cpath){
		res.err = "Couldn't find file";
	}

	arcan_mem_free(cpath);
	return res;
}

int alt_nbio_open(lua_State* L)
{
	LUA_TRACE("open_nonblock");
	struct pathfd pfd;

	int wrmode = luaL_optbnumber(L, 2, 0) ? O_WRONLY : O_RDONLY;
	bool userns = false;

/* nonblock-io write to/from an explicit vid,
 * this might also be opening a hash to/from an existing a12 monitor */
#ifdef WANT_ARCAN_BASE
	if (lua_type(L, 1) == LUA_TNUMBER){
		int rv = opennonblock_tgt(L, wrmode == O_WRONLY);
		LUA_ETRACE("open_nonblock(), ", NULL, rv);
	}
#endif

	char* str = strdup(luaL_checkstring(L, 1));

	size_t i = 0;
	for (;str[i] && isalnum(str[i]); i++);
	if (str[i] == ':' && str[i+1] == '/'){
		userns = RESOURCE_NS_USER;
	}

	if (str[0] == '<')
		pfd = build_fifo_ipc(str+1, userns, wrmode == O_WRONLY);
	else if (str[0] == '=')
		pfd = build_socket_ipc(str+1, userns, wrmode != O_WRONLY);
	else if (wrmode == O_WRONLY)
		pfd = build_new_file(str, userns);
	else
		pfd = open_existing_file(str, userns);

	free(str);

	if (pfd.err){
		LUA_ETRACE("open_nonblock", pfd.err, 0);
	}

	struct nonblock_io* conn = arcan_alloc_mem(
			sizeof(struct nonblock_io),
			ARCAN_MEM_BINDING, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	conn->fd = pfd.fd;
	conn->lfch = '\n';
	alt_nbio_nonblock_cloexec(pfd.fd, true);

/* this little crutch was better than differentiating the userdata as the
 * support for polymorphism there is rather clunky */
	conn->mode = pfd.wrmode;
	conn->pending = pfd.path;
	conn->unlink_fn = pfd.unlink;
	conn->data_handler = LUA_NOREF;
	conn->write_handler = LUA_NOREF;

	uintptr_t* dp = lua_newuserdata(L, sizeof(uintptr_t));
	*dp = (uintptr_t) conn;

	luaL_getmetatable(L, pfd.metatable);
	lua_setmetatable(L, -2);

	LUA_ETRACE("open_nonblock", NULL, 1);
}

void alt_nbio_data_out(lua_State* L, intptr_t tag)
{
	if (!lookup_registry(L, tag, LUA_TUSERDATA, "data-out"))
		return;

	struct nonblock_io** ibb = luaL_checkudata(L, -1, "nonblockIO");
	struct nonblock_io* ib = *ibb;
	lua_pop(L, 1);

	if (!ib->out_queue)
		return;

/* all pending writes are done, notify and check if there is still a job */
	int status = alt_nbio_process_write(L, ib);

	if (status == 0)
		return;

/* no registered handler? then just ensure empty queue on finish/fail */
	if (ib->write_handler == LUA_NOREF){
		drop_all_jobs(ib);
		return;
	}

/* the gpu locked is only interesting / useful for arcan where there are
 * certain restrictions on doing things while the GPU is locked, while still
 * being able to process other IO */
	if (!lookup_registry(L, ib->write_handler, LUA_TFUNCTION, "data-out-wh"))
		return;

	lua_pushboolean(L, status == 1);
#ifdef WANT_ARCAN_BASE
	lua_pushboolean(L, arcan_conductor_gpus_locked());
#else
	lua_pushboolean(L, false);
#endif
	drop_all_jobs(ib);
	alt_call(L, CB_SOURCE_NONE, 0, 2, 0, LINE_TAG":write_handler_cb");

/* Remove the current event-source unless a new handler has already been queued
 * in its place (alt_call callback is colored) - then the tag has already been
 * unref:d */
	if (!ib->out_queue){
		if (remove_job(ib->fd, O_WRONLY, &tag)){
			unref_registry(L, tag, LUA_TUSERDATA, "nbio-open-wrmeta");
		}
	}
}

void alt_nbio_data_in(lua_State* L, intptr_t tag)
{
	if (!lookup_registry(L, tag, LUA_TUSERDATA, "data-in"))
		return;

	struct nonblock_io** ibb = luaL_checkudata(L, -1, "nonblockIO");
	struct nonblock_io* ib = *ibb;
	if (!ib)
		return;

	lua_pop(L, 1);
	if (!lookup_registry(L, ib->data_handler, LUA_TFUNCTION, "data-in-dh"))
		return;

	intptr_t ch = ib->data_handler;
	ib->data_rearmed = false;

#ifdef WANT_ARCAN_BASE
	lua_pushboolean(L, arcan_conductor_gpus_locked());
#else
	lua_pushboolean(L, false);
#endif
	alt_call(L, CB_SOURCE_NONE, 0, 1, 1, LINE_TAG":data_handler_cb");

/* manually re-armed? do nothing */
	if (ib->data_rearmed){
	}
	else if (lua_type(L, -1) == LUA_TBOOLEAN && lua_toboolean(L, -1)){
/* automatically re-arm on true- return, means doing nothing */
	}
/* or remove and assume that this is no longer wanted */
	else {
		unref_registry(L, ch, LUA_TFUNCTION, "data-in-dontwant");
		ib->data_handler = LUA_NOREF;

/* but make sure that we don't remove any data-out handler while at it */
		if (remove_job(ib->fd, O_RDONLY, &tag)){
			unref_registry(L, tag, LUA_TUSERDATA, "data-in-meta-dontwant");
		}
	}
	lua_pop(L, 1);
}

/* set_position and seek are split to leave room for the theoretically possible
 * on sockets / pipes as a positive seek being (skip n bytes) */
static int nbio_seek(lua_State* L)
{
	struct nonblock_io** ibb = luaL_checkudata(L, 1, "nonblockIO");
	struct nonblock_io* ib = *ibb;
	if (!ib)
		arcan_fatal("nbio:seek on closed file");

	lua_Number ofs = lua_tonumber(L, 1);
	off_t pos = lseek(ib->fd, ofs, SEEK_CUR);

	lua_pushboolean(L, pos != -1);
	lua_pushnumber(L, pos);
	return 2;
}

static int nbio_position(lua_State* L)
{
	struct nonblock_io** ibb = luaL_checkudata(L, 1, "nonblockIO");
	if (!ibb)
		arcan_fatal("nbio:set_position on closed file");

	struct nonblock_io* ib = *ibb;

	lua_Number pos = lua_tonumber(L, 1);
	if (pos < 0)
		pos = lseek(ib->fd, -pos, SEEK_END);
	else
		pos = lseek(ib->fd, pos, SEEK_SET);

	lua_pushboolean(L, pos != -1);
	lua_pushnumber(L, pos);
	return 2;
}

static int nbio_flush(lua_State* L)
{
	struct nonblock_io** ibb = luaL_checkudata(L, 1, "nonblockIO");
	struct nonblock_io* ib = *ibb;
	lua_pop(L, 1);

/* if we have a write_handler it should be handled through the regular loop */
	if (ib->write_handler != LUA_NOREF || !ib->out_queue || ib->fd == -1){
		lua_pushboolean(L, false);
		return 1;
	}

	ssize_t timeout = luaL_optnumber(L, 2, -1);
	bool rv = ensure_flush(L, ib, timeout);

	lua_pushboolean(L, rv);
	return 1;
}

bool alt_nbio_import(
	lua_State* L, int fd, mode_t mode, struct nonblock_io** out,
	char** unlink_fn)
{
	if (-1 == fd){
		lua_pushnil(L);
		return false;
	}

	if (out)
		*out = NULL;

	struct nonblock_io* nbio = malloc(sizeof(struct nonblock_io));

	if (!nbio){
		close(fd);
		lua_pushnil(L);
		return false;
	}

	uintptr_t* dp = lua_newuserdata(L, sizeof(uintptr_t*));
	if (!dp){
		close(fd);
		free(nbio);
		lua_pushnil(L);
		return false;
	}
	*dp = (uintptr_t) nbio;

	*nbio = (struct nonblock_io){
		.fd = fd,
		.mode = mode,
		.lfch = '\n',
		.unlink_fn = (unlink_fn ? *unlink_fn : NULL),
		.write_handler = LUA_NOREF,
		.data_handler = LUA_NOREF,
	};

	if (out)
		*out = nbio;

	alt_nbio_nonblock_cloexec(fd, false);

	luaL_getmetatable(L, "nonblockIO");
	lua_setmetatable(L, -2);
	return true;
}

void alt_nbio_register(lua_State* L,
	bool (*add)(int fd, mode_t, intptr_t tag),
	bool (*remove)(int fd, mode_t, intptr_t* out),
	void (*error)(lua_State* L, int fd, intptr_t tag, const char*))
{
	add_job = add;
	remove_job = remove;
	trigger_error = error;

	luaL_newmetatable(L, "nonblockIO");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, nbio_read);
	lua_setfield(L, -2, "read");
	lua_pushcfunction(L, nbio_write);
	lua_setfield(L, -2, "write");
	lua_pushcfunction(L, nbio_closer);
	lua_setfield(L, -2, "__gc");
	lua_pushcfunction(L, nbio_writequeue);
	lua_setfield(L, -2, "outqueue");
	lua_pushcfunction(L, nbio_datahandler);
	lua_setfield(L, -2, "data_handler");
	lua_pushcfunction(L, nbio_closer);
	lua_setfield(L, -2, "close");
	lua_pushcfunction(L, nbio_seek);
	lua_setfield(L, -2, "seek");
	lua_pushcfunction(L, nbio_position);
	lua_setfield(L, -2, "set_position");
	lua_pushcfunction(L, nbio_flush);
	lua_setfield(L, -2, "flush");
	lua_pushcfunction(L, nbio_lf);
	lua_setfield(L, -2, "lf_strip");
	lua_pop(L, 1);

	luaL_newmetatable(L, "nonblockIOs");
	lua_pushvalue(L, -1);
	lua_setfield(L, -2, "__index");
	lua_pushcfunction(L, nbio_socketaccept);
	lua_setfield(L, -2, "accept");
	lua_pushcfunction(L, nbio_socketclose);
	lua_setfield(L, -2, "close");
	lua_pushcfunction(L, nbio_socketclose);
	lua_setfield(L, -2, "_gc");
	lua_pop(L, 1);
}
