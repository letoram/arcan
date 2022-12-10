#include <arcan_shmif.h>
#include <unistd.h>
#include <fcntl.h>

/* Should have the option for a more complete svg rasterizer/parser
 * here, with all the w3c-terrible that comes with it.
 *
 * Other possible vector candidates of repute would be HVIF of Haiku-OS.
 */
#define NANOSVG_IMPLEMENTATION
#define NANOSVG_ALL_COLOR_KEYWORDS
#define NSVG_RGB(r,g,b)( SHMIF_RGBA(r, g, b, 0x00) )
#include "parsers/nanosvg.h"
#define NANOSVGRAST_IMPLEMENTATION
#include "parsers/nanosvgrast.h"

#define STB_IMAGE_IMPLEMENTATION
#define STBI_NO_GIF
#define STBI_NO_PIC
#define STBI_NO_PNM
#define STBI_NO_PSD
#define STBI_NO_BMP

#include "stb_image.h"

#define STB_IMAGE_RESIZE_IMPLEMENTATION
#include "stb_image_resize.h"

#include "decode.h"
#include "platform_types.h"
#include "os_platform.h"

static struct {
	data_source source;
	map_region map;
	char nbyte;
	bool active;

	float ppcm;
	int pan_xy[2];
	float scale;
	NSVGimage* svg;
	NSVGrasterizer* rast;
	bool force_scale;
	bool pending_raster;
} current = {
	.scale = 1.0
};

static void release_current()
{
	if (!current.active)
		return;

	arcan_release_map(current.map);
	arcan_release_resource(&current.source);
	current.active = false;

	if (current.svg){
		nsvgDelete(current.svg);
		current.svg = NULL;
	}
}

static void reraster(struct arcan_shmif_cont* C)
{
	if (!current.pending_raster)
		return;

	if (!current.rast)
		current.rast = nsvgCreateRasterizer();

	size_t px_w = ceilf(current.svg->width * current.scale);
	size_t px_h = ceilf(current.svg->height * current.scale);

	if (px_w > PP_SHMPAGE_MAXW)
		px_w = PP_SHMPAGE_MAXW;

	if (px_h > PP_SHMPAGE_MAXH)
		px_h = PP_SHMPAGE_MAXH;

	if (!current.force_scale)
		arcan_shmif_resize(C, px_w, px_h);

	nsvgRasterize(current.rast, current.svg,
		current.pan_xy[0], current.pan_xy[1],
		current.scale, C->vidb, C->w, C->h, C->stride);

	current.pending_raster = false;
	arcan_shmif_signal(C, SHMIF_SIGVID);
}

static bool do_svg(struct arcan_shmif_cont* C)
{
	char* tmp = strdup(current.map.ptr);

	if (current.svg){
		nsvgDelete(current.svg);
		current.svg = NULL;
	}

	current.svg = nsvgParse(tmp, "px", current.ppcm * 2.54f);
	current.scale = 1;
	current.pan_xy[0] = 0;
	current.pan_xy[1] = 0;

	if (!current.svg)
		return false;

	current.pending_raster = true;
	free(tmp);
	return true;
}

/* try to find a segment size that fits both the permitted and the source, this
 * is naive and slow and we should possibly respect a displayhint in that case
 * (or if we receive an explicit displayhint, go with that) */
static void find_safe_fit(struct arcan_shmif_cont* C, size_t dw, size_t dh)
{
	int attempts = 0;
	while (dw && dh && !arcan_shmif_resize(C, dw, dh)){
		if (!attempts){
			if (dw > dh){
				float ratio = (float)dh / (float)dw;
				dw = PP_SHMPAGE_MAXW;
				dh = dw * ratio;
				attempts++;
			}
		else {
			float ratio = (float)dw / (float)dh;
			dh = PP_SHMPAGE_MAXH;
			dw = dh * ratio;
			attempts++;
		}
		continue;
	}
	dw >>= 1;
	dh >>= 1;
	attempts++;
	}
}

