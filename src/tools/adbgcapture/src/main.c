#define _DEFAULT_SOURCE
#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <unistd.h>
#include <pwd.h>
#include <fcntl.h>

#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <arcan_tui_listwnd.h>

static int core_fd = -1;
static int app_fd = -1;
static char* dbgcore_fn = NULL;
static char* dbgbin_fn = NULL;

enum {
	REQID_GDB = 0xbabe,
	REQID_LLDB = 0xcafe,
	REQID_SHELL = 0x011
};

/* incremented on bchunk transfers
 * _Atomic int pending = ATOMIC_VAR_INIT(0),
 * pending number of bytes are then expected from signalfd before exiting */
static void on_bchunk(struct tui_context* c,
	bool input, uint64_t size, int tgt, const char* id, void* t)
{
	if (input)
		return;

/* duplicate the source to make sure we don't trample on file position with
 * multiple pendings */
	int fd = -1;
	if (strcasecmp(id, "elf") == 0)
		fd = arcan_shmif_dupfd(app_fd, -1, true);

	if (strcasecmp(id, "elfcore") == 0)
		fd = arcan_shmif_dupfd(core_fd, -1, true);

	if (-1 == fd)
		return;

	lseek(fd, 0, SEEK_SET);

/* duplicate the target as it will be closed after this */
	tgt = arcan_shmif_dupfd(tgt, -1, true);
	if (-1 == tgt){
		close(fd);
		return;
	}

/* NOTE: This does not use the signal-fd to verify that there is no outstanding
 * copies to be done before shutting down - or at least communicate the number
 * of pending - internally a flag for detach- on shutdown might also be useful.
 *
 * The other is that we can't distinguish between multiple transfers in-flight
 * as no unique identifier to notify back on is available. */
	arcan_tui_bgcopy(c, fd, tgt, -1, 0);
}

static void drop_to_user(const char* uname)
{
/* drop privileges, if it doesn't work - well little we can do about it */
	struct passwd* uinf = getpwnam(uname);
	if (!uinf)
		return;

	setegid(uinf->pw_gid);
	setgid(uinf->pw_gid);
#ifdef __LINUX
	setfsgid(uinf->pw_gid);
	setfsuid(uinf->pw_uid);
#endif
	setuid(uinf->pw_uid);
	seteuid(uinf->pw_uid);
}

/* we need the descriptor to the source so we can send on request */
static FILE* grab_bin(const char* arg_pid, char** name_out)
{
	char fnbuf[strlen(arg_pid) + sizeof("/proc//exe")];
	snprintf(fnbuf, sizeof(fnbuf), "/proc/%s/exe", arg_pid);
	app_fd = open(fnbuf, O_RDONLY);

	char tmpbuf[64] = {0};
	readlink(fnbuf, tmpbuf, 64);
	char* beg = strrchr(tmpbuf, '/');
	if (beg)
		*name_out = strdup(&beg[1]);

	return fdopen(app_fd, "r");
}

static FILE* grab_core(const char* corename)
{
	if (strcmp(corename, "-") == 0)
		return stdin;

	return fopen(corename, "r");
}

static char* file_to_tmp(FILE* fin, const char* prefix, int* fdout)
{
	char pattern_core[strlen(prefix) + sizeof("/tmp/_XXXXXX")];
	sprintf(pattern_core, "/tmp/%s_XXXXXX", prefix);
	if (!fin)
		return NULL;

	*fdout = mkstemp(pattern_core);
	if (-1 == *fdout)
		return NULL;

	FILE* fout = fdopen(*fdout, "w");
	char buf[4096];

	for(;;){
		size_t nr = fread(buf, 1, 4096, fin);
		if (!nr || 1 != fwrite(buf, nr, 1, fout))
			break;
	}

	*fdout = arcan_shmif_dupfd(*fdout, -1, true);
	fclose(fout);
	return strdup(pattern_core);
}

enum {
	COMMAND_DEAD = 0,
	COMMAND_GDB = 1,
	COMMAND_LLDB = 2,
	COMMAND_COPYCORE = 3,
	COMMAND_COPYBIN = 4,
	COMMAND_SHELL = 5,
};

