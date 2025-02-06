#include <arcan_shmif.h>
#include <pthread.h>
#include "platform/shmif_platform.h"
#include "shmif_privint.h"

bool arcan_shmif_multipart_message(
	struct arcan_shmif_cont* C, struct arcan_event* ev,
	char** out, bool* bad)
{
	if (!C || !ev || !out || !bad ||
		ev->category != EVENT_TARGET || ev->tgt.kind != TARGET_COMMAND_MESSAGE){
		*bad = true;
		return false;
	}

	struct shmif_hidden* P = C->priv;
	size_t msglen = strlen(ev->tgt.message);

	if (P->flush_multipart){
		P->flush_multipart = false;
		P->multipart_ofs = 0;
	}

	bool end_multipart = ev->tgt.ioevs[0].iv == 0;

	if (end_multipart)
		P->flush_multipart = true;

	if (msglen + P->multipart_ofs >= sizeof(P->multipart)){
		*bad = true;
		return false;
	}

	debug_print(DETAILED, C,
		"multipart:buffer:pre=%s:msg=%s", P->multipart, ev->tgt.message);
	memcpy(&P->multipart[P->multipart_ofs], ev->tgt.message, msglen);
	P->multipart_ofs += msglen;
	P->multipart[P->multipart_ofs] = '\0';
	debug_print(DETAILED, C,
		"multipart:buffer:post=%s", P->multipart);
	*out = P->multipart;
	*bad = false;

	return end_multipart;
}

#include "../frameserver/util/utf8.c"
bool arcan_shmif_pushutf8(
	struct arcan_shmif_cont* acon, struct arcan_event* base,
	const char* msg, size_t len)
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

bool arcan_shmif_descrevent(struct arcan_event* ev)
{
	if (!ev)
		return false;

	if (ev->category != EVENT_TARGET)
		return false;

	unsigned list[] = {
		TARGET_COMMAND_STORE,
		TARGET_COMMAND_RESTORE,
		TARGET_COMMAND_DEVICE_NODE,
		TARGET_COMMAND_FONTHINT,
		TARGET_COMMAND_BCHUNK_IN,
		TARGET_COMMAND_BCHUNK_OUT,
		TARGET_COMMAND_NEWSEGMENT
	};

	for (size_t i = 0; i < COUNT_OF(list); i++){
		if (ev->tgt.kind == list[i] &&
			ev->tgt.ioevs[0].iv != BADFD)
				return true;
	}

	return false;
}

bool arcan_shmif_acquireloop(struct arcan_shmif_cont* c,
	struct arcan_event* acqev, struct arcan_event** evpool, ssize_t* evpool_sz)
{
	if (!c || !acqev || !evpool || !evpool_sz)
		return false;

/* preallocate a buffer "large enough", some unreasonable threshold */
	size_t ul = 512;
	*evpool = malloc(sizeof(struct arcan_event) * ul);
	if (!*evpool)
		return false;

	*evpool_sz = 0;
	while (arcan_shmif_wait(c, acqev) && ul--){
/* event to buffer? */
		if (acqev->category != EVENT_TARGET ||
			(acqev->tgt.kind != TARGET_COMMAND_NEWSEGMENT &&
			acqev->tgt.kind != TARGET_COMMAND_REQFAIL)){
/* dup- copy the descriptor so it doesn't get freed in shmif_wait */
			if (arcan_shmif_descrevent(acqev)){
				acqev->tgt.ioevs[0].iv =
					arcan_shmif_dupfd(acqev->tgt.ioevs[0].iv, -1, true);
			}
			(*evpool)[(*evpool_sz)++] = *acqev;
		}
		else
			return true;
	}

/* broken pool */
	debug_print(FATAL, c, "eventpool is broken: %zu / %zu", *evpool_sz, ul);
	*evpool_sz = -1;
	free(*evpool);
	*evpool = NULL;
	return false;
}
