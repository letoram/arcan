/*
 * Basic bringup for libuvc as part of the decode frameserver
 * Setup derived from the example in libuvc.
 *
 * For this to work properly (and that goes with USB LEDs etc.  as well), we
 * need to extend the device- negotiation path - until then, make sure the user
 * arcan is running as can get access to the device nodes themselves.
 *
 * The setup is also so we can get webcam decoding without a full libvlc build
 * on more custom setups - and as a place for hooking in other webcam support,
 * should it be needed.
 *
 * More interestingly is when we can negotiate other buffer formats for the
 * shmpage, particularly MJPEG and H264 for with the network- proxy.
 *
 * Controls to expose:
 *  - autoexposure,
 *  - autofocus
 *  - focus range
 *  - zoom
 *  - pan/tilt/roll
 *  - privacy(?)
 *  - button callback
 *
 * These should probably be provided as labelhints
 */
#include <arcan_shmif.h>
#include <libuvc/libuvc.h>
#include <libswscale/swscale.h>
#include <math.h>

static int video_buffer_count = 1;

/* should also have the option to convert to GPU texture here and pass
 * onwards rather than paying the conversion proce like this */
static uint8_t clamp_u8(int v, int low, int high)
{
	return
		v < low ? low : (v > high ? high : v);
}

static shmif_pixel ycbcr(int y, int cb, int cr)
{
	double r = y + (1.4065 * (cr - 128));
	double g = y - (0.3455 * (cb - 128)) - (0.7169 * (cr - 128));
	double b = y + (1.7790 * (cb - 128));
	return
		SHMIF_RGBA(
			clamp_u8(r, 0, 255),
			clamp_u8(g, 0, 255),
			clamp_u8(b, 0, 255),
			0xff
		);
}
static void frame_uyvy(uvc_frame_t* frame, struct arcan_shmif_cont* dst)
{
	uint8_t* buf = frame->data;

	for (size_t y = 0; y < frame->height; y++){
		shmif_pixel* vidp = &dst->vidp[y * dst->pitch];
		for (size_t x = 0; x < frame->width; x+=2){
			vidp[x+0] = ycbcr(buf[1], buf[0], buf[2]);
			vidp[x+1] = ycbcr(buf[3], buf[0], buf[2]);
			buf += 4;
		}
	}

	arcan_shmif_signal(dst, SHMIF_SIGVID);
}

static void run_swscale(
	uvc_frame_t* frame, struct arcan_shmif_cont* dst, int planes, int fmt)
{
	static struct SwsContext* scaler;
	static int old_fmt = -1;

	if (fmt != old_fmt && scaler){
		sws_freeContext(scaler);
		scaler = NULL;
	}

	if (!scaler){
		scaler = sws_getContext(
			frame->width, frame->height, fmt,
			dst->w, dst->h, AV_PIX_FMT_BGRA, SWS_BILINEAR, NULL, NULL, NULL);
	}

	if (!scaler)
		return;

	int dst_stride[] = {dst->stride};
	uint8_t* const dst_buf[] = {dst->vidb};
	const uint8_t* data[3] = {frame->data, NULL, NULL};
	int lines[3] = {frame->width, 0, 0};
	size_t bsz = frame->width * frame->height;

	if (planes > 1){
		size_t hw = (frame->width + 1) >> 1;
		size_t hh = (frame->height + 1) >> 1;

		data[1] = frame->data + bsz;
		lines[1] = frame->width;

		if (planes > 2){
			lines[1] = hw;
			data[2] = frame->data + bsz + hw;
			lines[2] = hw;
		}
	}

	sws_scale(scaler, data, lines, 0, frame->height, dst_buf, dst_stride);
	arcan_shmif_signal(dst, SHMIF_SIGVID);
}

static void frame_rgb(uvc_frame_t* frame, struct arcan_shmif_cont* dst)
{
	uint8_t* buf = frame->data;
	for (size_t y = 0; y < frame->height; y++){
		shmif_pixel* vidp = &dst->vidp[y * dst->pitch];
		for (size_t x = 0; x < frame->width; x++){
			vidp[x] = SHMIF_RGBA(buf[0], buf[1], buf[2], 0xff);
			buf += 3;
		}
	}
	arcan_shmif_signal(dst, SHMIF_SIGVID);
}

