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

static void commit(int led, uint8_t rv, uint8_t gv, uint8_t bv, bool buf)
{
	printf("%d(%d, %d, %d)%s", led,
		(int) rv, (int) gv, (int) bv, buf ? "+" : "=\n");
}

int main(int argc, char** argv)
{
	if (2 != argc){
		printf("usage: leddec /path/to/ledpipe (fifo)\n");
		return EXIT_FAILURE;
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
	}

	close(fd);
	return EXIT_SUCCESS;
}
