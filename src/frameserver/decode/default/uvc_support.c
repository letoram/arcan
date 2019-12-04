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

static void frame_yuyv(uvc_frame_t* frame, struct arcan_shmif_cont* dst)
{
	uint8_t* buf = frame->data;

	for (size_t y = 0; y < frame->height; y++){
		shmif_pixel* vidp = &dst->vidp[y * dst->pitch];
		for (size_t x = 0; x < frame->width; x+=2){
			vidp[x+0] = ycbcr(buf[0], buf[1], buf[3]);
			vidp[x+1] = ycbcr(buf[2], buf[1], buf[3]);
			buf += 4;
		}
	}

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
	printf("got frame\n");

/* guarantee dimensions */
	if (cont->w != frame->width || cont->h != frame->height){
		if (!arcan_shmif_resize(cont, frame->width, frame->height))
			return;
	}

/* conversion / repack */
	switch(frame->frame_format){
	case UVC_FRAME_FORMAT_YUYV:
		frame_yuyv(frame, cont);
	break;
	case UVC_FRAME_FORMAT_UYVY:
		frame_uyvy(frame, cont);
	break;
	case UVC_FRAME_FORMAT_RGB:
		frame_rgb(frame, cont);
	break;
	default:
	break;
	}
}

bool uvc_support_activate(
	struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	int vendor_id = 0x00;
	int product_id = 0x00;
	size_t width = 640;
	size_t height = 480;
	size_t fps = 30;

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
		snprintf((char*) cont->addr->last_words,
			sizeof(cont->addr->last_words), "couldn't initialize UVC");
		return false;
	}

/* enumeration means that we won't really use the connection, but
 * at least output to stdout and, if present, send them as messages */
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

			arcan_shmif_enqueue(cont, &ev);
			printf("%s", ev.ext.message.data);
		}
		uvc_free_device_list(devices, 1);
/* return false as VLC might also be able to enumerate capture */
		return false;
	}

	const char* val;
	if (arg_lookup(args, "vid", 0, &val) && val){
		vendor_id = strtoul(val, NULL, 10);
	}

	if (arg_lookup(args, "pid", 0, &val) && val){
		product_id = strtoul(val, NULL, 10);
	}

	arg_lookup(args, "serial", 0, &serial);

	if (uvc_find_device(uvctx, &dev, vendor_id, product_id, serial) < 0){
		snprintf((char*) cont->addr->last_words,
			sizeof(cont->addr->last_words), "no matching device");
		return false;
	}

	if (uvc_open(dev, &devh) < 0){
		snprintf((char*)cont->addr->last_words,
			sizeof(cont->addr->last_words), "couldn't open device");
		return false;
	}

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
 * from the initial display-hint
 */
	if (uvc_get_stream_ctrl_format_size(
		devh, &ctrl, UVC_FRAME_FORMAT_YUYV, width, height, fps) < 0){
		fprintf(stderr, "kind=EINVAL:message=format request (%zu*%zu@%zu fps) failed\n");
		return false;
	}

	uvc_start_streaming(devh, &ctrl, callback, cont, 0);

/* this one is a bit special, optimally we'd want to check cont and
 * see if we have GPU access - if there is one, we should try and get
 * the camera native format, upload that to a texture and repack /
 * convert there - for now just set RGBX and hope that uvc can unpack
 * without further conversion */
	arcan_shmif_privsep(cont, "minimal", NULL, 0);

	int rc = -1;
	while(rc >= 0){
		struct arcan_event ev;
		while(arcan_shmif_wait(cont, &ev)){
			if (ev.category != EVENT_TARGET)
				continue;
		}
	}

	arcan_shmif_drop(cont);
	uvc_close(devh);
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
	"width    \t px        \t preferred capture width (=640)\n"
	"height   \t px        \t preferred capture height (=480)\n"
	"fps      \t nframes   \t preferred catpure framerate (=30)\n"
	);
}
