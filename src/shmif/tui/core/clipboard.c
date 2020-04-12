#include <stdlib.h>
#include <stdio.h>
#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../tui_int.h"

#include "../screen/utf8.c"

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

bool tui_push_message(struct arcan_shmif_cont* acon,
	struct arcan_event* base, const char* msg, size_t len)
{
	uint32_t state = 0, codepoint = 0;
	const char* outs = msg;
	size_t maxlen = sizeof(base->ext.message.data) - 1;

/* utf8- point aligned against block size */
	while (len > maxlen){
		size_t i, lastok = 0;
		state = 0;
		for (i = 0; i <= maxlen - 1; i++){
			if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(msg[i])))
				lastok = i;

			if (i != lastok){
				if (0 == i)
					return false;
			}
		}

		memcpy(base->ext.message.data, outs, lastok);
		base->ext.message.data[lastok] = '\0';
		len -= lastok;
		outs += lastok;
		if (len)
			base->ext.message.multipart = 1;
		else
			base->ext.message.multipart = 0;

		arcan_shmif_enqueue(acon, base);
	}

/* flush remaining */
	if (len){
		snprintf((char*)base->ext.message.data, maxlen, "%s", outs);
		base->ext.message.multipart = 0;
		arcan_shmif_enqueue(acon, base);
	}

	return true;
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

	return tui_push_message(&tui->clip_out, &msgev, sel, len);
}
