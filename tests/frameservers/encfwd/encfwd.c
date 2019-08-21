#include <arcan_shmif.h>

int main(int argc, char** argv)
{
	if (argc != 3){
		printf("usage: encfwd cp1(input:encode) cp2(forward:media)\n");
		return EXIT_FAILURE;
	}

	setenv("ARCAN_CONNPATH", argv[1], 1);
	struct arcan_shmif_cont enc =
		arcan_shmif_open(SEGID_ENCODER, SHMIF_ACQUIRE_FATALFAIL, NULL);
	printf("encoder connected: %zu, %zu\n", enc.w, enc.h);

	setenv("ARCAN_CONNPATH", argv[2], 1);
	struct arcan_shmif_cont fwd =
		arcan_shmif_open(SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, NULL);

	for (;;){
		struct arcan_event ev;

/* check the main segment for the encoder reply */
		if (fwd.w != enc.w || fwd.h != enc.h){
			if (!arcan_shmif_resize(&fwd, enc.w, enc.h)){
				fprintf(stderr, "couldn't synch src-dst size(%zu*%zu)\n", enc.w, enc.h);
				break;
			}
		}

		int rv = arcan_shmif_poll(&enc, &ev);
		if (rv < 0){
			fprintf(stderr, "poll failed on enc (source)\n");
			break;
		}

/* naively assume same forward and pitch, just memcpy */
		if (ev.category == EVENT_TARGET &&
			ev.tgt.kind == TARGET_COMMAND_STEPFRAME)
		{
			memcpy(fwd.vidp, enc.vidp, enc.w * enc.h * sizeof(shmif_pixel));
			arcan_shmif_signal(&enc, SHMIF_SIGVID);
			arcan_shmif_signal(&fwd, SHMIF_SIGVID);
		}

/* just flush */
		while ((rv = arcan_shmif_poll(&fwd, &ev) > 0)){}
		if (rv < 0){
			fprintf(stderr, "poll failed on fwd\n");
			break;
		}
	}

	arcan_shmif_drop(&enc);
	arcan_shmif_drop(&fwd);
	return EXIT_SUCCESS;
}
