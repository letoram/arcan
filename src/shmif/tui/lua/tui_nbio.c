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

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <sys/un.h>
#include <sys/poll.h>

#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>

#include "tui_nbio.h"
#include "tui_nbio_local.h"

static struct nonblock_io open_fds[LUACTX_OPEN_FILES];

/* open_nonblock and similar functions need to register their fds here as they
 * are force-closed on context shutdown, this is necessary with crash recovery
 * and scripting errors. The limit is set based on the same open limit imposed
 * by arcan_event_ sources. */
static bool (*add_job)(int fd, mode_t mode, intptr_t tag);
static bool (*remove_job)(int fd, intptr_t* out);

static void set_nonblock_cloexec(int fd, bool socket)
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
	set_nonblock_cloexec(fd, true);

	if (-1 == connect(fd, (struct sockaddr*) &addr_remote, sizeof(addr_remote))){
		unlink(local);
		close(fd);
		return -1;
	}

	return fd;
}

static int connect_stream_to(const char* path, char** out)
{
/* we still need to bind a path that we can then unlink after connection */
	char* local_path = NULL;
	int retry = 3;

/* find a temporary name to use in the appl-temp namespace, with a fail
 * retry counter to counteract the rare collision vs. permanent problem */
	do {
		char tmpname[16];
		long rnd = random();
		snprintf(tmpname, sizeof(tmpname), "_sock%ld", rnd);
		char* tmppath = arcan_find_resource(tmpname, RESOURCE_APPL_TEMP, ARES_FILE);
		if (!tmppath){
			local_path = arcan_expand_resource(tmpname, RESOURCE_APPL_TEMP);
		}
		else
			free(tmppath);
	} while (!local_path && retry--);

	if (!local_path)
		return -1;

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
			if (nw == EINTR || nw == EAGAIN)
				return 0;
			return -1;
		}

		job->ofs += nw;

