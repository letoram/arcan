#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>
#include <pthread.h>
#include <time.h>
#include <math.h>

#include <arcan_shmif.h>

static shmif_pixel palette[] = {
	SHMIF_RGBA(0xff, 0x00, 0x00, 0xff),
	SHMIF_RGBA(0x00, 0xff, 0x00, 0xff),
	SHMIF_RGBA(0x00, 0x00, 0xff, 0xff),
	SHMIF_RGBA(0xff, 0xff, 0x00, 0xff),
	SHMIF_RGBA(0xff, 0x00, 0xff, 0xff),
	SHMIF_RGBA(0x00, 0xff, 0xff, 0xff),
	SHMIF_RGBA(0xff, 0xff, 0xff, 0xff)
};

static float tones[] = {
	16.35, 18.35, 20.60, 21.83, 24.50, 27.50, 30.87, 32.70,
	30.87, 27.50, 24.50, 21.83, 20.60, 18.35
};

static int pi = 0;
static int ti = 0;
static float pos = 0;

static long long time_ms()
{
	struct timespec tp;
	clock_gettime(CLOCK_MONOTONIC_RAW, &tp);
	return (tp.tv_sec * 1000) + (tp.tv_nsec / 1000000);
}

static void* aprod(void* data)
{
	struct arcan_shmif_cont* cont = data;
	size_t bps = ARCAN_SHMIF_ACHANNELS * sizeof(shmif_asample);

	while (1){
		size_t nsamp = (cont->abufsize - cont->abufused) / (bps * 2);
		float stepv = 2.0 * 3.14 * ((5 * tones[ti]) / (float)cont->samplerate);
		for (size_t b = 0; b < cont->abuf_cnt; b++){
			for (size_t i = 0; i < nsamp; i++){
				cont->audp[i*2+0] = 32767.0 * sinf(pos);
				cont->audp[i*2+1] = 32767.0 * sinf(pos);
				pos += stepv;
			}
			cont->abufused = nsamp * bps;
			arcan_shmif_signal(cont, SHMIF_SIGAUD);
		}
	}

	return NULL;
}

static void step(struct arcan_shmif_cont* cont)
{
	printf("pre;%lld;%d;%d\n", time_ms(), pi, ti);
	pi = (pi + 1) % (sizeof(palette) / sizeof(palette[0]));
	ti = (ti + 1) % (sizeof(tones) / sizeof(tones[0]));
	size_t count = cont->pitch * cont->h;
	for (size_t i = 0; i < count; i++)
		cont->vidp[i] = palette[pi];

/* will create pop:ing as any queued buffers are dropped */
	arcan_shmif_enqueue(cont, &(arcan_event){
		.tgt.kind = ARCAN_EVENT(FLUSHAUD)
	});
	arcan_shmif_signal(cont, SHMIF_SIGVID);
	printf("post;%lld;%d;%d\n", time_ms(), pi, ti);
}

int main(int argc, char** argv)
{
	struct arg_arr* aarr;
	if (argc != 7){
		printf("usage: \n\tavlat w h vbuf_count abuf_count abuf_sz samplerate\n");
			return EXIT_FAILURE;
	}

	int w = strtoul(argv[1], NULL, 10);
	int h = strtoul(argv[2], NULL, 10);

	struct shmif_resize_ext ext_sz = {
		.vbuf_cnt = strtoul(argv[3], NULL, 10),
		.abuf_cnt = strtoul(argv[4], NULL, 10),
		.abuf_sz = strtoul(argv[5], NULL, 10),
		.samplerate = strtoul(argv[6], NULL, 10)
	};

	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	if (!arcan_shmif_resize_ext(&cont, w, h, ext_sz)){
		printf("failed to set buffer properties\n");
		return EXIT_FAILURE;
	}

	printf("context: %d * %d, %d bytes @ %d Hz",
		(int)cont.w, (int)cont.h, (int)cont.abufsize, (int)cont.samplerate);

	step(&cont);
	ti = 0;

	pthread_t athread;
	pthread_create(&athread, NULL, aprod, (void*) &cont);

	arcan_event ev;
	while (arcan_shmif_wait(&cont, &ev)){
		if (ev.category == EVENT_TARGET)
		switch (ev.tgt.kind){
		case TARGET_COMMAND_EXIT:
			return EXIT_SUCCESS;
		break;
		default:
		break;
		}
		else if (ev.category == EVENT_IO){
			switch (ev.io.datatype){
				case EVENT_IDATATYPE_TRANSLATED:
					if (ev.io.input.translated.active)
						step(&cont);
				break;
				case EVENT_IDATATYPE_DIGITAL:
					if (ev.io.input.digital.active)
						step(&cont);
				break;
				default:
				break;
			}
		}
	}

	return EXIT_SUCCESS;
}
