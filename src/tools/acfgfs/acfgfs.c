/*
 * ACFGFS - Quick and dirty implementation of the pipe based virtual config
 * filesystem protocol used in Durden, Safespaces and others. Based on the
 * hello example from the original fuse project.
 *
 * It is a simple line-based protocol implemented over a domain socket.
 *
 * read /path : retrieve metadata or current value
 * ls /path : show contents of directory
 * exec /path : execute action (filename not ending in =)
 * write /path=value : update key/value
 * eval /path=value : simulate path and see if the value would be accepted or not
 *
 * these are all mapped via wait_for_command and exposed as either directories or FIFOs.
 */

#define FUSE_USE_VERSION 31

#include <fuse.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <inttypes.h>
#include <stdbool.h>
#include <limits.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <stddef.h>
#include <assert.h>
#include <sys/un.h>
#include <stdarg.h>
#include <sys/socket.h>
#include <pthread.h>

_Static_assert(sizeof(uint64_t) >= sizeof(uintptr_t), "filehandle can't hold pointer");

static pthread_mutex_t mutex = PTHREAD_MUTEX_INITIALIZER;

/* current 'multithreading' is rather pointless, but if the asynch- callback
 * changes to main arcan won't pan out - we'll need to do something here */
static pthread_mutex_t in_command = PTHREAD_MUTEX_INITIALIZER;

static void debug_print_fn(const char* fmt, ...)
{
	pthread_mutex_lock(&mutex);
	va_list ap;
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	pthread_mutex_unlock(&mutex);
}

