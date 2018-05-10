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

#include <fuse3/fuse.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <stddef.h>
#include <assert.h>
#include <sys/un.h>
#include <sys/socket.h>

_Static_assert(sizeof(uint64_t) >= sizeof(uintptr_t), "filehandle can't hold pointer");

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
	FILE* flog;
} options = {
	.control = "/home/void/.arcan/appl-out/durden/ipc/control",
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
	if (!options.flog){
		options.flog = fopen("/tmp/log", "w+");
	}
	fprintf(options.flog, "issue: %s %s\n", path?path:"nopath", arg?arg:"noarg");

	if (-1 == options.con){
		struct sockaddr_un addr = {
			.sun_family = AF_UNIX
		};
		snprintf(addr.sun_path,
			sizeof(addr.sun_path)/sizeof(addr.sun_path[0]), "%s", options.control);
		options.con = socket(AF_UNIX, SOCK_STREAM, 0);
		if (connect(options.con, (struct sockaddr*) &addr, sizeof(addr)) == -1){
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
	if (ntw > sizeof(buf))
		return -EINVAL;

/* buffered write */
	size_t ofs = 0;
	while(ntw){
		ssize_t nw = write(options.con, &buf[ofs], ntw);
		if (-1 == nw){
			if (errno != EAGAIN && errno != EINTR){
				close(options.con);
				options.con = -1;
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
		fprintf(options.flog, "waiting for reply\n");
		if (-1 == read(options.con, &buf[ofs], 1)){
			if (errno != EAGAIN && errno != EINTR){
				fprintf(options.flog, "reading, failed\n");
				close(options.con);
				options.con = -1;
				return -errno;
			}
			continue;
		}

		if (buf[ofs] == '\n'){
			buf[ofs] = '\0';
			ofs = 0;
			fprintf(options.flog, "ret: %s\n", buf);
			fflush(options.flog);
			if (strcmp(buf, "OK") == 0){
				return 0;
			}
			else if (strncmp(buf, "EINVAL", 6) == 0){
				return -ENOENT;
			}
			linecb(buf, tag);
			continue;
		}

		ofs++;
		if (ofs == sizeof(buf)){
			return -EINVAL;
		}
	}

	return 0;
}

#define OPTION(t, p)                           \
    { t, offsetof(struct options, p), 1 }
static const struct fuse_opt option_spec[] = {
	OPTION("--control=%s", control),
	OPTION("-h", show_help),
	OPTION("--help", show_help),
	FUSE_OPT_END
};

static void *acfgfs_init(struct fuse_conn_info *conn,
			struct fuse_config *cfg)
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
		stbuf->st_mode = S_IFIFO | 0600;
		stbuf->st_nlink = 1;
	}
	else if (strcmp(str, "kind: value") == 0){
		stbuf->st_mode = S_IFIFO | 0600;
		stbuf->st_nlink = 1;
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
	if (str[len-1] == '='){
		fs.st_mode = S_IFIFO | 0600;
		fs.st_nlink = 1;
	}
	else if (str[len-1] == '/'){
		fs.st_mode = S_IFDIR | 0700;
		fs.st_nlink = 3;
		fs.st_size = 4096;
		str[len-1] = '\0';
	}
	else {
		fs.st_mode = S_IFIFO | 0600;
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
	char* buffer;
	size_t buf_sz;
	bool valid;
	bool action;
};

static void rent(char* path, void* tag)
{

}

static int acfgfs_open(const char* path, struct fuse_file_info* fi)
{
	struct file_ent_info fent;
	wait_for_command("read", path, NULL, rent, &fent);
/*
 * set fi: O_RDONLY unless queried type was a value
 */
	return -ENOENT;
}

static int acfgfs_read(const char* path,
	char* buf, size_t size, off_t offset, struct fuse_file_info* fi)
{
/*
 * queue the result from the 'open' call to save a round-trip,
 * always return failure on subsequent calls to provoke users
 * to re-open (i.e. synch)
 */
	return -ENOENT;
}

static ssize_t acfgfs_write(const char* path,
	char* buf, size_t size, off_t offset, struct fuse_file_info* fi)
{
/*
 * value?
 * just assumem that what we want to write to the entry fits the buffer in the
 * first write call, and any subsequent ones are EPIPE.
 *
 * action?
 * just exec it and then EPIPE after first call
 */
	if (fi->fh != 0xbad1dea &&
		0 == wait_for_command("exec", path, NULL, NULL, NULL)){
		fi->fh = 0xbad1dea;
		return 0;
	}

	return -ENOENT;
}

static struct fuse_operations acfgfs_oper = {
	.init = acfgfs_init,
	.getattr = acfgfs_getattr,
	.readdir = acfgfs_readdir,
/*
	.open = acfgfs_open,
	.read = acfgfs_read,
	.write = acfgfs_write,
	.release = acfgfs_release
 */
};

static void show_help(const char *progname)
{
	printf("usage: %s [options] <mountpoint>\n\n", progname);
	printf("File-system specific options:\n"
	       "    --name=<s>          Name of the \"hello\" file\n"
	       "                        (default: \"hello\")\n"
	       "    --contents=<s>      Contents \"hello\" file\n"
	       "                        (default \"Hello, World!\\n\")\n"
	       "\n");
}

int main(int argc, char *argv[])
{
	struct fuse_args args = FUSE_ARGS_INIT(argc, argv);

	/* Set defaults -- we have to use strdup so that
	   fuse_opt_parse can free the defaults if other
	   values are specified */

	/* Parse options */
	if (fuse_opt_parse(&args, &options, option_spec, NULL) == -1)
		return 1;

	/* When --help is specified, first print our own file-system
	   specific help text, then signal fuse_main to show
	   additional help (by adding `--help` to the options again)
	   without usage: line (by setting argv[0] to the empty
	   string) */
	if (options.show_help) {
		show_help(argv[0]);
		assert(fuse_opt_add_arg(&args, "--help") == 0);
		args.argv[0] = (char*) "";
	}

	return fuse_main(args.argc, args.argv, &acfgfs_oper, NULL);
}
