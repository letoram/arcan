/*
 * Simple implementation of a client/server proxy.
 */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
#include <pwd.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/wait.h>
#include <stdarg.h>
#include <ctype.h>

#include <sys/socket.h>
#include <sys/stat.h>
#include <netdb.h>

#include "a12.h"
#include "a12_int.h"
#include "a12_helper.h"
#include "anet_helper.h"
#include "directory.h"

enum anet_mode {
	ANET_SHMIF_CL = 1,
	ANET_SHMIF_CL_REVERSE = 2,
	ANET_SHMIF_SRV,
	ANET_SHMIF_SRV_INHERIT,
	ANET_SHMIF_EXEC,
};

enum mt_mode {
	MT_SINGLE = 0,
	MT_FORK = 1
};

struct arcan_net_meta {
	struct anet_options* opts;
	int argc;
	char** argv;
	char* bin;
};

static struct {
	bool soft_auth;
	bool no_default;
	bool probe_only;
	size_t accept_n_pk_unknown;
	size_t backpressure;
	size_t backpressure_soft;
	int directory;
	const char* reqname;
	struct anet_dirsrv_opts dirsrv;
	struct anet_dircl_opts dircl;
} global = {
	.backpressure_soft = 2,
	.backpressure = 6,
	.directory = -1
};

static const char* trace_groups[] = {
	"video",
	"audio",
	"system",
	"event",
	"transfer",
	"debug",
	"missing",
	"alloc",
	"crypto",
	"vdetail",
	"binary",
	"security",
	"directory"
};

static struct a12_vframe_opts vcodec_tuning(
	struct a12_state* S, int segid, struct shmifsrv_vbuffer* vb, void* tag);

static int tracestr_to_bitmap(char* work)
{
	int res = 0;
	char* pt = strtok(work, ",");
	while(pt != NULL){
		for (size_t i = 1; i <= COUNT_OF(trace_groups); i++){
			if (strcasecmp(trace_groups[i-1], pt) == 0){
				res |= 1 << (i - 1);
				break;
			}
		}
		pt = strtok(NULL, ",");
	}
	return res;
}

/*
 * pull in from arcan codebase, chacha based CSPRNG
 */
extern void arcan_random(uint8_t* dst, size_t ntc);

/*
 * Since we pull in some functions from the main arcan codebase, we need to
 * define this symbol, used if the random function has problems with entropy
 * etc.
 */
void arcan_fatal(const char* msg, ...)
{
	va_list args;
	va_start(args, msg);
	vfprintf(stderr, msg, args);
	va_end(args);
	exit(EXIT_FAILURE);
}

static bool handover_setup(struct a12_state* S,
	int fd, struct arcan_net_meta* meta, struct shmifsrv_client** C)
{
	if (meta->opts->mode != ANET_SHMIF_EXEC && global.directory <= 0)
		return true;

/* wait for authentication before going for the shmifsrv processing mode */
	char* msg;
	if (!anet_authenticate(S, fd, fd, &msg)){
		a12int_trace(A12_TRACE_SYSTEM, "authentication failed: %s", msg);
		free(msg);
		shutdown(fd, SHUT_RDWR);
		close(fd);
		return false;
	}

	if (global.directory > 0){
		anet_directory_srv(S, global.dirsrv, fd, fd);
		shutdown(fd, SHUT_RDWR);
		return false;
	}

	if (S->remote_mode == ROLE_PROBE){
		a12int_trace(A12_TRACE_SYSTEM, "probed:terminating");
		shutdown(fd, SHUT_RDWR);
		close(fd);
		return false;
	}

	a12int_trace(A12_TRACE_SYSTEM, "client connected, spawning: %s", meta->bin);

/* connection is ok, tie it to a new shmifsrv_client via the exec arg. The GUID
 * is left 0 here as the local bound applications tend to not have much of a
 * perspective on that. Should it become relevant, just stepping Kp with a local
 * salt through the hash should do the trick. */
	int socket, errc;
	extern char** environ;
	struct shmifsrv_envp env = {
		.init_w = 32, .init_h = 32,
		.path = meta->bin,
		.argv = meta->argv, .envv = environ
	};

	*C = shmifsrv_spawn_client(env, &socket, &errc, 0);
	if (!*C){
		shutdown(fd, SHUT_RDWR);
		close(fd);
		return false;
	}

	return true;
}

static int get_bcache_dir()
{
	const char* base = getenv("A12_BCACHE_DIR");
	if (!base)
		return -1;

	return open(base, O_DIRECTORY);
}

/*
 * in this mode we should really fexec ourselves so we don't risk exposing
 * aslr or canaries, as well as handle the key-generation
 */
