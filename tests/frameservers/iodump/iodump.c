#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>
#include <inttypes.h>

const char* msub_to_lbl(int ind)
{
	switch(ind){
	case MBTN_LEFT_IND: return "left";
	case MBTN_RIGHT_IND: return "right";
	case MBTN_MIDDLE_IND: return "middle";
	case MBTN_WHEEL_UP_IND: return "wheel-up";
	case MBTN_WHEEL_DOWN_IND: return "wheel-down";
	default:
		return "unknown";
	}
}

static void dump_eof(int fd)
{
	FILE* fin = fdopen(dup(fd), "r");
	if (!fin)
		return;

	char inb[1024];
	while(1){
		char* buf = fgets(inb, 1024, fin);
		if (!buf)
			break;
		printf("read: %s\n", buf);
	}

	fclose(fin);
}

static void write_eof(int fd)
{
	FILE* fout = fdopen(dup(fd), "w");
	if (!fout)
		return;

	int i = 0;
	while(1){
		if (fprintf(fout, "%d\n", i++) < 0)
			break;
	}

	fclose(fout);
}

static void dump_event(struct arcan_event ev)
{
	printf("%s\n", arcan_shmif_eventstr(&ev, NULL, 0));
}

int main(int argc, char** argv)
{
	int id = SEGID_APPLICATION;
	struct arg_arr* aarr;
	if (argc > 1){
		if (strcmp(argv[1], "-game") == 0)
			id = SEGID_GAME;
		else if (strcmp(argv[1], "-terminal") == 0)
			id = SEGID_TERMINAL;
		else if (strcmp(argv[1], "-vm") == 0)
			id = SEGID_VM;
		else{
			printf("usage: \n\tiodump to identify as normal application"
				"\n\tiodump -game to identify as game"
				"\n\tiodump -terminal to identify as terminal"
				"\n\tiodump -vm to identify as vm\n"
			);
				return EXIT_FAILURE;
			}
		}

	struct arcan_shmif_cont cont = arcan_shmif_open(
		id, SHMIF_ACQUIRE_FATALFAIL, &aarr);
	printf("open\n");

	arcan_event ev;

/* just send garbage so the correct events are being propagated */
	arcan_shmif_signal(&cont, SHMIF_SIGVID);
	printf("loop\n");
	while (arcan_shmif_wait(&cont, &ev)){
		dump_event(ev);
	}

	return EXIT_SUCCESS;
}
