/*
 * Basic bringup for libuvc as part of the decode frameserver
 *
 * For this to work properly (and that goes with USB LEDs etc.
 * as well), we need to extend the device- negotiation path -
 * until then, make sure the user arcan is running as can get
 * access to the device nodes themselves.a
 *
 * The setup is also so we can get webcam decoding without a
 * full libvlc build on more custom setups - and as a place
 * for hooking in other webcam support, should it be needed.
 */
#include <arcan_shmif.h>
#include <libuvc/libuvc.h>

bool uvc_support_activate(
	struct arcan_shmif_cont* cont, struct arg_arr* args)
{
	int vendor_id = 0x00;
	int product_id = 0x00;

/* capture is already set, otherwise we wouldn't be here */
	uvc_context_t* uvctx;
	uvc_device_t* dev;
	uvc_device_handle_t* devh;
	uvc_stream_ctrl_t ctrl;
	uvc_error_t res;

/* note: expand SHMIF with a interop function to set / append last words */
	if (uvc_init(&uvctx, NULL) < 0){
		snprintf(cont->addr->last_words,
			sizeof(cont->addr->last_words), "couldn't initialize UVC");
		return false;
	}

	if (uvc_find_device(uvctx, &dev, vendor_id, product_id, NULL) < 0){
		snprintf(cont->addr->last_words,
			sizeof(cont->addr->last_words), "no matching device");
		return false;
	}

	if (uvc_open(dev, &devh) < 0){
		snprintf(cont->addr->last_words,
			sizeof(cont->addr->last_words), "couldn't open device");
		return false;
	}

	uvc_print_diag(devh, stderr);

/* this one is a bit special, optimally we'd want to check cont and
 * see if we have GPU access - if there is one, we should try and get
 * the camera native format, upload that to a texture and repack /
 * convert there - for now just set RGBX and hope that uvc can unpack
 * without further conversion */
	int rc = -1;
	while(rc >= 0){
		struct arcan_event ev;
		while( (rc = arcan_shmif_poll(cont, &ev)) > 0){

		}
	}

	arcan_shmif_drop(cont);
	uvc_close(devh);
	return true;
}

void uvc_append_help(FILE* out)
{
	fprintf(out, "\nUVC- based webcam arguments:\n"
	"  key  \t  value   \t  description\n"
	"-------\t----------\t---------------\n"
	"capture\t          \t enable capture device support\n"
	"vid    \t 0xUSBVID \t specify (hex) the vendor ID of the device\n"
	"pid    \t 0xUSBPID \t specify (hex) the product ID of the device\n"
	"serial \t <string> \t specify the serial number of the device\n"
	);
}