static void fork_a12srv(struct a12_state* S, int fd, void* tag)
{
	pid_t fpid = fork();

/* just ignore and return to caller */
	if (fpid > 0){
		a12int_trace(A12_TRACE_SYSTEM, "client handed off to %d", (int)fpid);
		a12_channel_close(S);
		close(fd);
		return;
	}

	if (fpid == -1){
		a12int_trace(A12_TRACE_SYSTEM, "couldn't fork/dispatch, ulimits reached?\n");
		a12_channel_close(S);
		close(fd);
		return;
	}

/* Split the log output on debug so we see what is going on */
#ifdef _DEBUG
		char buf[sizeof("cl_log_xxxxxx.log")];
		snprintf(buf, sizeof(buf), "cl_log_%.6d.log", (int) getpid());
		FILE* fpek = fopen(buf, "w+");
		if (fpek){
			a12_set_trace_level(a12_trace_targets, fpek);
		}
#endif

/* make sure that we don't leak / expose whatever the listening process has,
 * not much to do to guarantee or communicate the failure on these three -
 * possibly creating a slush-pipe and dup:ing that .. */
	close(STDIN_FILENO);
	close(STDOUT_FILENO);
	close(STDERR_FILENO);
	open("/dev/null", O_RDONLY);
	open("/dev/null", O_WRONLY);
	open("/dev/null", O_WRONLY);

	struct shmifsrv_client* C = NULL;
	struct arcan_net_meta* meta = tag;

	if (!handover_setup(S, fd, meta, &C)){
		return;
	}

	arcan_shmif_privsep(NULL, "shmif", NULL, 0);
	int rc = 0;

	if (C){
		a12helper_a12cl_shmifsrv(S, C, fd, fd, (struct a12helper_opts){
			.redirect_exit = meta->opts->redirect_exit,
			.devicehint_cp = meta->opts->devicehint_cp,
			.vframe_block = global.backpressure,
			.vframe_soft_block = global.backpressure_soft,
			.eval_vcodec = vcodec_tuning,
			.bcache_dir = get_bcache_dir()
		});
		shmifsrv_free(C, SHMIFSRV_FREE_NO_DMS);
	}
	else {
/* we should really re-exec ourselves with the 'socket-passing' setup so that
 * we won't act as a possible ASLR break */
		rc = a12helper_a12srv_shmifcl(NULL, S, NULL, fd, fd);
	}

	shutdown(fd, SHUT_RDWR);
	close(fd);
	exit(rc < 0 ? EXIT_FAILURE : EXIT_SUCCESS);
}

extern char** environ;

static struct a12_vframe_opts vcodec_tuning(
	struct a12_state* S, int segid, struct shmifsrv_vbuffer* vb, void* tag)
{
	struct a12_vframe_opts opts = {
		.method = VFRAME_METHOD_DZSTD,
		.bias = VFRAME_BIAS_BALANCED
	};

/* missing: here a12_state_iostat could be used to get congestion information
 * and encoder feedback, then use that to forward new parameters + bias */
	switch (segid){
	case SEGID_LWA:
		opts.method = VFRAME_METHOD_H264;
	break;
	case SEGID_GAME:
		opts.method = VFRAME_METHOD_H264;
		opts.bias = VFRAME_BIAS_LATENCY;
	break;

/* this one is also a possible subject for codec passthrough, that will have
 * to be implemented in the server util part as we need shmif to propagate if
 * we can deal with passthrough and then device_fail that if the other end
 * starts to reject the bitstream */
	case SEGID_MEDIA:
		opts.method = VFRAME_METHOD_H264;
		opts.bias = VFRAME_BIAS_QUALITY;
	break;
	}

/* this is temporary until we establish a config format where the parameters
 * can be set in a non-commandline friendly way (recall ARCAN_CONNPATH can
 * result in handover-exec arcan-net */
	if (opts.method == VFRAME_METHOD_H264){
		static bool got_opts;
		static unsigned long cbr = 22;
		static unsigned long br  = 1024;

/* convert and clamp to the values supported by x264 in ffmpeg */
		if (!got_opts){
			char* tmp;
			if ((tmp = getenv("A12_VENC_CRF"))){
				cbr = strtoul(tmp, NULL, 10);
				if (cbr > 55)
					cbr = 55;
			}
			if ((tmp = getenv("A12_VENC_RATE"))){
				br = strtoul(tmp, NULL, 10);
				if (br * 1000 > INT_MAX)
					br = INT_MAX;
			}
			got_opts = true;
		}

		opts.ratefactor = cbr;
		opts.bitrate = br;
	}

	return opts;
}