static void callback(uvc_frame_t* frame, void* tag)
{
	uvc_frame_t* bgr;
	uvc_error_t ret;
	struct arcan_shmif_cont* cont = tag;

/* guarantee dimensions */
	if (cont->w != frame->width || cont->h != frame->height){
		if (!arcan_shmif_resize_ext(cont, frame->width, frame->height,
			(struct shmif_resize_ext){.vbuf_cnt = video_buffer_count})){
			return;
		}
	}

/* conversion / repack */
	switch(frame->frame_format){
/* 'actually YUY2 is also called YUYV which is YUV420' (what a mess)
 * though at least the capture devices I have used this one had the
 * YUYV frame format have the same output as NV12 /facepalm */
	case UVC_FRAME_FORMAT_YUYV:
	case UVC_FRAME_FORMAT_NV12:
		run_swscale(frame, cont, 2, AV_PIX_FMT_NV12);
	break;
	case UVC_FRAME_FORMAT_UYVY:
		run_swscale(frame, cont, 3, AV_PIX_FMT_UYVY422);
		frame_uyvy(frame, cont);
	break;
	case UVC_FRAME_FORMAT_RGB:
		frame_rgb(frame, cont);
	break;
/* h264 and mjpeg should map into ffmpeg as well */
	default:
		LOG("unhandled frame format: %d\n", (int)frame->frame_format);
	break;
	}
}

static int fmt_score(const uint8_t fourcc[static 4], int* out)
{
	static struct {
		uint8_t fourcc[4];
		int enumv;
		int score;
	}
	fmts[] = {
		{
			.fourcc = {'Y', 'U', 'Y', '2'},
			.enumv = UVC_FRAME_FORMAT_YUYV,
			.score = 2
		},
		{
			.fourcc = {'U', 'Y', 'V', 'Y'},
			.enumv = UVC_FRAME_FORMAT_UYVY,
			.score = 2
		},
		{
			.fourcc = {'Y', '8', '0', '0'},
			.enumv = UVC_FRAME_FORMAT_GRAY8,
			.score = 1
		},
		{
      .fourcc = {'N',  'V',  '1',  '2'},
			.enumv = UVC_FRAME_FORMAT_NV12,
			.score = 3
		},
/* this does not seem to have the 'right' fourcc? */
		{
			.fourcc = {0x7d, 0xeb, 0x36, 0xe4},
			.enumv = UVC_FRAME_FORMAT_BGR,
			.score = 3
		},
		{
			.enumv = UVC_FRAME_FORMAT_MJPEG,
			.score = -1,
			.fourcc = {'M', 'J', 'P', 'G'}
		},
		{
			.enumv = UVC_FRAME_FORMAT_MJPEG,
			.score = -1,
			.fourcc = {'H', '2', '6', '4'}
		},
	};

	for (size_t i = 0; i < sizeof(fmts) / sizeof(fmts[0]); i++){
		if (memcmp(fmts[i].fourcc, fourcc, 4) == 0){
			*out = fmts[i].enumv;
			return fmts[i].score;
		}
	}

	return -1;
}

/*
 * preference order:
 *  fmt > dimensions
 */