static bool do_file(struct arcan_shmif_cont* C, int inf)
{
	release_current();

	current.source = (data_source){
		.fd = inf
	};

/* mapping writeable ensures we have an in-memory copy that nsvg can deal with
 * and that won't be 'streamed' */
	current.map = arcan_map_resource(&current.source, true);

	if (!current.map.ptr){
		arcan_release_resource(&current.source);
		return false;
	}

	if (current.map.sz < 5){
		return false;
	}

/* special-case SVG where we can / should reraster on DPI change */
	if (strncmp(current.map.ptr, "<?xml", 5) == 0 ||
		strncmp(current.map.ptr, "<svg", 4) == 0){
		return do_svg(C);
	}

/* other considerations here later is to enable HDR-aproto and if used on the
 * right source, deal with all that jaz - then we might also need/want to go
 * the handle-passing path immediately and try shmifext */
	int dw, dh;
	unsigned char* buf = stbi_load_from_memory(
			(unsigned char*) current.map.ptr,
			current.map.sz, &dw, &dh, NULL, sizeof(shmif_pixel));

	if (!buf)
		return false;

	find_safe_fit(C, dw, dh);

/* if the sizes doesn't match, scale into a buffer and then repack,
 * the repack bit is needed as shmif and stbi has a different idea
 * of channel order and stbi doesn't expose controls */
	if (dw != C->w && dh != C->h){
		unsigned char* unpack = malloc(C->w * C->h * sizeof(shmif_pixel));
		if (!unpack)
			return false;

		stbir_resize_uint8(buf, dw, dh, 0,
			unpack, C->w, C->h, 0, sizeof(shmif_pixel));

		free(buf);
		buf = unpack;
		dw = C->w;
		dh = C->h;
	}

	unsigned char* cur = buf;
	for (size_t y = 0; y < dh; y++){
		shmif_pixel* out = &C->vidp[y * C->pitch];
		for (size_t x = 0; x < dw; x++){
			uint8_t r = *cur++;
			uint8_t g = *cur++;
			uint8_t b = *cur++;
			uint8_t a = *cur++;
			out[x] = SHMIF_RGBA(r, g, b, a);
		}
	}

	free(buf);
	arcan_shmif_signal(C, SHMIF_SIGVID);
	return true;
}

static bool process_event(struct arcan_shmif_cont* C, arcan_tgtevent* ev)
{
	if (ev->kind == TARGET_COMMAND_EXIT)
		return false;

	if (ev->kind == TARGET_COMMAND_BCHUNK_IN){
		if (current.pending_raster){
			reraster(C);
		}
		do_file(C, arcan_shmif_dupfd(ev->ioevs[0].iv, -1, true));
		current.pending_raster = true;
		return true;
	}

	if (ev->kind == TARGET_COMMAND_SEEKCONTENT && current.svg){
		if (ev->ioevs[0].iv == 1){
			current.pan_xy[0] += ev->ioevs[1].iv;
			current.pan_xy[1] += ev->ioevs[2].iv;
			current.scale += ev->ioevs[3].fv;
		}
/* absolute */
		else if (ev->ioevs[0].iv == 0){
			current.pan_xy[0] = ev->ioevs[1].fv * current.svg->width;
			current.pan_xy[1] = ev->ioevs[2].fv * current.svg->height;
			if (ev->ioevs[3].fv > 0)
				current.scale = ev->ioevs[3].fv;
		}

		if (current.scale < 0.001)
			current.scale = 0.001;

		current.pending_raster = true;
	}

/* on a vector source we can reblit to fit the desired size and density */
	if (ev->kind == TARGET_COMMAND_DISPLAYHINT){
		if (ev->ioevs[0].iv && ev->ioevs[1].iv){
			arcan_shmif_resize(C, ev->ioevs[0].iv, ev->ioevs[1].iv);
			current.force_scale = true;
		}
		if (ev->ioevs[4].fv && ev->ioevs[4].fv != current.ppcm){
			current.ppcm = ev->ioevs[4].fv;
			do_svg(C); /* need to reparse with new density information */
		}
	}

	return true;
}

/*
 * currently quite naive,
 *
 * support a handful of formats in a 'service' mode where BCHUNK events
 * will resize the context (if needed) and blit/convert.
 *
 * this is based on a simplified aloadimage which is the testing/sandboxing
 * environment for more advanced features here.
 */
int decode_image(struct arcan_shmif_cont* C, struct arg_arr* args)
{
	arcan_shmif_privsep(C, "stdio", NULL, 0);
	struct arcan_shmif_initial* init = NULL;
	arcan_shmif_initial(C, &init);
	if (init){
		current.ppcm = init->density;
	}

	const char* val = NULL;
	int fd = -1;
	if (arg_lookup(args, "file", 0, &val)){
		if (!val || strlen(val) == 0){
			return show_use(C, "file=arg [arg] missing");
		}
		fd = open(val, O_RDONLY);
	}
	else
		fd = wait_for_file(C, "svg;jpg;png", NULL);

	if (-1 == fd)
		return EXIT_SUCCESS;

	do_file(C, fd);
	reraster(C);

	arcan_event ev;

/* this does not merge displayhint / seekcontent calls, that might be a useful
 * optimzation in cases where it is desired to both pan, scale and change dpi */
	while (arcan_shmif_wait(C, &ev) > 0){
		if (ev.category != EVENT_TARGET)
			continue;

		if (ev.tgt.kind == TARGET_COMMAND_EXIT)
			break;

		do {
			if (!process_event(C, &ev.tgt))
				goto out;
		}
		while (arcan_shmif_poll(C, &ev) > 0);
		reraster(C);
	}

out:
	return EXIT_SUCCESS;
}