static int query_command(struct tui_context* t)
{
	struct tui_list_entry list[] = {
		{
			.label = "GDB",
			.tag = COMMAND_GDB
		},
		{
			.label = "LLDB",
			.tag = COMMAND_LLDB
		},
		{
			.label = "Shell",
			.tag = COMMAND_SHELL,
		},
		{
			.label = "Copy Core",
			.tag = COMMAND_COPYCORE
		},
		{
			.label = "Copy Bin",
			.tag = COMMAND_COPYBIN
		},
		{
			.label = "",
			.attributes = LIST_SEPARATOR
		},
		{
			.label = "Quit / Discard",
			.tag = COMMAND_DEAD
		}
	};

/* arcan_tui_ident(t, ""); */
	arcan_tui_listwnd_setup(t, list, sizeof(list) / sizeof(list[0]));
	struct tui_list_entry* ent;
	for(;;){
		struct tui_process_res res = arcan_tui_process(&t, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(t) && errno == EINVAL){
				return COMMAND_DEAD;
			}
		}

		if (arcan_tui_listwnd_status(t, &ent)){
			break;
		}
	}

	arcan_tui_listwnd_release(t);
	return ent->tag;
}

/* don't know where we are coming from PATH- wise so go for hardcoded */
static char* find_exec(const char* fname)
{
	static const char* const prefix[] = {"/usr/local/bin", "/usr/bin", ".", NULL};
	size_t ind = 0;

	while(prefix[ind]){
		char* buf	= NULL;
		if (-1 == asprintf(&buf, "%s/%s", prefix[ind++], fname))
			continue;

		struct stat fs;
		if (-1 == stat(buf, &fs)){
			free(buf);
			continue;
		}

		return buf;
	}

	return NULL;
}

static bool on_subwindow(struct tui_context* t,
	arcan_tui_conn* new_wnd, uint32_t id, uint8_t type, void* c)
{
	char* exec_path = find_exec("afsrv_terminal");
	if (!exec_path)
		return false;

	char* argv[] = {"afsrv_terminal", NULL};
	char* env[] = {
		NULL, /* ARCAN_TERMINAL_EXEC=... */
		NULL, /* ARCAN_TERMINAL_ARGV=... */
		NULL
	};


	if (type == SEGID_DEBUG)
		return false;

/* depending on the ID we get back, take different action - we don't have a
 * better gdb frontend to handover to, so the transfers of core and bin comes
 * from the race:y pathnames */
	char* bin = NULL;
	char* arg = NULL;

	if (id == REQID_GDB){
		bin = find_exec("gdb");
		if (!bin)
			return false;

		char* tmp;
		int rv = asprintf(&tmp,"ARCAN_TERMINAL_EXEC=%s", bin);
		free(bin);
		bin = tmp;

		if (-1 == rv)
			return false;

		rv = asprintf(&arg, "ARCAN_TERMINAL_ARGV=%s %s",
			dbgbin_fn ? dbgbin_fn : "",
			dbgcore_fn ? dbgcore_fn : "");
		if (-1 == rv){
			free(bin);
			return false;
		}
	}
	else if (id == REQID_LLDB){
/* --core --file */
		bin = find_exec("lldb");
		if (!bin)
			return false;

		char* tmp;
		int rv = asprintf(&tmp,"ARCAN_TERMINAL_EXEC=%s", bin);
		free(bin);
		bin = tmp;

		if (-1 == rv)
			return false;

		rv = asprintf(&arg, "ARCAN_TERMINAL_ARGV=--core %s %s",
			dbgcore_fn ? dbgcore_fn : "", dbgbin_fn ? dbgbin_fn : "");
		if (-1 == rv){
			free(bin);
			return false;
		}
	}
	else {
/* just let a normal shell go in here, possibly CWD to the binary in question -
 * recall, this can be used over a12 and remotely where the callback shell
 * makes sense */
	}

	if (bin){
		env[0] = bin;
		env[1] = arg;
	}

	arcan_tui_handover(
		t, new_wnd, exec_path, argv, env,
		TUI_DETACH_PROCESS | TUI_DETACH_STDIN | TUI_DETACH_STDOUT);
	return true;
}

