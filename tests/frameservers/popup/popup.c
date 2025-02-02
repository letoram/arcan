#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <unistd.h>
#include <stdbool.h>

#include <arcan_shmif.h>

static bool run_frame(struct arcan_shmif_cont* c, uint8_t rgb[3])
{
	rgb[0]++;
	rgb[1] += rgb[0] == 255;
	rgb[2] += rgb[1] == 255;

	for (size_t row = 0; row < c->h; row++)
		for (size_t col = 0; col < c->w; col++){
		c->vidp[ row * c->pitch + col ] = SHMIF_RGBA(rgb[0], rgb[1], rgb[2], 0xff);
	}

	arcan_shmif_signal(c, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
	return true;
}

static void flush_popup(struct arcan_shmif_cont* C)
{
	if (!C->addr)
		return;

/* missing, chain another popup if we click inside the segment */
	struct arcan_event ev;
	int sv;
	while ((sv = arcan_shmif_poll(C, &ev)) > 0){
	}
	if (-1 == sv)
		arcan_shmif_drop(C);
}

#ifdef ENABLE_FSRV_AVFEED
void arcan_frameserver_avfeed_run(const char* resource, const char* keyfile)
#else
int main(int argc, char** argv)
#endif
{
	struct arcan_shmif_cont cont = arcan_shmif_open(
		SEGID_APPLICATION, SHMIF_ACQUIRE_FATALFAIL, NULL);
	cont.hints = SHMIF_RHINT_VSIGNAL_EV;
	arcan_shmif_resize(&cont, 640, 480);

	uint8_t rgb[3] = {64, 64, 64};
	int mx = 0, my = 0;

	struct arcan_shmif_cont popup = {0};
	bool req_pending = false;

	run_frame(&cont, rgb);
	arcan_event ev;

	arcan_shmif_mousestate_setup(&cont, ARCAN_MOUSESTATE_ABSOLUTE, NULL);

	while(arcan_shmif_wait(&cont, &ev) > 0){
		flush_popup(&popup);

		if (ev.category == EVENT_IO){
			if (arcan_shmif_mousestate(&cont, NULL, &ev, &mx, &my)){
			}
			else if (
				ev.io.datatype == EVENT_IDATATYPE_DIGITAL &&
				ev.io.input.digital.active){
				if (!popup.addr && !req_pending){
					req_pending = true;
					arcan_shmif_enqueue(&cont, &(struct arcan_event){
						.category = EVENT_EXTERNAL,
						.ext.kind = ARCAN_EVENT(SEGREQ),
						.ext.segreq = {
							.width = 128,
							.height = 64,
							.xofs = mx,
							.yofs = my,
							.kind = SEGID_POPUP
						}
					});
				}
				else {
					arcan_shmif_enqueue(&popup, &(struct arcan_event){
						.category = EVENT_EXTERNAL,
						.ext.kind = ARCAN_EVENT(VIEWPORT),
						.ext.viewport = {
							.x = mx,
							.y = my,
							.parent = cont.segment_token
						}
					});
				}
			}
			continue;
		}

		if (ev.category != EVENT_TARGET)
			continue;

		switch (ev.tgt.kind){
			case TARGET_COMMAND_EXIT:
				goto out;
			break;
			case TARGET_COMMAND_REQFAIL:
				printf("rejected popup\n");
				req_pending = false;
			break;
			case TARGET_COMMAND_NEWSEGMENT:{
				req_pending = false;
				uint8_t rgb[3] = {127, 127, 127};
				popup = arcan_shmif_acquire(&cont, NULL, SEGID_POPUP, 0);
				run_frame(&popup, rgb);
			}
			break;
			case TARGET_COMMAND_STEPFRAME:
				run_frame(&cont, rgb);
			break;
		default:
		break;
		}
	}
out:
	return EXIT_SUCCESS;
}
