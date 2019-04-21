/*
 * Simple implementation of a client/server proxy.
 */
#include <arcan_shmif.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <poll.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/wait.h>
#include "a12_int.h"
#include "a12.h"
#include "a12_helper.h"

static int run_shmif_server(
	uint8_t* authk, size_t auth_sz, const char* cp, int fdin, int fdout)
{
	int fd = -1;

/* set to non-blocking */
	int flags = fcntl(fdout, F_GETFL);
	fcntl(fdout, F_SETFL, flags | O_NONBLOCK);
	flags = fcntl(fdin, F_GETFL);
	fcntl(fdin, F_SETFL, flags | O_NONBLOCK);

/* repeatedly open the same connection point, then depending on if we are in piped
 * mode (single client) or socketed mode we fork off a server */
	while(true){
		struct shmifsrv_client* cl =
			shmifsrv_allocate_connpoint(cp, NULL, S_IRWXU, fd);

		if (!cl){
			fprintf(stderr, "couldn't allocate connection point\n");
			return EXIT_FAILURE;
		}

/* extract handle first time */
		if (-1 == fd)
			fd = shmifsrv_client_handle(cl);

		if (-1 == fd){
			fprintf(stderr,
				"descriptor allocator failed, couldn't open connection point\n");
			return EXIT_FAILURE;
		}

		struct pollfd pfd = { .fd = fd, .events = POLLIN | POLLERR | POLLHUP };
		debug_print(1, "(srv) configured, polling");
		if (poll(&pfd, 1, -1) == 1){
			debug_print(1, "(srv) got connection");

/* go through the accept step, now we can hand the connection over
 * and repeat the listening stage in some other execution context,
 * here's the point to thread or multiprocess */
			if (pfd.revents == POLLIN){
				shmifsrv_poll(cl);

/* build the a12 state and hand it over to the main loop */
				a12helper_a12cl_shmifsrv(a12_channel_open(
					authk, auth_sz), cl, fdin, fdout, (struct a12helper_opts){});
			}

			if (pfd.revents & (~POLLIN)){
				debug_print(1, "(srv) poll failed, rebuilding");
				shmifsrv_free(cl);
			}
		}
/* SIGINTR */
		else
			break;

/* wait until something happens */
	}
	return EXIT_SUCCESS;
}

static int run_shmif_client(
	uint8_t* authk, size_t authk_sz, int fdin, int fdout)
{
	struct a12_state* ast = a12_channel_build(authk, authk_sz);
	if (!ast){
		fprintf(stderr, "Couldn't allocate client state machine\n");
		return EXIT_FAILURE;
	}

	return a12helper_a12srv_shmifcl(ast, NULL, fdin, fdout);
}

static int killpipe[] = {-1, -1};
static void test_handler()
{
	wait(NULL);
	close(killpipe[0]);
	close(killpipe[1]);
}

static int run_shmif_test(uint8_t* authk, size_t auth_sz, bool sp)
{
	signal(SIGCHLD, test_handler);
	int clpipe[2];
	int srvpipe[2];

	pipe(clpipe);
	pipe(srvpipe);

/* just ugly- sleep and assume that the server has been setup */
	if (fork() > 0){
		if (sp){
//			close(clpipe[1]); close(srvpipe[0]);
			while (1)
				run_shmif_client(authk, auth_sz, clpipe[0], srvpipe[1]);
		}
//		close(clpipe[0]); close(srvpipe[1]);
		return run_shmif_server(authk, auth_sz, "test", srvpipe[0], clpipe[1]);
	}

#define STDERR_CHILD
#ifdef STDERR_CHILD
	fclose(stderr);
	stderr = fopen("child.stderr", "w+");
#else
#endif
	if (sp){
		close(clpipe[0]); close(srvpipe[1]);
		killpipe[0] = srvpipe[0]; killpipe[1] = clpipe[1];
		return run_shmif_server(authk, auth_sz, "test", srvpipe[0], clpipe[1]);
	}
	close(clpipe[1]); close(srvpipe[0]);
	killpipe[0] = clpipe[0]; killpipe[1] = srvpipe[1];
	while (1)
		run_shmif_client(authk, auth_sz, clpipe[0], srvpipe[1]);
}

static int show_usage(const char* n, const char* msg)
{
	fprintf(stderr, "%s\nUsage:\n\t%s client mode: arcan-net -c"
	"\n\t%s server mode: arcan-net -s connpoint\n"
	"\t%s testing mode: arcan-net -t(server main) or -T (client main)"
	"\nshared:"
	"\n\t -k keyfile: authkey, use authentication key from [authkey]"
	"\n\t -v method, force video compression (rgba, rgb, rgb565, dpng, h264)\n", msg, n, n, n);
	return EXIT_FAILURE;
}

int main(int argc, char** argv)
{
	uint8_t authk[64] = {0};
	size_t authk_sz = 64;

	const char* cp = NULL;
	int mode = 0;

	size_t i = 1;
	for (; i < argc; i++){
		if (strcmp(argv[i], "-k") == 0){
			i++;
			if (i == argc)
				return show_usage(argv[i], "missing keyfile argument");
			else {
				FILE* fpek = fopen(argv[i], "r");
				if (!fpek)
					return show_usage(argv[i], "keyfile couldn't be read");
				authk_sz = fread(authk, 1, 64, fpek);
				fclose(fpek);
			}
		}
		else if (strcmp(argv[i], "-s") == 0){
			i++;
			if (i == argc)
				return show_usage(argv[i], "missing connection point argument");
			mode = 1;
			cp = argv[i];
			break;
		}
		else if (strcmp(argv[i], "-c") == 0){
			mode = 2;
			break;
		}
		else if (strcmp(argv[i], "--test") == 0 || strcmp(argv[i], "-t") == 0){
			mode = 3;
			break;
		}
		else if (strcmp(argv[i], "--TEST") == 0 || strcmp(argv[i], "-T") == 0){
			mode = 4;
			break;
		}
	}

	if (mode == 3 || mode == 4){
		if (!getenv("ARCAN_CONNPATH")){
			fprintf(stderr, "Test mode: No ARCAN_CONNPATH env\n");
			return EXIT_FAILURE;
		}
		return run_shmif_test(authk, authk_sz, mode == 3);
	}

	if (isatty(STDIN_FILENO) || isatty(STDOUT_FILENO))
		return show_usage(argv[0], "[stdin] / [stdout] should not be TTYs\n");

	if (mode == 0)
		return show_usage(argv[0], "missing connection mode (-c or -s)");

/*
 * continue to sweep for a -x argument, if found, setup pipes, fork, exec.
 */
	if (mode == 1)
		return run_shmif_server(authk, authk_sz, cp, STDIN_FILENO, STDOUT_FILENO);

	if (mode == 2)
		return run_shmif_client(authk, authk_sz, STDIN_FILENO, STDOUT_FILENO);

	return EXIT_SUCCESS;
}