static void single_a12srv(struct a12_state* S, int fd, void* tag)
{
	struct shmifsrv_client* C = NULL;
	struct arcan_net_meta* meta = tag;

	if (!handover_setup(S, fd, meta, &C))
		return;

	if (C){
		a12helper_a12cl_shmifsrv(S, C, fd, fd, (struct a12helper_opts){
			.redirect_exit = meta->opts->redirect_exit,
			.devicehint_cp = meta->opts->devicehint_cp,
			.vframe_block = global.backpressure,
			.vframe_soft_block = global.backpressure_soft,
			.eval_vcodec = vcodec_tuning,
			.bcache_dir = get_bcache_dir()
		});
		shmifsrv_free(C, SHMIFSRV_FREE_NO_DMS);
	}
	else{
		a12helper_a12srv_shmifcl(NULL, S, NULL, fd, fd);
		shutdown(fd, SHUT_RDWR);
		close(fd);
	}
}

static void a12cl_dispatch(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd)
{
/* Directory mode has a simpler processing loop so treat it special here, also
 * reducing attack surface since very little actual forwarding or processing is
 * needed. */
	if (global.directory){
		global.dircl.basedir = global.directory;
		anet_directory_cl(S, global.dircl, fd, fd);
		close(fd);
		return;
	}

/* note that the a12helper will do the cleanup / free */
	a12helper_a12cl_shmifsrv(S, cl, fd, fd, (struct a12helper_opts){
		.vframe_block = global.backpressure,
		.redirect_exit = args->redirect_exit,
		.devicehint_cp = args->devicehint_cp,
		.bcache_dir = get_bcache_dir()
	});
	close(fd);
}

static void fork_a12cl_dispatch(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd)
{
	pid_t fpid = fork();
	if (fpid == 0){
		a12cl_dispatch(args, S, cl, fd);
		exit(EXIT_SUCCESS);
	}
	else if (fpid == -1){
		fprintf(stderr, "fork_a12cl() couldn't fork new process, check ulimits\n");
		shmifsrv_free(cl, SHMIFSRV_FREE_NO_DMS);
		a12_channel_close(S);
		close(fd);
		return;
	}
	else {
/* just ignore and return to caller */
		a12int_trace(A12_TRACE_SYSTEM, "client handed off to %d", (int)fpid);
		a12_channel_close(S);
		shmifsrv_free(cl, SHMIFSRV_FREE_LOCAL);
		close(fd);
	}
}

static struct anet_cl_connection find_connection(
	struct anet_options* opts, struct shmifsrv_client* cl)
{
	struct anet_cl_connection anet;
	int rc = opts->retry_count;
	int timesleep = 1;

/* connect loop until retry count exceeded */
	while (rc != 0 && (!cl || (shmifsrv_poll(cl) != CLIENT_DEAD))){
		anet = anet_cl_setup(opts);

		if (anet.state)
			break;

		if (!anet.state){
			if (anet.errmsg){
				fputs(anet.errmsg, stderr);
				free(anet.errmsg);
				anet.errmsg = NULL;
			}

			if (timesleep < 10)
				timesleep++;

			if (rc > 0)
				rc--;

			sleep(timesleep);
			continue;
		}
	}

	return anet;
}

/* connect / authloop shmifsrv */
static struct anet_cl_connection forward_shmifsrv_cl(
	struct shmifsrv_client* cl, struct anet_options* opts)
{
	struct anet_cl_connection anet = find_connection(opts, cl);

/* failed, or retry-count exceeded? */
	if (!anet.state || shmifsrv_poll(cl) == CLIENT_DEAD){
		shmifsrv_free(cl, SHMIFSRV_FREE_NO_DMS);

		if (anet.state){
			a12_free(anet.state);
			close(anet.fd);

			if (anet.errmsg)
				free(anet.errmsg);
		}
	}

/* wait / block the processing until we know the connection is authentic,
 * this will callback into keystore and so on */
	char* msg;
	if (!anet_authenticate(anet.state,
		anet.fd, anet.fd, &msg) || shmifsrv_poll(cl) == CLIENT_DEAD){
		if (msg){
			a12int_trace(A12_TRACE_SYSTEM, "authentication_failed=%s", msg);
		}

		shmifsrv_free(cl, SHMIFSRV_FREE_NO_DMS);
		if (anet.state){
			a12_free(anet.state);
			close(anet.fd);
		}

		if (anet.errmsg)
			free(anet.errmsg);
	}

	return anet;
}

