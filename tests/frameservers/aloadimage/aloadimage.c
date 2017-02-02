/*
 * Simple image viewer with playlist support,
 * intended for testing linear/sRGB/float transfer modes
 * but possibly also extend enough to match xloadimage
 *
 * missing controls:
 * - click+drag to pan
 * - mouse-wheel to zoom
 * - middle click to force-scale
 * - right click to force window size to source size
 */

#include <arcan_shmif.h>
#include <unistd.h>

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image.h"
#include "stb_image_resize.h"

static shmif_pixel pad_px = SHMIF_RGBA(0, 0, 0, 0xff);

/* asserts (w <= out->w, h <= out->h or scale is set */
static void blit(struct arcan_shmif_cont* out,
	uint8_t* raw, int x, int y, int w, int h, int bstride, bool scale)
{
	stbir_resize_uint8(&raw[y*bstride+x*4], w, h, bstride,
		out->vidb, out->w, out->h, out->stride, 4);

	arcan_shmif_signal(out, SHMIF_SIGVID);
}

static void set_ident(struct arcan_shmif_cont* out, const char* str)
{
	struct arcan_event ev = {.ext.kind = ARCAN_EVENT(IDENT)};
	size_t lim = sizeof(ev.ext.message.data)/sizeof(ev.ext.message.data[1]);
	size_t len = strlen(str);

	if (len > lim)
		str += len - lim - 1;

	snprintf((char*)ev.ext.message.data, lim, "%s", str);
	arcan_shmif_enqueue(out, &ev);
}

int main(int argc, char** argv)
{
	if (argc <= 1){
		fprintf(stderr, "use: pngview [opts] file1 file2 .. filen \n");
		return EXIT_FAILURE;
	}

	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_MEDIA, SHMIF_ACQUIRE_FATALFAIL, NULL);

	int carg = 1;
	int minarg = 1;
	int step_timer = 0, init_timer = 0;

/* for automatic playlist stepping */
	if (step_timer)
		arcan_shmif_enqueue(&cont, &(struct arcan_event){
			.ext.kind = ARCAN_EVENT(CLOCKREQ),
			.ext.clock.rate = 25
		});

	while (minarg < argc){
		int w, h, f;
		const char* fn = argv[carg++];
		uint8_t* res = stbi_load(fn, &w, &h, &f, 4);
		carg++;
		if (!res){
			fprintf(stderr, "failed to load: %s\n", fn);
			continue;
		}
		set_ident(&cont, fn);
		blit(&cont, res, 0, 0, w, h, w * 4, true);

		arcan_event ev;
		bool step = false;
		while (!step && arcan_shmif_wait(&cont, &ev)){
			if (ev.category == EVENT_TARGET)
			switch (ev.tgt.kind){
				case TARGET_COMMAND_DISPLAYHINT:
					if (ev.tgt.ioevs[0].iv && ev.tgt.ioevs[1].iv &&
						arcan_shmif_resize(&cont, ev.tgt.ioevs[0].iv, ev.tgt.ioevs[1].iv))
						blit(&cont, res, 0, 0, w, h, w * 4, true);
				break;
				case TARGET_COMMAND_STEPFRAME:
					if (step_timer > 0){
						step_timer--;
						if (step_timer == 0){
							step_timer = init_timer;
							step = true;
						}
					}
				break;
				case TARGET_COMMAND_EXIT:
				arcan_shmif_drop(&cont);
				return EXIT_SUCCESS;
			break;
			default:
			break;
			}
		}

		free(res);
	}

	return EXIT_SUCCESS;
}
