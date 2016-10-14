#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

#ifdef ENABLE_FSRV_AVFEED
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
#else
int main(int argc, char** argv)
#endif
{
	struct arg_arr* aarr;
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, &aarr);

	struct arcan_shmif_initial* init;
	if (sizeof(struct arcan_shmif_initial)
		!= arcan_shmif_initial(&cont, &init)){
		printf("couldn't query initial primary segment properties\n");
#ifndef ENABLE_FSRV_AVFEED
		return EXIT_FAILURE;
#endif
	}

	printf("initial properties:\n\
\twidth * height: %zu * %zu stride: %zu  pitch: %zu\n\
\taudio buffers: %d, audio buffer size: %d\n\
\tdensity: %f\n\
\tlang: %s, text_lang: %s, country: %s, UTF+%d\n\
\tlat: %f, long: %f, elev: %f\n\
disp_px_w: %zu, disp_px_h: %zu, disp_rgb: %d, disp_refresh: %d\n\
render_node: %d\n",
	cont.w, cont.h, cont.stride, cont.pitch,
	(int) cont.abuf_cnt, (int) cont.abufsize,
	init->density,
	init->lang, init->text_lang, init->country, init->timezone,
	init->latitude, init->longitude, init->elevation,
	init->display_width_px, init->display_height_px, init->rgb_layout, (int)init->rate,
	init->render_node);

	for (size_t i = 0; i < 4; i++){
		printf("font[%zu] = .fd = %d, .hint = %d, "
			".size_mm = %f, .size_pt = %zu\n", i, init->fonts[i].fd,
			init->fonts[i].hinting, init->fonts[i].size_mm,
			SHMIF_PT_SIZE(init->density, init->fonts[i].size_mm));
	}

#ifndef ENABLE_FSRV_AVFEED
	return EXIT_SUCCESS;
#endif
}