static int a12_connect(struct anet_options* args,
	void (*dispatch)(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd))
{
	signal(SIGPIPE, SIG_IGN);
	signal(SIGCHLD, SIG_IGN);

	int shmif_fd = -1;
	for(;;){
		struct shmifsrv_client* cl =
			shmifsrv_allocate_connpoint(args->cp, NULL, S_IRWXU, shmif_fd);

		if (!cl){
			fprintf(stderr, "couldn't open connection point\n");
			return EXIT_FAILURE;
		}

/* first time, extract the connection point descriptor from the connection */
		if (-1 == shmif_fd)
			shmif_fd = shmifsrv_client_handle(cl);

		struct pollfd pfd = {.fd = shmif_fd, .events = POLLIN | POLLERR | POLLHUP};

/* wait for a connection */
		for(;;){
			int pv = poll(&pfd, 1, -1);
			if (-1 == pv){
				if (errno != EINTR && errno != EAGAIN){
					shmifsrv_free(cl, true);
					fprintf(stderr, "error while waiting for a connection\n");
					return EXIT_FAILURE;
				}
				continue;
			}
			else if (pv)
				break;
		}

/* accept it (this will mutate the client_handle internally) */
		shmifsrv_poll(cl);

/* setup the connection, we do this after the fact rather than before as remote
 * is more likely to have a timeout than locally */
		struct anet_cl_connection anet = forward_shmifsrv_cl(cl, args);

/* wake the client */
		a12int_trace(A12_TRACE_SYSTEM, "local connection found, forwarding to dispatch");
		dispatch(args, anet.state, cl, anet.fd);
	}

	return EXIT_SUCCESS;
}

/* Special version of a12_connect where we inherit the connection primitive
 * to the local shmif client, so we can forego most of the domainsocket bits.
 * The normal use-case for this is where ARCAN_CONNPATH is set to a12://
 * prefix and shmif execs into arcan-net */
static int a12_preauth(struct anet_options* args,
	void (*dispatch)(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd))
{
	int sc;
	struct shmifsrv_client* cl = shmifsrv_inherit_connection(args->sockfd, &sc);
	if (!cl){
		fprintf(stderr, "(shmif::arcan-net) "
			"couldn't build connection from socket (%d)\n", sc);
		shutdown(args->sockfd, SHUT_RDWR);
		close(args->sockfd);
		return EXIT_FAILURE;
	}

	args->opts->local_role = ROLE_SOURCE;
	struct anet_cl_connection anet = forward_shmifsrv_cl(cl, args);

/* and ack the connection */
	dispatch(args, anet.state, cl, anet.fd);

	return EXIT_SUCCESS;
}

static bool tag_host(struct anet_options* anet, char* hoststr, const char** err)
{
	char* toksep = strrchr(hoststr, '@');
	if (!toksep)
		return false;

	*toksep = '\0';
	anet->key = hoststr;
	anet->keystore.type = A12HELPER_PROVIDER_BASEDIR;
	anet->keystore.directory.dirfd = a12helper_keystore_dirfd(err);

	return true;
}

static bool show_usage(const char* msg)
{
	fprintf(stderr, "%s%sUsage:\n"
	"Forward local arcan applications (push): \n"
	"    arcan-net [-Xtd] -s connpoint [tag@]host port\n"
	"         (keystore-mode) -s connpoint tag@\n"
	"         (inherit socket) -S fd_no [tag@]host port\n\n"
	"Server local arcan application (pull): \n"
	"         -l port [ip] -- /usr/bin/app arg1 arg2 argn\n\n"
	"Bridge remote inbound arcan applications (to ARCAN_CONNPATH): \n"
	"    arcan-net [-Xtd] -l port [ip]\n\n"
	"Bridge remote outbound arcan application: \n"
	"    arcan-net [tag@]host port\n\n"
	"Directory/discovery server (uses ARCAN_APPLBASEPATH): \n"
	"    arcan-net --directory -l port [ip]\n\n"
	"Directory/discovery client: \n"
	"    arcan-net [tag@]host port [appl]\n\n"
	"Forward-local options:\n"
	"\t-X             \t Disable EXIT-redirect to ARCAN_CONNPATH env (if set)\n"
	"\t-r, --retry n  \t Limit retry-reconnect attempts to 'n' tries\n\n"
	"Options:\n"
	"\t-a, --auth n   \t Read authentication secret from stdin (maxlen:32)\n"
	"\t --soft-auth   \t authentication secret (password) only, ignore keystore\n"
	"\t               \t if [n] is provided, n keys added to trusted\n"
	"\t-t             \t Single- client (no fork/mt - easier troubleshooting)\n"
	"\t --no-ephem-rt \t Disable ephemeral keypair roundtrip (outbound only)\n"
	"\t --probe-only  \t (outbound) Authenticate and print server primary state\n"
	"\t-d bitmap      \t Set trace bitmap (bitmask or key1,key2,...)\n\n"
	"Directory client options: \n"
	"\t --keep-appl   \t Don't wipe appl after execution\n"
	"\t --reload      \t Re-request the same appl after completion\n"
	"\t --block-log   \t Don't attempt to forward script errors or crash logs\n"
	"\t --block-state \t Don't attempt to synch state before/after running appl\n\n"
	"Environment variables:\n"
	"\tARCAN_STATEPATH\t Used for keystore and state blobs (sensitive)\n"
#ifdef WANT_H264_ENC
	"\tA12_VENC_CRF   \t video rate factor (sane=17..28) (0=lossless,51=worst)\n"
	"\tA12_VENC_RATE  \t bitrate in kilobits/s (hintcap to crf)\n"
#endif
	"\tA12_VBP        \t backpressure maximium cap (0..8)\n"
	"\tA12_VBP_SOFT   \t backpressure soft (full-frames) cap (< VBP)\n"
	"\tA12_CACHE_DIR  \t Used for caching binary stores (fonts, ...)\n\n"
	"Keystore mode (ignores connection arguments):\n"
	"\tAdd/Append key: arcan-net keystore tag host [port=6680]\n"
	"\t                tag=default is reserved\n"
	"\nTrace groups (stderr):\n"
	"\tvideo:1      audio:2      system:4    event:8      transfer:16\n"
	"\tdebug:32     missing:64   alloc:128   crypto:256   vdetail:512\n"
	"\tbinary:1024  security:2048\n\n", msg ? msg : "", msg ? "\n\n" : ""
	);
	return false;
}

