/*
 * Simple implementation of a client/server proxy.
 */
#include <arcan_shmif.h>
#include <arcan_shmif_server.h>
#include <errno.h>
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

enum mt_mode {
	MT_SINGLE = 0,
	MT_FORK = 1
};

static const char* trace_groups[] = {
	"video",
	"audio",
	"system",
	"event",
	"missing",
	"alloc",
	"crypto",
	"vdetail",
	"btransfer"
};

static int tracestr_to_bitmap(char* work)
{
	int res = 0;
	char* pt = strtok(work, ",");
	while(pt != NULL){
		for (size_t i = 0; i < COUNT_OF(trace_groups); i++){
			if (strcasecmp(trace_groups[i], pt) == 0){
				res |= 1 << i;
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

/*
 * in this mode we should really fexec ourselves so we don't risk exposing
 * aslr or canaries, as well as handle the key-generation
 */
static void fork_a12srv(struct a12_state* S, int fd, void* tag)
{
	pid_t fpid = fork();
	if (fpid == 0){
/* Split the log output on debug so we see what is going on */
#ifdef _DEBUG
		char buf[sizeof("cl_log_xxxxxx.log")];
		snprintf(buf, sizeof(buf), "cl_log_%.6d.log", (int) getpid());
		FILE* fpek = fopen(buf, "w+");
		if (fpek){
			a12_set_trace_level(a12_trace_targets, fpek);
		}
		fclose(stderr);
#endif
/* we should really re-exec ourselves with the 'socket-passing' setup so that
 * we won't act as a possible ASLR break */
		arcan_shmif_privsep(NULL, "shmif", NULL, 0);
		int rc = a12helper_a12srv_shmifcl(S, NULL, fd, fd);
		exit(rc < 0 ? EXIT_FAILURE : EXIT_SUCCESS);
	}
	else if (fpid == -1){
		a12int_trace(A12_TRACE_SYSTEM, "couldn't fork/dispatch, ulimits reached?\n");
		a12_channel_close(S);
		close(fd);
		return;
	}
	else {
/* just ignore and return to caller */
		a12_channel_close(S);
		close(fd);
	}
}

static void single_a12srv(struct a12_state* S, int fd, void* tag)
{
	a12helper_a12srv_shmifcl(S, NULL, fd, fd);
}

static void a12cl_dispatch(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd)
{
/* note that the a12helper will do the cleanup / free */
	a12helper_a12cl_shmifsrv(S, cl, fd, fd, (struct a12helper_opts){
		.dirfd_temp = -1,
		.dirfd_cache = -1,
		.redirect_exit = args->redirect_exit,
		.devicehint_cp = args->devicehint_cp
	});
}

static void fork_a12cl_dispatch(
	struct anet_options* args,
	struct a12_state* S, struct shmifsrv_client* cl, int fd)
{
	pid_t fpid = fork();
	if (fpid == 0){
/* missing: extend sandboxing, close stdio */
		a12helper_a12cl_shmifsrv(S, cl, fd, fd, (struct a12helper_opts){
			.dirfd_temp = -1,
			.dirfd_cache = -1,
			.redirect_exit = args->redirect_exit,
			.devicehint_cp = args->devicehint_cp
		});
		exit(EXIT_SUCCESS);
	}
	else if (fpid == -1){
		fprintf(stderr, "fork_a12cl() couldn't fork new process, check ulimits\n");
		shmifsrv_free(cl, true);
		a12_channel_close(S);
		return;
	}
	else {
/* just ignore and return to caller */
		a12int_trace(A12_TRACE_SYSTEM, "client handed off to %d", (int)fpid);
		a12_channel_close(S);

		if (args->redirect_exit){
			shmifsrv_free(cl, false);
		}
		else
			shmifsrv_free(cl, true);

		close(fd);
	}
}

/* connect / authloop shmifsrv */
static struct anet_cl_connection forward_shmifsrv_cl(
	struct shmifsrv_client* cl, struct anet_options* opts)
{
	struct anet_cl_connection anet = {};
	int rc = opts->retry_count;
	int timesleep = 1;

/* connect loop until retry count exceeded */
	while (rc != 0 && shmifsrv_poll(cl) != CLIENT_DEAD){
		anet = anet_cl_setup(opts);

		if (anet.state)
			break;

		if (!anet.state){
			fputs(stderr, anet.errmsg);
			free(anet.errmsg);
			anet.errmsg = NULL;

			if (timesleep < 10)
				timesleep++;

			if (rc > 0)
				rc--;

			sleep(timesleep);
			continue;
		}
	}

/* failed, or retry-count exceeded? */
	if (!anet.state || shmifsrv_poll(cl) == CLIENT_DEAD){
		shmifsrv_free(cl, true);

		if (anet.state){
			a12_free(anet.state);
			close(anet.fd);

			if (anet.errmsg)
				free(anet.errmsg);
		}
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
		return EXIT_FAILURE;
	}

	struct anet_cl_connection anet = forward_shmifsrv_cl(cl, args);

/* and ack the connection */
	dispatch(args, anet.state, cl, anet.fd);

	return EXIT_SUCCESS;
}

static bool show_usage(const char* msg)
{
	fprintf(stderr, "%s%sUsage:\n"
	"\tForward local arcan applications: arcan-net [-Xtd] -s connpoint [keyid@]host port\n"
	"\t                                  (inherit socket) -S fd_no host port\n"
	"\tBridge remote arcan applications: arcan-net [-Xtd] -l port [ip]\n\n"
	"Forward-local options:\n"
	"\t-X            \t Disable EXIT-redirect to ARCAN_CONNPATH env (if set)\n"
	"\t-r, --retry n \t Limit retry-reconnect attempts to 'n' tries\n\n"
	"Options:\n"
	"\t-b dir        \t Set basedir to <dir> (for config, keys/ accepted/ cache/)\n"
	"\t-a, --auth n  \t (Registering key) read authentication string from stdin\n"
	"\t              \t overrides possible A12_BASE_DIR environment\n"
	"\t-t            \t Single- client (no fork/mt)\n"
	"\t-d bitmap     \t set trace bitmap (bitmask or key1,key2,...)\n"
	"\nTrace groups (stderr):\n"
	"\tvideo:1      audio:2      system:4    event:8      transfer:16\n"
	"\tdebug:32     missing:64   alloc:128  crypto:256    vdetail:512\n"
	"\tbtransfer:1024\n\n", msg, msg ? "\n" : ""
	);
	return false;
}

static bool apply_commandline(int argc, char** argv, struct anet_options* opts)
{
	const char* modeerr = "Mixed or multiple -s or -l arguments";

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

			opts->mode = ANET_SHMIF_SRV;
			if (i >= argc - 1)
				return show_usage("Invalid arguments, -s without room for ip");
			opts->cp = argv[++i];

			for (size_t ind = 0; opts->cp[ind]; ind++)
				if (!isalnum(opts->cp[ind]))
					return show_usage("Invalid character in connpoint [a-Z,0-9]");

			if (i == argc)
				return show_usage("-s without room for host/port");

			opts->host = argv[++i];

			if (i == argc)
				return show_usage("-s without room for port");

			opts->port = argv[++i];

			if (i != argc - 1)
				return show_usage("Trailing arguments to -s connpoint host port");

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
				return show_usage("-S without room for host/port");

			opts->host = argv[++i];

			if (i == argc)
				return show_usage("-S without room for port");

			opts->port = argv[++i];

			if (i != argc - 1)
				return show_usage("Trailing arguments to -S fd_in host port");
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

			if (i < argc - 1)
				opts->host = argv[++i];

			if (i != argc - 1)
				return show_usage("Trailing arguments to -l port");
		}
		else if (strcmp(argv[i], "-t") == 0){
			opts->mt_mode = MT_SINGLE;
		}
		else if (strcmp(argv[i], "-X") == 0){
			opts->redirect_exit = NULL;
		}
		else if (strcmp(argv[i], "-r") == 0 || strcmp(argv[i], "--retry") == 0){
			if (1 < argc - 1){
				opts->retry_count = (ssize_t) strtol(argv[++i], NULL, 10);
			}
			else
				return show_usage("Missing count argument to -r,--retry");
		}
	}

	return true;
}

int main(int argc, char** argv)
{
	struct anet_options anet = {
		.retry_count = -1,
		.mt_mode = MT_FORK
	};
	anet.opts = a12_sensitive_alloc(sizeof(struct a12_context_options));

/* set this as default, so the remote side can't actually close */
	anet.redirect_exit = getenv("ARCAN_CONNPATH");
	anet.devicehint_cp = getenv("ARCAN_CONNPATH");

	if (!apply_commandline(argc, argv, &anet))
		return show_usage("Invalid arguments");

/* parsing done, route to the right connection mode */
	if (!anet.mode)
		return show_usage("No mode specified, please use -s or -l form");

	char* errmsg;

	if (anet.mode == ANET_SHMIF_CL){
		switch (anet.mt_mode){
		case MT_SINGLE:
			anet_listen(&anet, &errmsg, single_a12srv, NULL);
			fprintf(stderr, "%s", errmsg ? errmsg : "");
		case MT_FORK:
			anet_listen(&anet, &errmsg, fork_a12srv, NULL);
			fprintf(stderr, "%s", errmsg ? errmsg : "");
			free(errmsg);
		break;
		default:
		break;
		}
		return EXIT_FAILURE;
	}
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
