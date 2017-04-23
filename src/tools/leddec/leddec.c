/*
 * Quick and dirty arcan_led FIFO protocol decoder
 */
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <stdbool.h>
#include <stdint.h>
#include <fcntl.h>
#include <poll.h>
#include <arcan_shmif.h>

static struct arcan_shmif_cont con;
static bool con_dirty;

static void commit(int led, uint8_t rv, uint8_t gv, uint8_t bv, bool buf)
{
	if (con.addr){
		if (-1 == led){
			for (size_t i = 0; i < 256; i++)
				con.vidp[i] = SHMIF_RGBA(rv, gv, bv, 255);
		}
		else if (led < 256 && led >= 0)
			con.vidp[led] = SHMIF_RGBA(rv, gv, bv, 255);
		con_dirty = true;
	}

	printf("%d(%d, %d, %d)%s", led,
		(int) rv, (int) gv, (int) bv, buf ? "+" : "=\n");
}

int main(int argc, char** argv)
{
	if (2 != argc){
		printf("usage: leddec /path/to/ledpipe (fifo)\n");
		return EXIT_FAILURE;
	}

	if (getenv("ARCAN_CONNPATH")){
		con = arcan_shmif_open(SEGID_MEDIA, 0, NULL);
		if (con.addr)
			arcan_shmif_resize(&con, 256, 1);
	}

	int fd = open(argv[1], O_RDONLY);
	if (-1 == fd){
		printf("couldn't open %s\n", argv[1]);
		return EXIT_FAILURE;
	}

	bool done = false;
	int led = -1;
	uint8_t rv, gv, bv;
	rv = gv = bv = 0;

	while(!done){
		uint8_t buf[2];
		if (2 != read(fd, buf, 2)){
			printf("read != 2\n");
			break;
		}
		switch(buf[0]){
		case 'A': led = -1; break;
		case 'a': led = buf[1]; break;
		case 'r': rv = buf[1]; break;
		case 'g': gv = buf[1]; break;
		case 'b': bv = buf[1]; break;
		case 'i': rv = gv = bv = buf[1]; break;
		case 'c': commit(led, rv, gv, bv, buf[1] != 0); break;
		case 'o': printf("\nshutdown\n"); done = true; break;
		default:
			printf("\ndata corruption (%d, %d)\n", (int)buf[0], (int)buf[1]);
		break;
		}

/* only synch when we've flushed the incoming buffer */
		if (con_dirty){
			struct pollfd pfd = {
				.fd = fd,
				.events = POLLIN
			};
			if (0 == poll(&pfd, 1, 0)){
				con_dirty = false;
				arcan_shmif_signal(&con, SHMIF_SIGVID);
			}
		}
	}

	close(fd);
	return EXIT_SUCCESS;
}