static int apply_commandline(int argc, char** argv, struct arcan_net_meta* meta)
{
	const char* modeerr = "Mixed or multiple -s or -l arguments";
	struct anet_options* opts = meta->opts;

/* the default role is sink, -s -exec changes this to source */
	opts->opts->local_role = ROLE_SINK;

/* default-trace security warnings */
	a12_set_trace_level(2048, stderr);

	size_t i = 1;
/* mode defining switches and shared switches */
	for (; i < argc; i++){
		if (argv[i][0] != '-')
			break;

		if (strcmp(argv[i], "-d") == 0){
			if (i == argc - 1)
				return show_usage("-d without trace value argument");
			char* workstr = NULL;
			unsigned long val = strtoul(argv[++i], &workstr, 10);
			if (workstr == argv[i]){
				val = tracestr_to_bitmap(workstr);
			}
			a12_set_trace_level(val, stderr);
		}

/* a12 client, shmif server */
		else if (strcmp(argv[i], "-s") == 0){
			if (opts->mode)
				return show_usage(modeerr);

			opts->opts->local_role = ROLE_SOURCE;
			opts->mode = ANET_SHMIF_SRV;
			if (i >= argc - 1)
				return show_usage("-s: Missing connpoint argument");
			opts->cp = argv[++i];

/* shmif connection points are restricted set */
			for (size_t ind = 0; opts->cp[ind]; ind++)
				if (!isalnum(opts->cp[ind]))
					return show_usage("-s: Invalid character in connpoint [a-Z,0-9]");

			i++;
			if (i >= argc)
				return show_usage("-s: Missing tag@ or host port argument");

			const char* err = NULL;
			if (tag_host(opts, argv[i], &err)){
				if (err)
					return show_usage(err);
				continue;
			}

			opts->host = argv[i++];

			if (i >= argc)
				return show_usage("-s: Missing port argument");

			opts->port = argv[i];

			if (i != argc - 1)
				return show_usage("-s: Trailing arguments after port");

			continue;
		}
/* a12 client, shmif server, inherit primitives */
		else if (strcmp(argv[i], "-S") == 0){
			if (opts->mode)
				return show_usage(modeerr);

			opts->mode = ANET_SHMIF_SRV_INHERIT;
			if (i >= argc - 1)
				return show_usage("Invalid arguments, -S without room for ip");

			opts->sockfd = strtoul(argv[++i], NULL, 10);
			struct stat fdstat;

			if (-1 == fstat(opts->sockfd, &fdstat))
				return show_usage("Couldn't stat -S descriptor");

			if ((fdstat.st_mode & S_IFMT) != S_IFSOCK)
				return show_usage("-S descriptor does not point to a socket");

			if (i == argc)
				return show_usage("-S without room for tag or host/port");

			i++;
			const char* err = NULL;
			if (tag_host(opts, argv[i], &err)){
				if (err)
					return show_usage(err);
				continue;
			}

			opts->host = argv[i++];

			if (i == argc)
				return show_usage("-S host without room for port argument");

			opts->port = argv[i++];

			if (i < argc)
				return show_usage("Trailing arguments to -S fd_in host port");
		}
		else if (strcmp(argv[i], "--soft-auth") == 0){
			global.soft_auth = true;
		}
		else if (strcmp(argv[i], "--no-ephem-rt") == 0){
			opts->opts->disable_ephemeral_k = true;
		}
		else if (strcmp(argv[i], "--probe-only") == 0){
			opts->opts->local_role = ROLE_PROBE;
			global.probe_only = true;
		}
/* a12 server, shmif client */
		else if (strcmp(argv[i], "-l") == 0){
			if (opts->mode)
				return show_usage(modeerr);
			opts->mode = ANET_SHMIF_CL;

			if (i == argc - 1)
				return show_usage("-l without room for port argument");

			opts->port = argv[++i];

			for (size_t ind = 0; opts->port[ind]; ind++)
				if (opts->port[ind] < '0' || opts->port[ind] > '9')
					return show_usage("Invalid values in port argument");

/* three paths, -l port host --exec ..
 * or -l port --exec
 * or just -l port */
			i++;

			if (i == argc)
				return i;

			if (strcmp(argv[i], "--exec") != 0 && strcmp(argv[i], "--") != 0){
				opts->host = argv[i++];

/* no exec, just host */
				if (i >= argc - 1)
					return i;
			}

			if (strcmp(argv[i], "--exec") != 0 && strcmp(argv[i], "--") != 0){
				return show_usage("Unexpected trailing argument, expected --exec or end");
			}

			i++;
			if (i == argc)
				return show_usage("--exec without bin arg0 .. argn");

			meta->bin = argv[i];
			meta->argv = &argv[i];
			opts->mode = ANET_SHMIF_EXEC;
			opts->opts->local_role = ROLE_SOURCE;

			return i;
		}
		else if (strcmp(argv[i], "-t") == 0){
			opts->mt_mode = MT_SINGLE;
		}
		else if (strcmp(argv[i], "--keep-appl") == 0){
			global.dircl.keep_appl = true;
		}
		else if (strcmp(argv[i], "--block-log") == 0){
			global.dircl.block_log = true;
		}
		else if (strcmp(argv[i], "--block-state") == 0){
			global.dircl.block_state = true;
		}
		else if (strcmp(argv[i], "--reload") == 0){
			global.dircl.reload = true;
		}
		else if (strcmp(argv[i], "--directory") == 0){
			if (!getenv("ARCAN_APPLBASEPATH")){
				return show_usage("--directory without ARCAN_APPLBASEPATH set");
			}

			global.directory = open(getenv("ARCAN_APPLBASEPATH"), O_DIRECTORY);
			if (-1 == global.directory){
				return show_usage("--directory ARCAN_APPLBASEPATH couldn't be opened");
			}
			opts->opts->local_role = ROLE_DIR;
		}
		else if (strcmp(argv[i], "-X") == 0){
			opts->redirect_exit = NULL;
		}
		else if (strcmp(argv[i], "-a") == 0 || strcmp(argv[i], "--auth") == 0){
			char msg[32];

			if (isatty(STDIN_FILENO)){
				char* pwd = getpass("connection password: ");
				snprintf(msg, 32, "%s", pwd);
				while (*pwd){
					(*pwd) = '\0';
					pwd++;
				}
			}
			else {
				fprintf(stdout, "reading passphrase from stdin\n");
				if (fgets(msg, 32, stdin) <= 0)
					return show_usage("-a,--auth couldn't read secret from stdin");
			}
			size_t len = strlen(msg);
			if (!len){
				return show_usage("-a,--auth zero-length secret not permitted");
			}

			if (msg[len-1] == '\n')
				msg[len-1] = '\0';

			snprintf(opts->opts->secret, 32, "%s", msg);
			global.no_default = true;

			if (i < argc - 1 && isdigit(argv[i+1][0])){
				global.accept_n_pk_unknown = strtoul(argv[i+1], NULL, 10);
				i++;
				a12int_trace(A12_TRACE_SECURITY,
					"trust_first=%zu", global.accept_n_pk_unknown);
			}

		}
		else if (strcmp(argv[i], "-B") == 0){
			if (i == argc - 1)
				return show_usage("-B without bitrate argument");

			if (!isdigit(argv[i+1][0]))
				return show_usage("-B bitrate should be a number");
		}
		else if (strcmp(argv[i], "-r") == 0 || strcmp(argv[i], "--retry") == 0){
			if (1 < argc - 1){
				opts->retry_count = (ssize_t) strtol(argv[++i], NULL, 10);
			}
			else
				return show_usage("Missing count argument to -r,--retry");
		}
	}

	char* tmp;
	if ((tmp = getenv("A12_VBP"))){
		size_t bp = strtoul(tmp, NULL, 10);
		if (bp >= 0 && bp <= 8)
			global.backpressure = bp;
	}

	if ((tmp = getenv("A12_VBP_SOFT"))){
		size_t bp = strtoul(tmp, NULL, 10);
		if (bp >= 0 && bp <= global.backpressure)
			global.backpressure_soft = bp;
	}

	return i;
}