static bool match_dev_pref_fmt(
	uvc_device_handle_t* devh, size_t* w, size_t* h, int* fmt_out)
{
	const uvc_format_desc_t* fmt = uvc_get_format_descs(devh);
	int fmtid = -1;
	int best_score = -1;
	int fw = 0;
	int fh = 0;
	float id = 0;
	float best_dist = id;

	if (*w || *h)
		id = sqrtf(*w * *w + *h * *h);

/* ok the way formats are defined here is a special kind of ?!, there is an
 * internal format description that you are supposed to use within API borders,
 * then it is compared to the regular fourcc and GUIDs - but note that the
 * fourcc is ALSO a GUID */
	while (fmt){
		int fmtscore;
		int score = fmt_score(fmt->fourccFormat, &fmtscore);

		if (score != -1 && (best_score == -1 || best_score < score)){
			const uvc_frame_desc_t* ftype = fmt->frame_descs;
			if (!ftype){
				fmt = fmt->next;
				continue;
			}

/* new format, pick the first dimension, and if the caller set a preference,
 * find the distance that best fits our wants */
			best_score = score;
			fw = ftype->wWidth;
			fh = ftype->wHeight;
			*fmt_out = fmtscore;

			best_dist = sqrtf(fw * fw + fh * fh);
			if (!*w || !*h){
				fmt = fmt->next;
				continue;
			}

			while (ftype){
				float dist = sqrtf(
					ftype->wWidth * ftype->wWidth + ftype->wHeight * ftype->wHeight);
				if (dist < best_dist){
					best_dist = dist;
					fw = ftype->wWidth;
					fh = ftype->wHeight;
				}
				ftype = ftype->next;
			}
		}

		fmt = fmt->next;
	}

	if (best_score != -1){
		*w = fw;
		*h = fh;
		return true;
	}
	else
		return false;
}

#define DIE(C) do { arcan_shmif_drop(C); return true; } while(0)

