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

static struct nonblock_io open_fds[LUACTX_OPEN_FILES];

/* open_nonblock and similar functions need to register their fds here as they
 * are force-closed on context shutdown, this is necessary with crash recovery
 * and scripting errors. The limit is set based on the same open limit imposed
 * by arcan_event_ sources. */
static bool (*add_job)(int fd, mode_t mode, intptr_t tag);
static bool (*remove_job)(int fd, mode_t mode, intptr_t* out);

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

	if (ib->data_handler)
		luaL_unref(L, LUA_REGISTRYINDEX, ib->data_handler);

	if (ib->write_handler)
		luaL_unref(L, LUA_REGISTRYINDEX, ib->write_handler);

/* no-op if nothing registered */
	intptr_t tag;
	if (remove_job(fd, O_RDONLY, &tag)){
		luaL_unref(L, LUA_REGISTRYINDEX, tag);
	}
	if (remove_job(fd, O_WRONLY, &tag)){
		luaL_unref(L, LUA_REGISTRYINDEX, tag);
	}

	free(ib);
	*ibb = NULL;

/* remove the entry, close will be called from nbio_close, and any current
 * event handlers and triggers will be removed through drop_all_jobs */
	for (size_t i = 0; i < LUACTX_OPEN_FILES; i++){
		if (open_fds[i].fd == fd){
			open_fds[i] = (struct nonblock_io){0};
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
	if ((*ib)->data_handler){
		luaL_unref(L, LUA_REGISTRYINDEX, (*ib)->data_handler);
		(*ib)->data_handler = 0;
	}

/* tracking to ensure that we detect nbio_data_in -> cb ->data_handler */
	(*ib)->data_rearmed = true;

/* the same goes for the reference used to tag events */
	intptr_t out;
	if (remove_job((*ib)->fd, O_RDONLY, &out)){
		luaL_unref(L, LUA_REGISTRYINDEX, out);
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
			luaL_unref(L, LUA_REGISTRYINDEX, ref);
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
		if (iw->write_handler){
			luaL_unref(L, LUA_REGISTRYINDEX, iw->write_handler);
			iw->write_handler = 0;
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
		luaL_unref(L, LUA_REGISTRYINDEX, ref);
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

static char* nextline(struct nonblock_io* ib,
	size_t start, bool eof, size_t* nb, size_t* step, bool* gotline)
{
	if (!ib->ofs)
		return NULL;

	*step = 0;

	for (size_t i = start; i < ib->ofs; i++){
		if (ib->buf[i] == '\n'){
			*nb = ib->lfstrip ? (i - start) : (i - start) + 1;
			*step = (i - start) + 1;
			*gotline = true;
			return &ib->buf[start];
		}
	}

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
	memmove(ib->buf, &ib->buf[ci], ib->ofs - ci);\
	ib->ofs -= ci;\
}while(0)
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
			(ch = nextline(ib, ci, eof, &len, &step, &gotline))){
			lua_pushvalue(L, -1);
			lua_pushlstring(L, ch, len);
			lua_pushboolean(L, eof && !gotline);
			ci += step;
			alt_call(L, CB_SOURCE_NONE, 0, 2, 1, LINE_TAG":read_cb");
			cancel = lua_toboolean(L, -1);
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
 * isnt't there count will be set to 0 and we just turn it into SIZET_MAX */
		lua_getfield(L, -1, "read_cap");
		size_t count = lua_tonumber(L, -1);
		if (!count)
			count = (size_t) -1;
		lua_pop(L, 1);

	while (
			count &&
			(ch = nextline(ib, ci, eof, &len, &step, &gotline))){
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
		if ((ch = nextline(ib, 0, eof, &len, &step, &gotline))){
			lua_pushlstring(L, ch, len);
			memmove(ib->buf, &ib->buf[step], buf_sz - step);
			ib->ofs -= step;
		}
		else
			lua_pushnil(L);

		lua_pushboolean(L, !eof);
		return 2;
	}
}

static int nbio_lf(lua_State* L)
{
	LUA_TRACE("open_nonblock:lf_strip")
	struct nonblock_io** ib = luaL_checkudata(L, 1, "nonblockIO");
	struct nonblock_io* ir = *ib;

	ir->lfstrip = luaL_optbnumber(L, 2, 0);

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

	int outp[2];
	if (-1 == pipe(outp)){
		arcan_warning("open_nonblock(tgt), pipe-pair creation failed: %d\n", errno);
		return 0;
	}

	const char* type = luaL_optstring(L, 3, "stream");

/* WRITE mode = 'INPUT' in the client space */
	int dst = wr ? outp[0] : outp[1];
	int src = wr ? outp[1] : outp[0];

/* in any scenario where this would fail, "blocking" behavior is acceptable */
	set_nonblock_cloexec(src, true);
	struct arcan_event ev = {
		.category = EVENT_TARGET,
		.tgt.kind = wr ? TARGET_COMMAND_BCHUNK_IN : TARGET_COMMAND_BCHUNK_OUT
	};
	snprintf(ev.tgt.message, COUNT_OF(ev.tgt.message), "%s", type);

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
		open_fds[i] = (struct nonblock_io){0};
	}
}

int alt_nbio_open(lua_State* L)
{
	LUA_TRACE("open_nonblock");

	const char* metatable = "nonblockIO";
	char* unlink_fn = NULL;

	int wrmode = luaL_optbnumber(L, 2, 0) ? O_WRONLY : O_RDONLY;
	bool fifo = false, ignerr = false, use_socket = false;
	char* path;
	int fd;

/* nonblock-io write to/from an explicit vid */
#ifdef WANT_ARCAN_BASE
	if (lua_type(L, 1) == LUA_TNUMBER){
		int rv = opennonblock_tgt(L, wrmode == O_WRONLY);
		LUA_ETRACE("open_nonblock(), ", NULL, rv);
	}
#endif

	int namespace = RESOURCE_APPL_TEMP;
	const char* str = luaL_checkstring(L, 1);
	if (str[0] == '<'){
		fifo = true;
		str++;
	}
	else if (str[0] == '='){
		use_socket = true;
		str++;
	}
	else {
		size_t i = 0;
		for (;str[i] && isalnum(str[i]); i++);
		if (str[i] == ':' && str[i+1] == '/'){
			namespace = RESOURCE_NS_USER;
		}
	}

/* note on file-system races: it is an explicit contract that the namespace
 * provided for RESOURCE_APPL_TEMP is single- user (us) only. Anyhow, this
 * code turned out a lot messier than needed, refactor when time permits. */
	if (wrmode == O_WRONLY){
		struct stat fi;
		path = arcan_find_resource(str, namespace, ARES_FILE, NULL);

/* we require a zap_resource call if the file already exists, except for in
 * the case of a fifo dst- that we can open in (w) mode */
		bool dst_fifo = (path && -1 != stat(path, &fi) && S_ISFIFO(fi.st_mode));
		if (!dst_fifo && (path || !(path = arcan_expand_resource(str, namespace)))){
			arcan_warning("open_nonblock(), refusing to open "
				"existing file for writing\n");
			arcan_mem_free(path);

			LUA_ETRACE("open_nonblock", "write on already existing file", 0);
		}

		int fl = O_NONBLOCK | O_WRONLY | O_CLOEXEC;
		if (fifo){
/* this is susceptible to the normal race conditions, but we also expect
 * APPL_TEMP to be mapped to a 'safe' path */
			if (-1 == mkfifo(path, S_IRWXU)){
				if (errno != EEXIST || -1 == stat(path, &fi) || !S_ISFIFO(fi.st_mode)){
					arcan_warning("open_nonblock(): mkfifo (%s) failed\n", path);
					LUA_ETRACE("open_nonblock", "mkfifo failed", 0);
				}
			}
			unlink_fn = strdup(path);
			ignerr = true;
		}
		else
			fl |= O_CREAT;

/* failure to open fifo can be expected, then opening will be deferred */
		fd = open(path, fl, S_IRWXU);
		if (-1 != fd && fifo && (-1 == fstat(fd, &fi) || !S_ISFIFO(fi.st_mode))){
			close(fd);
			LUA_ETRACE("open_nonblock", "opened file not fifo", 0);
		}
	}
/* recall, socket binding is supposed to go to a 'safe' namespace, so
 * filesystem races are less than a concern than normally */
	else if (use_socket){
		struct sockaddr_un addr = {
			.sun_family = AF_UNIX
		};
		size_t lim = COUNT_OF(addr.sun_path);
		path = arcan_find_resource(str, namespace, ARES_FILE, NULL);
		if (path || !(path = arcan_expand_resource(str, namespace))){
			arcan_warning("open_nonblock(), refusing to overwrite file\n");
			LUA_ETRACE("open_nonblock", "couldn't create socket", 0);
		}

		if (strlen(path) > lim - 1){
			arcan_warning("open_nonblock(), socket path too long\n");
			LUA_ETRACE("open_nonblock", "socket path too long", 0);
		}
		snprintf(addr.sun_path, lim, "%s", path);

		metatable = "nonblockIOs";

		fd = socket(AF_UNIX, SOCK_STREAM, 0);
		if (-1 == fd){
			arcan_warning("open_nonblock(): couldn't create socket\n");
			arcan_mem_free(path);
			LUA_ETRACE("open_nonblock", "couldn't create socket", 0);
		}
		fchmod(fd, S_IRWXU);

		alt_nbio_nonblock_cloexec(fd, true);
		int rv = bind(fd, (struct sockaddr*) &addr, sizeof(addr));
		if (-1 == rv){
			close(fd);
			arcan_mem_free(path);
			arcan_warning(
				"open_nonblock(): bind (%s) failed: %s\n", path, strerror(errno));
			LUA_ETRACE("open_nonblock", "couldn't bind socket", 0);
		}
		listen(fd, 5);
		unlink_fn = path;
		path = NULL; /* don't mark as pending */
	}
	else {
retryopen:
		path = arcan_find_resource(str, namespace, ARES_FILE, NULL);

/* fifo and doesn't exist? create */
		if (!path){
			if (fifo && (path = arcan_expand_resource(str, namespace))){
				if (-1 == mkfifo(path, S_IRWXU)){
					arcan_warning("open_nonblock(): mkfifo (%s) failed\n", path);
					LUA_ETRACE("open_nonblock", "mkfifo failed", 0);
				}
				goto retryopen;
			}
			else{
				LUA_ETRACE("open_nonblock", "file does not exist", 0);
			}
		}
/* normal file OR socket */
		else{
			fd = open(path, O_NONBLOCK | O_CLOEXEC | O_RDONLY);

/* socket, 'connect mode' */
			if (-1 == fd && errno == ENXIO){
				fd = alt_nbio_socket(path, namespace, &unlink_fn);
				wrmode = O_RDWR;
			}
		}

		arcan_mem_free(path);
		path = NULL;
	}

	if (fd < 0 && !ignerr){
		arcan_mem_free(path);
		LUA_ETRACE("open_nonblock", "couldn't open file", 0);
	}

	struct nonblock_io* conn = arcan_alloc_mem(
			sizeof(struct nonblock_io),
			ARCAN_MEM_BINDING, ARCAN_MEM_BZERO, ARCAN_MEMALIGN_NATURAL);

	conn->fd = fd;

/* this little crutch was better than differentiating the userdata as the
 * support for polymorphism there is rather clunky */
	conn->mode = wrmode;
	conn->pending = path;
	conn->unlink_fn = unlink_fn;

	uintptr_t* dp = lua_newuserdata(L, sizeof(uintptr_t));
	*dp = (uintptr_t) conn;

	luaL_getmetatable(L, metatable);
	lua_setmetatable(L, -2);

	LUA_ETRACE("open_nonblock", NULL, 1);
}

void alt_nbio_data_out(lua_State* L, intptr_t tag)
{
	lua_rawgeti(L, LUA_REGISTRYINDEX, tag);
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
	if (!ib->write_handler){
		drop_all_jobs(ib);
		return;
	}

/* the gpu locked is only interesting / useful for arcan where there are
 * certain restrictions on doing things while the GPU is locked, while still
 * being able to process other IO */
	lua_rawgeti(L, LUA_REGISTRYINDEX, ib->write_handler);
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
			luaL_unref(L, LUA_REGISTRYINDEX, tag);
		}
	}
}