/* keystore is singleton global */
static bool open_keystore(const char** err)
{
	int dir = a12helper_keystore_dirfd(err);
	if (-1 == dir)
		return false;

	struct keystore_provider prov = {
		.directory.dirfd = dir,
		.type = A12HELPER_PROVIDER_BASEDIR
	};

	if (!a12helper_keystore_open(&prov)){
		*err = "Couldn't open keystore from basedir (ARCAN_STATEPATH)";
		return false;
	}

	return true;
}

static int apply_keystore_command(int argc, char** argv)
{
/* (opt, -b dir) */
	if (!argc)
		return show_usage("Missing keystore command arguments");

	const char* err;
	if (!open_keystore(&err)){
		return show_usage(err);
	}

/* time for tag, host and port */
	if (!argc || argc < 2){
		a12helper_keystore_release();
		return show_usage("Missing tag / host arguments");
	}

	char* tag = argv[0];
	char* host = argv[1];
	argc -= 2;
	argv += 2;

	unsigned long port = 6680;
	if (argc){
		port = strtoul(argv[0], NULL, 10);
		if (!port || port > 65535){
			a12helper_keystore_release();
			return show_usage("Port argument is invalid or out of range");
		}
	}

	uint8_t outpub[32];
	if (!a12helper_keystore_register(tag, host, port, outpub)){
		return show_usage("Couldn't add/create tag in keystore");
	}

	size_t outl;
	unsigned char* b64 = a12helper_tob64(outpub, 32, &outl);
	fprintf(stdout, "add a12/accepted/(filename) in remote keystore:\n* %s\n", b64);
	free(b64);

	a12helper_keystore_release();

	return EXIT_SUCCESS;
}