/* slide on completion */
		if (job->ofs == job->sz){
			ib->out_queue = job->next;
			arcan_mem_free(job->buf);
			arcan_mem_free(job);
			job = ib->out_queue;
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

	if (ib->ref)
		luaL_unref(L, LUA_REGISTRYINDEX, ib->ref);

	if (ib->data_handler)
		luaL_unref(L, LUA_REGISTRYINDEX, ib->data_handler);

	if (ib->write_handler)
		luaL_unref(L, LUA_REGISTRYINDEX, ib->write_handler);

/* no-op if nothing registered */
	remove_job(fd, NULL);

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
	if (remove_job((*ib)->fd, &out)){
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
		lua_pushboolean(L, add_job(
			(*ib)->fd, (*ib)->write_handler ? O_RDWR : O_RDONLY, ref));

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

static int nbio_write(lua_State* L)
{
	LUA_TRACE("open_nonblock:write");
	struct nonblock_io** ud = luaL_checkudata(L, 1, "nonblockIO");
	struct nonblock_io* iw = *ud;

	if (!iw)
		LUA_ETRACE("open_nonblock:close", "already closed", 0);

	if (iw->mode == O_RDONLY)
		LUA_ETRACE("open_nonblock:write", "invalid mode (r) for write", 0);

	size_t len;
	const char* buf = luaL_checklstring(L, 2, &len);
	off_t of = 0;

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

/* direct non-block output mode (legacy) */
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

/* API Note:
 * other option was to provide a function handler here, but was ignored
 * in favour of the shared data_handler API */

	add_job(iw->fd, iw->data_handler ? O_RDWR : O_RDONLY, iw->ref);

	lua_pushnumber(L, len);
	lua_pushboolean(L, true);
	LUA_ETRACE("open_nonblock:write", NULL, 2);
}

static int push_resstr(lua_State* L, struct nonblock_io* ib, off_t ofs)
{
	size_t in_sz = COUNT_OF(ib->buf);

	lua_pushlstring(L, ib->buf, ofs);

/* slide or reset buffering */
	if (ofs >= in_sz - 1){
		ib->ofs = 0;
	}
	else{
		memmove(ib->buf, ib->buf + ofs + 1, ib->ofs - ofs - 1);
		ib->ofs -= ofs + 1;
	}

	lua_pushboolean(L, true);
	return 2;
}

static size_t bufcheck(lua_State* L, struct nonblock_io* ib)
{
	size_t in_sz = COUNT_OF(ib->buf);
	for (size_t i = 0; i < ib->ofs; i++){
		if (ib->buf[i] == '\n')
			return push_resstr(L, ib, i);
	}

	if (in_sz - ib->ofs == 1)
		return push_resstr(L, ib, in_sz - 1);

	return 0;
}

int alt_nbio_process_read
	(lua_State* L, struct nonblock_io* ib, bool nonbuffered)
{
	size_t buf_sz = COUNT_OF(ib->buf);

	if (!ib || ib->fd < 0)
		return 0;

	ib->eofm = false;
	if (!nonbuffered){
		size_t bufch = bufcheck(L, ib);
		if (bufch)
			return bufch;
	}

	ssize_t nr;
	if ( (nr = read(ib->fd, ib->buf + ib->ofs, buf_sz - ib->ofs - 1)) > 0)
		ib->ofs += nr;

	if (nr == 0 || (-1 == nr && errno != EINTR && errno != EAGAIN)){

/* reading might still fail on pipe with 0 returned, special case it */
		struct pollfd pfd = {.fd = ib->fd, .events = POLLERR | POLLHUP};
		if (nr == 0 && 1 == poll(&pfd, 1, 0)){
			lua_pushnil(L);
			lua_pushboolean(L, false);
		}
		else {
			lua_pushlstring(L, ib->buf, ib->ofs);
			lua_pushboolean(L, true);
			ib->ofs = 0;
			ib->eofm = true;
		}

		return 2;
	}

	if (nonbuffered){
		if (!ib->ofs){
			lua_pushnil(L);
			lua_pushboolean(L, true);
			return 2;
		}

		lua_pushlstring(L, ib->buf, ib->ofs);
		ib->ofs = 0;
		lua_pushboolean(L, true);
		return 2;
	}
	else{
		if (0 == bufcheck(L, ib)){
			lua_pushnil(L);
			lua_pushboolean(L, true);
		}
		return 2;
	}
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
		arcan_fatal("open_nonblock(tgt), target must be a valid frameserver.\n");

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
 * without any interpreter-space accessible recipients */
	for (size_t i = 0; i < LUACTX_OPEN_FILES; i++){
		struct nonblock_io* ent = &open_fds[i];
		if (ent->fd > 0){
			remove_job(ent->fd, NULL);
			close(ent->fd);
		}
		drop_all_jobs(ent);
		open_fds[i] = (struct nonblock_io){0};
	}
}

/*
 * ugly little thing, should really be refactored into different typed versions
 * as part of the big 'split the monster.lua' project, as should all of the
 * posixism be forced into the platform layer.
 */
int alt_nbio_open(lua_State* L)
{
	LUA_TRACE("open_nonblock");

	const char* metatable = "nonblockIO";
	char* unlink_fn = NULL;
	int wrmode = luaL_optbnumber(L, 2, 0) ? O_WRONLY : O_RDONLY;
	bool fifo = false, ignerr = false, use_socket = false;
	char* path;
	int fd;

#ifdef WANT_ARCAN_BASE
	if (lua_type(L, 1) == LUA_TNUMBER){
		int rv = opennonblock_tgt(L, wrmode == O_WRONLY);
		LUA_ETRACE("open_nonblock(), ", NULL, rv);
	}
#endif

	const char* str = luaL_checkstring(L, 1);
	if (str[0] == '<'){
		fifo = true;
		str++;
	}
	else if (str[0] == '='){
		use_socket = true;
		str++;
	}

/* note on file-system races: it is an explicit contract that the namespace
 * provided for RESOURCE_APPL_TEMP is single- user (us) only. Anyhow, this
 * code turned out a lot messier than needed, refactor when time permits. */
	if (wrmode == O_WRONLY){
		struct stat fi;
		path = arcan_find_resource(str, RESOURCE_APPL_TEMP, ARES_FILE);

/* we require a zap_resource call if the file already exists, except for in
 * the case of a fifo dst- that we can open in (w) mode */
		bool dst_fifo = (path && -1 != stat(path, &fi) && S_ISFIFO(fi.st_mode));
		if (!dst_fifo && (path || !(path =
			arcan_expand_resource(str, RESOURCE_APPL_TEMP)))){
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
/* recall, socket binding is supposed to go to a 'safe' namespace, so the
 * normal filesystem races are less than a concern than normally */
	else if (use_socket){
		struct sockaddr_un addr = {
			.sun_family = AF_UNIX
		};
		size_t lim = COUNT_OF(addr.sun_path);
		path = arcan_find_resource(str, RESOURCE_APPL_TEMP, ARES_FILE);
		if (path || !(path = arcan_expand_resource(str, RESOURCE_APPL_TEMP))){
			arcan_warning("open_nonblock(), refusing to overwrite file\n");
			LUA_ETRACE("open_nonblock", "couldn't create socket", 0);
		}

		if (strlen(path) > lim - 1){
			arcan_warning("open_nonblock(), socket path too long\n");
			LUA_ETRACE("open_nonblock", "socket path too lpng", 0);
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

		set_nonblock_cloexec(fd, true);
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
		path = arcan_find_resource(str,
			fifo ? RESOURCE_APPL_TEMP : DEFAULT_USERMASK, ARES_FILE);

/* fifo and doesn't exist? create */
		if (!path){
			if (fifo && (path = arcan_expand_resource(str, RESOURCE_APPL_TEMP))){
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
				fd = connect_stream_to(path, &unlink_fn);
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

	struct nonblock_io* conn = arcan_alloc_mem(sizeof(struct nonblock_io),
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

	if (!ib->write_handler || !ib->out_queue)
		return;

/* all pending writes are done, notify and check if there is still a job */
	int status = alt_nbio_process_write(L, ib);
	if (status != 0){
		lua_rawgeti(L, LUA_REGISTRYINDEX, ib->write_handler);
		lua_pushboolean(L, status == 1);
#ifdef WANT_ARCAN_BASE
		lua_pushboolean(L, arcan_conductor_gpus_locked());
#else
		lua_pushboolean(L, false);
#endif
		alt_call(L, CB_SOURCE_NONE, 0, 2, 0, LINE_TAG":write_handler_cb");

/* remove the current event-source, and if there is a data handler still around
 * we need to re-register but fire only for read events while keeping the
 * reference mapping between nonblock_io lua-space job and event tag */
		if (!ib->out_queue){
			remove_job(ib->fd, NULL);
			if (ib->data_handler)
				add_job(ib->fd, O_RDONLY, tag);
			else
				luaL_unref(L, LUA_REGISTRYINDEX, tag);
		}
	}
}

void alt_nbio_data_in(lua_State* L, intptr_t tag)
{
	lua_rawgeti(L, LUA_REGISTRYINDEX, tag);

	struct nonblock_io** ibb = luaL_checkudata(L, -1, "nonblockIO");
	struct nonblock_io* ib = *ibb;
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
		luaL_unref(L, LUA_REGISTRYINDEX, tag);

/* but make sure that we don't remove any data-out handler while at it */
		remove_job(ib->fd, NULL);
		if (ib->write_handler)
			add_job(ib->fd, O_WRONLY, ib->data_handler);
	}
	lua_pop(L, 1);
}

/* this symbol comes parasitically with arcan-shmif and used inside the tui
 * implementation, thus it is not particularly nice to rely on it - on the
 * other hand vendoring in the code is also annoying */
extern unsigned long long arcan_timemillis();

static int nbio_flush(lua_State* L)
{
	struct nonblock_io** ibb = luaL_checkudata(L, 1, "nonblockIO");
	struct nonblock_io* ib = *ibb;
	lua_pop(L, 1);

	if (!ib->write_handler || !ib->out_queue || ib->fd == -1){
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

bool alt_nbio_import(lua_State* L, int fd, mode_t mode, struct nonblock_io** out)
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
		.mode = mode
	};

	if (out)
		*out = nbio;

	set_nonblock_cloexec(fd, false);

	luaL_getmetatable(L, "nonblockIO");
	lua_setmetatable(L, -2);
	return true;
}

void alt_nbio_register(lua_State* L,
	bool (*add)(int fd, mode_t, intptr_t tag),
	bool (*remove)(int fd, intptr_t* out))
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
	lua_pushcfunction(L, nbio_datahandler);
	lua_setfield(L, -2, "data_handler");
	lua_pushcfunction(L, nbio_closer);
	lua_setfield(L, -2, "close");
	lua_pushcfunction(L, nbio_flush);
	lua_setfield(L, -2, "flush");
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