#define debug_print(fmt, ...) \
	do { debug_print_fn("%s:%d:%s(): " fmt "\n",\
		"", __LINE__, __func__,##__VA_ARGS__); } while (0)

/*
 * get the two pipes (or one socket really, it was due to an engine
 * limitation before).
 * commands:
 * write ns/path/to/key=val
 * exec
 * ls
 * read
 * eval
 */

/*
 * Command line options
 *
 * We can't set default values for the char* fields here because
 * fuse_opt_parse would attempt to free() them when the user specifies
 * different values on the command line.
 */
static struct options {
	const char* control;
	int con;
	int show_help;
} options = {
	.control = NULL,
	.con = -1
};

/*
 * This is quite slow as it has to align to the synch periods of the displays
 * in order for the menu to give accurate results about the various states,so
 * some kind of caching mechanism similar to what would be performed for high
 * latency filesystems (ftp, ...) should be used here as well.
 */
static int wait_for_command(const char* cmd,
	const char* path, const char* arg, void(*linecb)(char*, void*), void* tag)
{
	char buf[4096];
	if (-1 == options.con){
		struct sockaddr_un addr = {
			.sun_family = AF_UNIX
		};
		snprintf(addr.sun_path,
			sizeof(addr.sun_path)/sizeof(addr.sun_path[0]), "%s", options.control);
		options.con = socket(AF_UNIX, SOCK_STREAM, 0);
		if (connect(options.con, (struct sockaddr*) &addr, sizeof(addr)) == -1){
			debug_print("can't connect to socket (%s)", options.control);
			close(options.con);
			options.con = -1;
			return -EEXIST;
		}
	}

	size_t ntw =
		snprintf(buf, sizeof(buf), "%s %s%s%s\n",
			cmd, path ? path : "",
			arg ? "=" : "",
			arg ? arg : ""
		);
	if (ntw > sizeof(buf)){
		debug_print("command %s:%s overflow protection",
			path ? path : "(nopath)", arg ? arg : "(noarg)");
		return -EINVAL;
	}

/* buffered write */
	size_t ofs = 0;
	pthread_mutex_lock(&in_command);
	while(ntw){
		ssize_t nw = write(options.con, &buf[ofs], ntw);
		if (-1 == nw){
			if (errno != EAGAIN && errno != EINTR){
				debug_print("write to parent failed, connection broken");
				close(options.con);
				options.con = -1;
				pthread_mutex_unlock(&in_command);
				return -errno;
			}
			continue;
		}
		ofs += nw;
		ntw -= nw;
	}

/* [n] is so low that doing real buffering etc. isn't really meaningful */
	ofs = 0;
	for(;;){
		if (-1 == read(options.con, &buf[ofs], 1)){
			if (errno != EAGAIN && errno != EINTR){
				close(options.con);
				options.con = -1;
				pthread_mutex_unlock(&in_command);
				return -errno;
			}
			continue;
		}

		if (buf[ofs] == '\n'){
			buf[ofs] = '\0';
			ofs = 0;
			if (strcmp(buf, "OK") == 0){
				pthread_mutex_unlock(&in_command);
				return 0;
			}
			else if (strncmp(buf, "EINVAL", 6) == 0){
				pthread_mutex_unlock(&in_command);
				return -ENOENT;
			}
			linecb(buf, tag);
			continue;
		}

		ofs++;
		if (ofs == sizeof(buf)){
			pthread_mutex_unlock(&in_command);
			return -EINVAL;
		}
	}

	pthread_mutex_unlock(&in_command);
	return 0;
}

static void *acfgfs_init(
	struct fuse_conn_info *conn, struct fuse_config *cfg)
{
	(void) conn;
	cfg->kernel_cache = 1;
	return NULL;
}

static void sdircb(char* str, void* tag)
{
	struct stat* stbuf = tag;
	if (strcmp(str, "kind: directory") == 0){
		stbuf->st_mode = S_IFDIR | 0700;
		stbuf->st_nlink = 3;
		stbuf->st_size = 4096;
	}
	else if (strcmp(str, "kind: action") == 0){
		stbuf->st_mode = S_IFREG | 0600;
		stbuf->st_nlink = 1;
		stbuf->st_size = 512;
	}
	else if (strcmp(str, "kind: value") == 0){
		stbuf->st_mode = S_IFREG | 0600;
		stbuf->st_nlink = 1;
		stbuf->st_size = 512;
	}
}

static int acfgfs_getattr(const char *path, struct stat *stbuf,
			 struct fuse_file_info *fi)
{
	(void) fi;
	*stbuf = (struct stat){};
	return wait_for_command("read", path, NULL, sdircb, stbuf);
}

struct rdircb_t {
	void* buf;
	fuse_fill_dir_t filler;
};

static void rdircb(char* str, void* tag)
{
	struct rdircb_t* cbt = tag;
	size_t len = strlen(str);
	struct stat fs = {
	};

	if (len <= 1)
		return;

/* strip away trailing newline */
	if (str[len-1] == '\n'){
		str[len-1] = '\0';
		len--;
	}

/* classify value, directory or action */
	if (str[len-1] == '/'){
		fs.st_mode = S_IFDIR | 0700;
		fs.st_nlink = 3;
		fs.st_size = 4096;
		str[len-1] = '\0';
	}
	else {
		fs.st_mode = S_IFREG | 0600;
		fs.st_nlink = 1;
	}

/* and forward */
	cbt->filler(cbt->buf, str, &fs, 0, 0);
}

static int acfgfs_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
			 off_t offset, struct fuse_file_info *fi,
			 enum fuse_readdir_flags flags)
{
	struct rdircb_t cbt = {
		.buf = buf,
		.filler = filler,
	};

	filler(buf, ".", NULL, 0, 0);
	filler(buf, "..", NULL, 0, 0);

	return wait_for_command("ls", path, NULL, rdircb, &cbt);
}

struct file_ent_info {
	uint32_t cookie;
	char buffer[4096];
	size_t used;
	bool value;
};

static void rent(char* str, void* tag)
{
	struct file_ent_info* dst = tag;
	size_t ntw = strlen(str);
	size_t left = sizeof(dst->buffer) - dst->used - 2;
	ntw = ntw < left ? ntw : left;
	if (!ntw)
		return;

/* nulled at init */
	memcpy(&dst->buffer[dst->used], str, ntw);
	dst->used += ntw;
	dst->buffer[dst->used++] = '\n';

	if (strcmp(str, "kind: value") == 0)
		dst->value = true;
}

static int acfgfs_open(const char* path, struct fuse_file_info* fi)
{
	struct file_ent_info* fent = malloc(sizeof(struct file_ent_info));
	if (!fent){
		debug_print("couldn't open %s", path);
		return -EINVAL;
	}
	*fent = (struct file_ent_info){.cookie = 0xfeedface};

	if (0 != wait_for_command("read", path, NULL, rent, fent)){
		free(fent);
		return -ENOENT;
	}

	fi->nonseekable = true;
	fi->fh = (uintptr_t) fent;
/* do want polling for some special 'wm- management protocol',
 * but not yet */
	fi->poll_events = 0;

	return 0;
}

static int acfgfs_read(const char* path,
	char* buf, size_t size, off_t offset, struct fuse_file_info* fi)
{
	if (!fi->fh)
		return -EINVAL;

	struct file_ent_info* fent = (struct file_ent_info*)((uintptr_t)fi->fh);
	if (fent->cookie != 0xfeedface){
		debug_print("invalid cookie in read command on %s", path);
		return -EINVAL;
	}

	size_t left = fent->used - offset;
	size_t ntr = size > left ? left : size;

/* I guess its FUSE responsibility to set EFAULT for buf not writable,
 * otherwise we need to test that with the write trick */
	if (offset > fent->used)
		return 0;

	memcpy(buf, &fent->buffer[offset], ntr);
	debug_print("read status, ntr: %zu, offset: %zd", ntr, offset);
	return ntr;
}

static int acfgfs_release(const char* path, struct fuse_file_info* fi)
{
	if (!fi->fh){
		debug_print("attempt to release %s on bad handle", path);
		return -EINVAL;
	}

	struct file_ent_info* fent = (struct file_ent_info*)((uintptr_t)fi->fh);
	if (fent->cookie != 0xfeedface){
		debug_print("attempt to release %s on bad cookie", path);
		return -EINVAL;
	}

	free(fent);
	fi->fh = 0xbad1dea;
	return 0;
}

static int acfgfs_write(const char* path,
	const char* buf, size_t size, off_t offset, struct fuse_file_info* fi)
{
	if (!fi->fh){
		debug_print("attempt to write to %s on bad handle", path);
		return -EINVAL;
	}

	struct file_ent_info* fent = (struct file_ent_info*)((uintptr_t)fi->fh);
	if (fent->cookie != 0xfeedface){
		debug_print("bad cookie 0x%"PRIx32, fent->cookie);
		return -EINVAL;
	}

/*
 * this does not differentiate between evaluate and commit, how should
 * we actually indicate this in a way that would make sense for CLI use?
 */
	if (fent->value){
		char argbuf[1024];
		snprintf(argbuf, sizeof(argbuf), "%.*s", (int)size, buf);
		if (0 != wait_for_command("write", path, argbuf, NULL, NULL)){
			debug_print("value commit failed: %s", argbuf);
			return -EINVAL;
		}
		return size;
	}

/* just ignore whatever, the write command itself is a trigger -
 * question is if FUSE does any other kind of buffering that would
 * be interpreted as unintentional writes */
	if (0 != wait_for_command("exec", path, NULL, NULL, NULL)){
		debug_print("exec activation of %s failed", path);
		return -EINVAL;
	}

	return 0;
}

static struct fuse_operations acfgfs_oper = {
	.init = acfgfs_init,
	.getattr = acfgfs_getattr,
	.readdir = acfgfs_readdir,
	.open = acfgfs_open,
	.read = acfgfs_read,
	.write = acfgfs_write,
	.release = acfgfs_release
};

static void show_help(const char* progname)
{
	printf("usage: %s [options] <mountpoint>\n\n", progname);
	printf("File-system specific options:\n"
		"\t--control=<s>\t control socket path (required)");
}

#define OPTION(t, p)\
{ t, offsetof(struct options, p), 1 }

static const struct fuse_opt option_spec[] = {
	OPTION("--control=%s", control),
	OPTION("-h", show_help),
	OPTION("--help", show_help),
	FUSE_OPT_END
};

int main(int argc, char *argv[])
{
	struct fuse_args args = FUSE_ARGS_INIT(argc, argv);

	if (fuse_opt_parse(&args, &options, option_spec, NULL) == -1)
		return 1;

	if (!options.control || !(options.control = realpath(options.control, NULL))){
		fprintf(stderr, "control socket missing, use --control=/path/to/control\n");
		return EXIT_FAILURE;
	}

	if (options.show_help) {
		show_help(argv[0]);
		assert(fuse_opt_add_arg(&args, "--help") == 0);
		args.argv[0] = (char*) "";
	}

	return fuse_main(args.argc, args.argv, &acfgfs_oper, NULL);
}