/*
 * This is used both for the inbound and outbound connection, the difference
 * though is that the outbound connection has already provided keymaterial
 * as that is necessary for constructing the HELLO packet - so the auth is
 * just against if the public key is known/trusted or not in that case.
 *
 * Thus the a12 implementation will only respect the 'authentic' part and
 * disregard whatever is put in key.
 *
 * For inbound, there is an option of differentiation - a different keypair
 * could be returned based on the public key.
 */
static struct pk_response key_auth_local(uint8_t pk[static 32])
{
	struct pk_response auth = {};

	char* tmp;
	uint16_t tmpport;
	size_t outl;
	unsigned char* out = a12helper_tob64(pk, 32, &outl);

/* is the key in our trusted set? */
	if (a12helper_keystore_accepted(pk, NULL)){
		auth.authentic = true;
		a12int_trace(A12_TRACE_SECURITY, "accept=%s", out);
		a12helper_keystore_hostkey("default", 0, auth.key, &tmp, &tmpport);
	}
/* or do we not care about pk authenticity - password in first HMAC only */
	if (global.soft_auth){
		auth.authentic = true;
		a12helper_keystore_hostkey("default", 0, auth.key, &tmp, &tmpport);
		a12int_trace(A12_TRACE_SECURITY, "soft-auth-trust=%s", out);
	}
/* or should we add the first n unknown as implicitly trusted through pass */
	else if (global.accept_n_pk_unknown){
		auth.authentic = true;
		global.accept_n_pk_unknown--;
		a12int_trace(A12_TRACE_SECURITY,
			"left=%zu:accept-unknown=%s", global.accept_n_pk_unknown, out);
		a12helper_keystore_accept(pk, NULL);
		a12helper_keystore_hostkey("default", 0, auth.key, &tmp, &tmpport);
	}
	else if (!auth.authentic){
		a12int_trace(A12_TRACE_SECURITY, "reject-unknown=%s", out);
	}

	if (auth.authentic && global.directory != -1){
		auth.state_access = a12helper_keystore_statestore;
	}

	free(out);
	return auth;
}

