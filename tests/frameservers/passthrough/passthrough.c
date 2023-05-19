#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

ssize_t find_beg(uint8_t* buf, size_t lim)
{
	for (size_t i = 0; i <= lim-4; i++){
		if (buf[i+0] == 0 && buf[i+1] == 0 && buf[i+2] == 0 && buf[i+3] == 1)
			return i;
	}

	return -1;
}

static bool fill_frame(struct arcan_shmif_cont *C, struct arcan_shmif_venc* venc, FILE* fpek)
{
/* just check for the next 00 00 00 01, assuming we are at one */
	ssize_t nep;
	if (venc->framesize > 4 && (nep = find_beg(&C->vidb[4], venc->framesize-4)) > 0){
		ssize_t tmp = venc->framesize;
		venc->framesize = nep + 4;
		arcan_shmif_signal(C, SHMIF_SIGVID);
		memmove(C->vidb, &C->vidb[venc->framesize], tmp - venc->framesize);
		venc->framesize = tmp - venc->framesize;
		return true;
	}

/* eof? just send the last one off */
	if (feof(fpek)){
		if (venc->framesize)
			arcan_shmif_signal(C, SHMIF_SIGVID);
		return false;
	}

/* fill up to a cap or give up if we exceed */
	size_t max = C->w * C->h * sizeof(shmif_pixel);
	if (venc->framesize >= max)
		return false;

	size_t ntr = max - venc->framesize;

	venc->framesize += fread(&C->vidb[venc->framesize], 1, ntr, fpek);

/* and try the sweep or buffer again */
	return fill_frame(C, venc, fpek);
}

#ifdef ENABLE_FSRV_AVFEED
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
#else
int main(int argc, char** argv)
#endif
{
	if (argc <= 4){
		printf("use: passthrough file width height\n");
		return EXIT_FAILURE;
	}

	FILE* fpek = fopen(argv[1], "r");
	if (!fpek){
		printf("couldn't open %s for input\n", argv[1]);
		return EXIT_FAILURE;
	}

/* should get w/h from h264 */
	struct arcan_shmif_cont C;
	C = arcan_shmif_open(SEGID_MEDIA, SHMIF_ACQUIRE_FATALFAIL, NULL);
	C.hints = SHMIF_RHINT_VSIGNAL_EV;

venc:
	arcan_shmif_resize_ext(&C, strtoul(argv[3], NULL, 10), strtoul(argv[4], NULL, 10),
		(struct shmif_resize_ext){
			.meta = SHMIF_META_VENC,
		}
	);

	struct arcan_shmif_venc* venc = arcan_shmif_substruct(&C, SHMIF_META_VENC).venc;
	if (!venc){
		printf("server rejected codec passthrough\n");
		goto out;
	}

	venc->fourcc[0] = 'H';
	venc->fourcc[1] = '2';
	venc->fourcc[2] = '6';
	venc->fourcc[3] = '4';

/* one frame might contain several logical ones */
	if (!fill_frame(&C, venc, fpek)){
		printf("input source didn't have bytestream delimiter\n");
		goto out;
	}

	arcan_event ev;
	while(arcan_shmif_wait(&C, &ev) && !feof(fpek)){
		if (ev.category != EVENT_TARGET)
			continue;

		switch (ev.tgt.kind){
			case TARGET_COMMAND_EXIT:
				goto out;
			break;
	/* the next step for this test would be to handover to afsrv_decode
	 * ourselves but since the context is already mapped it is harder .. */
			case TARGET_COMMAND_BUFFER_FAIL:
				printf("server couldn't decode encoded frame\n");
				arcan_shmif_drop(&C);
			break;
			case TARGET_COMMAND_STEPFRAME:
			if (!fill_frame(&C, venc, fpek)){
				printf("frame chunking failed\n");
				arcan_shmif_drop(&C);
			}
			break;
			case TARGET_COMMAND_RESET:
				printf("lost venc state, re-requesting\n");
				goto venc;
			break;
			default:
			break;
		}
	}
out:
	arcan_shmif_drop(&C);
	return EXIT_SUCCESS;
}