static void run_command(struct tui_context* t, int cmd)
{
	switch(cmd){
/* even divisible by 2? gdb, otherwise lldb */
	case COMMAND_GDB:
		arcan_tui_request_subwnd(t, TUI_WND_HANDOVER, REQID_GDB);
	break;
	case COMMAND_LLDB:
		arcan_tui_request_subwnd(t, TUI_WND_HANDOVER, REQID_LLDB);
	break;
	case COMMAND_SHELL:
		arcan_tui_request_subwnd(t, TUI_WND_HANDOVER, REQID_SHELL);
	break;
	case COMMAND_COPYCORE:
		if (-1 != core_fd)
			arcan_tui_announce_io(t, true, NULL, "elfcore");
	break;
	case COMMAND_COPYBIN:
		if (-1 != app_fd)
			arcan_tui_announce_io(t, true, NULL, "elf");
	break;
	}
}

int main(int argc, char** argv)
{
/* ensure that we get proper STDOUT/STDERR - the core_pattern handler is not
 * you vanilla 'sudo' interface */
	int fd = 0;

	while (fd < STDERR_FILENO && fd != -1)
		fd = open("/dev/null", O_RDWR);

	if (fd > STDERR_FILENO)
		close(fd);

/* we can't really 'report' to a stderr from the context of a crash collector */
	if (argc <
		1 + /* prgname     */
		1 + /* corename, - */
		1 + /* user        */
		1 + /* rtdir, .    */
		1 + /* connpath    */
		1   /* pid         */
	){
		fprintf(stderr, "arcan-dbgcapture - argument error (%d), expected: core user xdgrtdir cpoint pid\n", argc);
		return EXIT_FAILURE;
	}

	const char* arg_core = argv[1];
	const char* arg_user = argv[2];
	const char* arg_rtdir = argv[3];
	const char* arg_connpath = argv[4];
	const char* arg_pid = argv[5];

/* we need to get the application (and core) when we are still root as it might need the 'exe'
 * entry from proc with weird permissions */
	char* title = NULL;
	FILE* fbin = grab_bin(arg_pid, &title);
	FILE* fcore = grab_core(arg_core);

/* we can't create the tmp until we are the target user, or unlink won't work */
	drop_to_user(arg_user);

/* return the process and its state-data to the kernel */
	pid_t child = fork();
	if (child == 0){
		if (fork() == 0){
			return EXIT_FAILURE;
		}
		return EXIT_SUCCESS;
	}

	int status;
	while (wait(&status) != -1 && errno != ECHILD){}
/* fork failed(?) just go on.. */

/* now we can write them and gdb will be able to parse / read, the original
 * descriptors are held as core_fd and app_fd in order to send onwards */
	int scratch = -1;
	dbgcore_fn = file_to_tmp(fcore, "arcan_dbgcore", &core_fd);
	dbgbin_fn = file_to_tmp(fbin, "arcan_dbgbin", &scratch);

	if (-1 != scratch)
		close(scratch);

/* now we can fire up tui */
	if (arg_rtdir[0] == '/')
		setenv("XDG_RUNTIME_DIR", arg_rtdir, 1);

	setenv("ARCAN_CONNPATH", arg_connpath, 1);
	struct arcan_shmif_cont c = arcan_shmif_open_ext(0, NULL,
		(struct shmif_open_ext){
			.title = "arcan-dbgcapture",
			.ident = title,
			.type = SEGID_TUI
		},
		sizeof(struct shmif_open_ext)
	);
	if (!c.addr){
		goto out;
	}

/* we still lack a handover mechanism that retains the current connection,
 * the problem with that comes from the semaphores being gone and to stay
 * portable with "OS" X can't go with better primitives */
	struct tui_cbcfg cbcfg = {
		.bchunk = on_bchunk,
		.subwindow = on_subwindow
	};

	struct tui_context* t = arcan_tui_setup(
		(arcan_tui_conn*) &c, NULL, &cbcfg, sizeof(cbcfg));

/* send label and format-hints, though the same paths can be activated
 * interactively */

	int cmd;
	while ((cmd = query_command(t)) != COMMAND_DEAD){
		run_command(t, cmd);
	}

/* release the temps - could possibly be done when we get signal from
 * fsrv-terminal that it has managed to chain-exec into gdb through the
 * use of ARCAN_TERMINAL_PIDFD_OUT, PIDFD_IN like shmif-debug is using */
out:
	if (dbgcore_fn)
		unlink(dbgcore_fn);
	if (dbgbin_fn)
		unlink(dbgbin_fn);

	return EXIT_SUCCESS;
}