int main(int argc, char** argv)
{
	struct anet_options anet = {
		.retry_count = -1,
		.mt_mode = MT_FORK,
/* do note that pk_lookup is left empty == only password auth */
	};

	struct arcan_net_meta meta = {
		.opts = &anet
	};

	anet.opts = a12_sensitive_alloc(sizeof(struct a12_context_options));
	anet.opts->pk_lookup = key_auth_local;

/* set this as default, so the remote side can't actually close */
	anet.redirect_exit = getenv("ARCAN_CONNPATH");
	anet.devicehint_cp = getenv("ARCAN_CONNPATH");

	if (argc > 1 && strcmp(argv[1], "keystore") == 0){
		return apply_keystore_command(argc-2, argv+2);
	}

	if (argc < 2 || (argc == 2 &&
		(strcmp(argv[1], "-h") == 0 || strcmp(argv[1], "--help") == 0)))
		return show_usage(NULL);

	size_t argi = apply_commandline(argc, argv, &meta);
	if (!argi)
		return EXIT_FAILURE;

/* no mode? if there's arguments left, assume it is is the 'reverse' mode
 * where the connection is outbound but we get the a12 'client' view back
 * to pair with an arcan-net --exec .. */
	if (!anet.mode){

		if (argi <= argc - 1){
/* Treat as a key- 'tag' for connecting? This act as a namespace separator
 * so the other option would be to */
			const char* err = NULL;
			if (tag_host(&anet, argv[argi], &err)){
				if (err)
					return show_usage(err);
				argi++;
			}
/* Or just go host / [port] */
			else {
				anet.host = argv[argi++];
				anet.port = "6680";

				if (argi <= argc - 1 && isdigit(argv[argi][0])){
					anet.port = argv[argi++];
				}
			}

/* Make the outbound connection */
			struct anet_cl_connection cl = find_connection(&anet, NULL);
			if (!cl.state){
				if (anet.key)
					fprintf(stderr, "couldn't connect to any host for key %s\n", anet.key);
				else
					fprintf(stderr, "couldn't connect to %s\n", anet.host);

				return EXIT_FAILURE;
			}

			if (global.probe_only){
				printf("authenticated:remote_mode=%d\n", a12_remote_mode(cl.state));
				shutdown(cl.fd, SHUT_RDWR);
				close(cl.fd);
				return EXIT_SUCCESS;
			}

/* Could also be a connection to a directory server, then we switch to a
 * different processing loop that globs list of available appls, sources
 * sinks and other directories. */
			int rc = 0;
			if (a12_remote_mode(cl.state) == ROLE_DIR){
				global.dircl.applname = global.reqname;
				global.dircl.die_on_list;
				global.dircl.basedir = global.directory;
				if (argi <= argc - 1){
					global.dircl.applname = argv[argi];
				}

				anet_directory_cl(cl.state, global.dircl, cl.fd, cl.fd);
			}
			else {
				rc = a12helper_a12srv_shmifcl(NULL, cl.state, NULL, cl.fd, cl.fd);
			}
			shutdown(cl.fd, SHUT_RDWR);
			close(cl.fd);

			return rc < 0 ? EXIT_FAILURE : EXIT_SUCCESS;
		}
		else
			return show_usage("No mode specified, please use -s or -l form");
	}

	char* errmsg;

/* enable asymetric encryption and keystore */
	const char* err;
	if (global.soft_auth){
		a12int_trace(A12_TRACE_SECURITY, "weak-security=password only");
		if (!global.no_default){
			a12int_trace(A12_TRACE_SECURITY, "no-security=default password");
		}
	}
	else {
		if (!open_keystore(&err)){
			return show_usage(err);
		}
/* We have a keystore and are listening for an inbound connection, make sure
 * that there is a local key defined that we can use for the reply. There is a
 * point to making this more refined by also allowing the keystore to define
 * specific reply pubk when marking a client as accepted in order to
 * differentiate in both direction */
		uint8_t priv[32];
		char* outhost;
		uint16_t outport;
		if (!a12helper_keystore_hostkey("default", 0, priv, &outhost, &outport)){
			uint8_t outp[32];
			a12helper_keystore_register("default", "127.0.0.1", 6680, outp);
			a12int_trace(A12_TRACE_SECURITY, "key_added=default");
		}
	}

/* the directory option is not applied through the mode/role but rather as part
 * of handover_setup, but before then (since we can chose between single or
 * forking) we should scan / cache the applstore - then devise a way to do
 * dynamic updates. */
	if (anet.mode == ANET_SHMIF_CL || anet.mode == ANET_SHMIF_EXEC){
		if (global.directory != -1){
			global.dirsrv.basedir = global.directory;
			anet_directory_srv_rescan(&global.dirsrv);
		}
		switch (anet.mt_mode){
		case MT_SINGLE:
			anet_listen(&anet, &errmsg, single_a12srv, &meta);
			fprintf(stderr, "%s", errmsg ? errmsg : "");
		case MT_FORK:
			anet_listen(&anet, &errmsg, fork_a12srv, &meta);
			fprintf(stderr, "%s", errmsg ? errmsg : "");
			free(errmsg);
		break;
		default:
		break;
		}
		return EXIT_FAILURE;
	}

/* we have one shmif connection pre-established that should be mapped to
 * an outbound connection (ARCAN_CONNPATH=a12.. */
	if (anet.mode == ANET_SHMIF_SRV_INHERIT){
		return a12_preauth(&anet, a12cl_dispatch);
	}

/* ANET_SHMIF_SRV */
	switch (anet.mt_mode){
	case MT_SINGLE:
		return a12_connect(&anet, a12cl_dispatch);
	break;
	case MT_FORK:
		return a12_connect(&anet, fork_a12cl_dispatch);
	break;
	default:
		return EXIT_FAILURE;
	break;
	}
}
