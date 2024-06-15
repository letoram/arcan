#include <tesseract/capi.h>
#include <leptonica/allheaders.h>
#include <arcan_shmif.h>
#include "util/utf8.c"

static void repack_run(struct arcan_shmif_cont* cont, TessBaseAPI* handle)
{
	size_t buf_sz = cont->w * cont->h * 3;
	unsigned char* buf = malloc(buf_sz);
	if (!buf)
		return;

	for (size_t y = 0; y < cont->h; y++){
		shmif_pixel* px = &(cont->vidp[cont->h * y]);
		unsigned char* buf_row = &buf[y * cont->w * 3];

		for (size_t x = 0; x < cont->w; x++){
			unsigned char alpha;
			SHMIF_RGBA_DECOMP(*px, &buf_row[0], &buf_row[1], &buf_row[2], &alpha);
			px++;
			buf_row += 3;
		}
	}

	TessBaseAPISetImage(handle, buf, cont->w, cont->h, 3, cont->w * 3);
	free(buf);
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

	const char* dpival;
	arg_lookup(args, "dpi", 0, &dpival);
	if (dpival)
		TessBaseAPISetVariable(handle, "user_defined_dpi", dpival);

/*
 * There are many little details missing here, e.g.  control over segmentation
 * / grouping (receiving input) and somehow alerting when the OCR failed to
 * yield anything.
 *
 * There might be some API to avoid the explicit copy inside of
 * TessBaseAPISetImage as well, since that repacks / reallocs again.
 */
	arcan_event ev;
	while(arcan_shmif_wait(&cont, &ev)){
		if (ev.category == EVENT_TARGET){
			switch (ev.tgt.kind){
			case TARGET_COMMAND_STEPFRAME:{
				repack_run(&cont, handle);
				char* text = TessBaseAPIGetUTF8Text(handle);
				size_t len;
				if (text && (len = strlen(text))){
					struct arcan_event ev = {
						.ext.kind = ARCAN_EVENT(MESSAGE)
					};
					arcan_shmif_pushutf8(&cont, &ev, text, len);
					TessDeleteText(text);
				}

				arcan_shmif_signal(&cont, SHMIF_SIGVID);
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
