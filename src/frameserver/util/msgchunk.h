#include "utf8.c"

/* originally lifted from the clipboard code in tui, take a shmif
 * context and a message then split message over as many events as
 * needed, respecting utf8 alignment */
static void shmif_msgchunk(
	struct arcan_shmif_cont* c, const char* msg, size_t len)
{
	if (!c || !msg || !len)
		return;

	arcan_event msgev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	uint32_t state = 0, codepoint = 0;
	const char* outs = msg;
	size_t maxlen = sizeof(msgev.ext.message.data) - 1;

/* utf8- point aligned against block size */
	while (len > maxlen){
		size_t i, lastok = 0;
		state = 0;
		for (i = 0; i <= maxlen - 1; i++){
			if (UTF8_ACCEPT == utf8_decode(&state, &codepoint, (uint8_t)(msg[i])))
				lastok = i;

			if (i != lastok){
				if (0 == i)
					return;
			}
		}

		memcpy(msgev.ext.message.data, outs, lastok);
		msgev.ext.message.data[lastok] = '\0';
		len -= lastok;
		outs += lastok;

		if (len)
			msgev.ext.message.multipart = 1;
		else
			msgev.ext.message.multipart = 0;

		arcan_shmif_enqueue(c, &msgev);
	}

/* flush remaining */
	if (len){
		snprintf((char*)msgev.ext.message.data, maxlen, "%s", outs);
		msgev.ext.message.multipart = 0;
		arcan_shmif_enqueue(c, &msgev);
	}
}