void alt_nbio_data_in(lua_State* L, intptr_t tag)
{
	lua_rawgeti(L, LUA_REGISTRYINDEX, tag);

	struct nonblock_io** ibb = luaL_checkudata(L, -1, "nonblockIO");
	struct nonblock_io* ib = *ibb;
	if (!ib)
		return;

	lua_pop(L, 1);
	lua_rawgeti(L, LUA_REGISTRYINDEX, ib->data_handler);
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
		luaL_unref(L, LUA_REGISTRYINDEX, ch);

/* but make sure that we don't remove any data-out handler while at it */
		if (remove_job(ib->fd, O_RDONLY, &tag)){
			luaL_unref(L, LUA_REGISTRYINDEX, tag);
		}
	}
	lua_pop(L, 1);
}

/* this symbol comes parasitically with arcan-shmif and used inside the tui
 * implementation, thus it is not particularly nice to rely on it - on the
 * other hand vendoring in the code is also annoying */
extern unsigned long long arcan_timemillis();

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
	if (ib->write_handler || !ib->out_queue || ib->fd == -1){
		lua_pushboolean(L, false);
		return 1;
	}

	struct pollfd fd = {
		.fd = ib->fd,
		.events = POLLOUT | POLLERR | POLLHUP | POLLNVAL
	};

	bool rv = true;

/* since poll doesn't give much in terms of feedback across calls some crude
 * timekeeping is needed to make sure we don't exceed a timeout by too much */
	unsigned long long current = arcan_timemillis();
	ssize_t timeout = luaL_optnumber(L, 2, -1);
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
		.unlink_fn = (unlink_fn ? *unlink_fn : NULL)
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
	bool (*remove)(int fd, mode_t, intptr_t* out))
{
	add_job = add;
	remove_job = remove;

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
