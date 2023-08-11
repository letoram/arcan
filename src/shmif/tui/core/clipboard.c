#include <stdlib.h>
#include <stdio.h>
#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../../../frameserver/util/utf8.c"
#include "../tui_int.h"

#define UTF8_ACCEPT 0
#define UTF8_REJECT 1

void tui_clipboard_check(struct tui_context* tui)
{
	arcan_event ev;
	int pv = 0;

	while ((pv = arcan_shmif_poll(&tui->clip_in, &ev)) > 0){
		if (ev.category != EVENT_TARGET)
			continue;

		arcan_tgtevent* tev = &ev.tgt;
		switch(tev->kind){
		case TARGET_COMMAND_MESSAGE:
			if (tui->handlers.utf8)
				tui->handlers.utf8(tui, (const uint8_t*) tev->message,
					strlen(tev->message), tev->ioevs[0].iv, tui->handlers.tag);
		break;
		case TARGET_COMMAND_EXIT:
			arcan_shmif_drop(&tui->clip_in);
			return;
		break;
		default:
		break;
		}
	}

	if (pv == -1)
		arcan_shmif_drop(&tui->clip_in);
}

bool tui_clipboard_push(struct tui_context* tui, const char* sel, size_t len)
{
/*
 * there are more advanced clipboard options to be used when
 * we have the option of exposing other devices using a fuse- vfs
 * in: /vdev/istream, /vdev/vin, /vdev/istate
 * out: /vdev/ostream, /dev/vout, /vdev/vstate, /vdev/dsp
 */
	if (!tui->clip_out.vidp || !sel || !len)
		return false;

	arcan_event msgev = {
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	return arcan_shmif_pushutf8(&tui->clip_out, &msgev, sel, len);
}
