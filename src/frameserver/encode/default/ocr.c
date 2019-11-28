#include <tesseract/capi.h>
#include <leptonica/allheaders.h>
#include <arcan_shmif.h>
#include "util/utf8.c"

/*
 * Same code as in select- in terminal. Ought to be moved to a shared
 * shmif-support lib that also covers 3D setup and handle extraction.
 */
static void push_multipart(struct arcan_shmif_cont* out,
	char* msg, size_t len)
{
	arcan_event msgev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(MESSAGE)
	};

	uint32_t state = 0, codepoint = 0;
	char* outs = msg;
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

		arcan_shmif_enqueue(out, &msgev);
	}

/* flush remaining */
	if (len){
		snprintf((char*)msgev.ext.message.data, maxlen, "%s", outs);
		msgev.ext.message.multipart = 0;
		arcan_shmif_enqueue(out, &msgev);
	}
}

void ocr_serv_run(struct arg_arr* args, struct arcan_shmif_cont cont)
{
	TessBaseAPI* handle = TessBaseAPICreate();
	PIX* img;

	const char* lang = "eng";
	arg_lookup(args, "lang", 0, &lang);
	if (TessBaseAPIInit3(handle, NULL, lang)){
		LOG("encode-ocr: Couldn't initialize tesseract with lang (%s)\n", lang);
		return;
	}

/*
 * There are many little details missing here, e.g.  control over segmentation
 * / grouping (receiving input) and somehow alerting when the OCR failed to
 * yield anything.
 */
	arcan_event ev;
	while(arcan_shmif_wait(&cont, &ev)){
		if (ev.category == EVENT_TARGET){
			switch (ev.tgt.kind){
			case TARGET_COMMAND_STEPFRAME:{
				TessBaseAPISetImage(handle, (const unsigned char*) cont.vidp,
					cont.w, cont.h, sizeof(shmif_pixel), cont.stride);
				char* text = TessBaseAPIGetUTF8Text(handle);
				size_t len;
				if (!text || (len = strlen(text)) == 0)
					continue;

				push_multipart(&cont, text, len);
				TessDeleteText(text);
			}
			break;
			case TARGET_COMMAND_EXIT:
				goto out;
			default:
			break;
			}
		}
	}
out:
	TessBaseAPIEnd(handle);
	TessBaseAPIDelete(handle);
}