bool uvc_support_activate(
	struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	int vendor_id = 0x00;
	int product_id = 0x00;
	size_t width = 0;
	size_t height = 0;
	int fps = 0;

/* we only return 'false' if uvc has explicitly been disabled, otherwise
 * VLC might try to capture */
	const char* serial = NULL;
	if (arg_lookup(args, "no_uvc", 0, NULL))
		return false;

/* capture is already set, otherwise we wouldn't be here */
	uvc_context_t* uvctx;
	uvc_device_t* dev;
	uvc_device_handle_t* devh;
	uvc_stream_ctrl_t ctrl;
	uvc_error_t res;

	if (uvc_init(&uvctx, NULL) < 0){
		arcan_shmif_last_words(cont, "couldn't initialize UVC");
		DIE(cont);
	}

/* enumeration means that we won't really use the connection, but
 * at least send as messages */
	if (arg_lookup(args, "list", 0, NULL)){
		uvc_device_t** devices;
		uvc_get_device_list(uvctx, &devices);
		for(size_t i = 0; devices[i]; i++){
			uvc_device_descriptor_t* ddesc;
			if (uvc_get_device_descriptor(devices[i], &ddesc) != UVC_SUCCESS)
				continue;

			struct arcan_event ev = {
				.category = EVENT_EXTERNAL,
				.ext.kind = ARCAN_EVENT(MESSAGE)
			};

			size_t nb = sizeof(ev.ext.message.data) / sizeof(ev.ext.message.data[0]);
			if (!ddesc->serialNumber){
				snprintf((char*) ev.ext.message.data, nb, "vid=%.4x:pid=%.4x:"
					"status=EPERM, permission denied\n", ddesc->idVendor, ddesc->idProduct);
			}
			else{
				snprintf((char*) ev.ext.message.data, nb, "vid=%.4x:pid=%.4x:serial=%s:product=%s\n",
					ddesc->idVendor, ddesc->idProduct, ddesc->serialNumber, ddesc->product);
			}

			fputs((char*)ev.ext.message.data, stdout);
			arcan_shmif_enqueue(cont, &ev);
		}
		uvc_free_device_list(devices, 1);
		DIE(cont);
	}

	const char* val;
	if (arg_lookup(args, "vid", 0, &val) && val)
		vendor_id = strtoul(val, NULL, 16);

	if (arg_lookup(args, "width", 0, &val) && val)
		width = strtoul(val, NULL, 10);

	if (arg_lookup(args, "height", 0, &val) && val)
		height = strtoul(val, NULL, 10);

	if (arg_lookup(args, "pid", 0, &val) && val)
		product_id = strtoul(val, NULL, 16);

	if (arg_lookup(args, "fps", 0, &val) && val)
		fps = strtoul(val, NULL, 10);

	if (arg_lookup(args, "vbufc", 0, &val)){
		uint8_t bufc = strtoul(val, NULL, 10);
		video_buffer_count = bufc > 0 && bufc <= 4 ? bufc : 1;
	}

	arg_lookup(args, "serial", 0, &serial);

	if (uvc_find_device(uvctx, &dev, vendor_id, product_id, serial) < 0){
		arcan_shmif_last_words(cont, "no matching device");
		DIE(cont);
	}

	if (uvc_open(dev, &devh) < 0){
		arcan_shmif_last_words(cont, "couldn't open device");
		DIE(cont);
	}

/* finding the right format is complicated -
 *  the formats for a device is a linked list (->next) where there is a
 *  frame_desc with the same restriction.
 *
 * scan for matching size (if defined) - otherwise pick based on format
 * and format priority. This is what uvc_get_stream_ctrl_format_size does
 * but it also requires explicit size description
 */
	int fmt = -1;

	if (!match_dev_pref_fmt(devh, &width, &height, &fmt)){
		arcan_shmif_last_words(cont, "no compatible frame-format for device");
		DIE(cont);
	}

	enum uvc_frame_format frame_format;

/* will be redirected to log */
	uvc_print_diag(devh, stderr);

/* so there are more options to negotiate here, and we can't really grok
 * what is the 'preferred' format, normal tactic is
 *
 * uvc_stream_ctrl_t ctrl;
 * uvc_get_stream_ctrl_format_size(
 * 	devh, &ctrl, UVC_FRAME_FORMAT_YUYV, w, h, fps)
 *
 * so maybe we need to try a few and then pick what best match some user pref.
 */

/* some other frame formats take even more special consideration, mainly
 * FRAME_FORMAT_H264 (decode through vlc or openh264) | (attempt-passthrough)
 * FRAME_FORMAT_MJPEG
 */
	if (uvc_get_stream_ctrl_format_size(
		devh, &ctrl, fmt, width, height, fps) < 0){
		fprintf(stderr, "kind=EINVAL:message="
			"format request (%zu*%zu@%d fps)@%d failed\n", width, height, fps, fmt);

		if (uvc_get_stream_ctrl_format_size(
			devh, &ctrl, UVC_FRAME_FORMAT_ANY, width, height, fps) < 0){
			fprintf(stderr, "kind=EINVAL:message="
				"format request (%zu*%zu@%d fps)@ANY failed\n", width, height, fps);
		}
		goto out;
	}

	int rv = uvc_start_streaming(devh, &ctrl, callback, cont, 0);
	if (rv < 0){
		arcan_shmif_last_words(cont, "uvc- error when streaming");
		goto out;
	}

/* this one is a bit special, optimally we'd want to check cont and
 * see if we have GPU access - if there is one, we should try and get
 * the camera native format, upload that to a texture and repack /
 * convert there - for now just set RGBX and hope that uvc can unpack
 * without further conversion */
	arcan_shmif_privsep(cont, "minimal", NULL, 0);

	struct arcan_event ev;
	while(arcan_shmif_wait(cont, &ev)){
		if (ev.category != EVENT_TARGET)
			continue;
	}

out:
	uvc_close(devh);
	arcan_shmif_drop(cont);
	return true;
}

void uvc_append_help(FILE* out)
{
	fprintf(out, "\nUVC- based webcam arguments:\n"
	"   key   \t   value   \t  description\n"
	"---------\t-----------\t----------------\n"
	"no_uvc   \t           \t skip uvc in capture device processing chain\n"
	"list     \t           \t enumerate valid devices then return\n"
	"capture  \t           \t try and find a capture device\n"
	"vid      \t 0xUSBVID  \t specify (hex) the vendor ID of the device\n"
	"pid      \t 0xUSBPID  \t specify (hex) the product ID of the device\n"
	"serial   \t <string>  \t specify the serial number of the device\n"
	"width    \t px        \t preferred capture width (=0)\n"
	"height   \t px        \t preferred capture height (=0)\n"
	"fps      \t nframes   \t preferred capture framerate (=0)\n"
	"vbufc    \t nbuf      \t preferred number of transfer buffers (=1)\n"
	);
}
