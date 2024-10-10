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
		shmif_pixel* px = &(cont->vidp[cont->w * y]);
		unsigned char* buf_row = &buf[y * cont->w * 3];

		for (size_t x = 0; x < cont->w; x++){
			unsigned char alpha;
			SHMIF_RGBA_DECOMP(*px, &buf_row[0], &buf_row[1], &buf_row[2], &alpha);
			px++;
			buf_row += 3;
		}
	}

/* there must be an API that doesn't force another copy */
	TessBaseAPISetImage(handle, buf, cont->w, cont->h, 3, cont->w * 3);
	free(buf);
}

static bool isdir(const char* fn)
{
	struct stat buf;
	bool rv = false;

	if (fn == NULL)
			return false;

	if (stat(fn, &buf) == 0)
		rv = S_ISDIR(buf.st_mode);

	return rv;
}

void ocr_serv_run(struct arg_arr* args, struct arcan_shmif_cont cont)
{
	TessBaseAPI* handle = TessBaseAPICreate();
	PIX* img;

	const char* lang;
	if (!arg_lookup(args, "lang", 0, &lang))
		lang = "eng";

	const char* datadir = NULL;
	if (isdir("/usr/local/share/tessdata"))
		datadir = "/usr/share/tessdata";
	else if (isdir("/usr/share/tessdata"))
		datadir = "/usr/share/tessdata";
	else {
		arcan_shmif_last_words(&cont, "tesseract 'tessdata' not found");
		arcan_shmif_drop(&cont);
		return;
	}

	if (TessBaseAPIInit3(handle, datadir, lang)){
		arcan_shmif_last_words(&cont, "couldn't load init/language");
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
				LOG("frame\n");
				repack_run(&cont, handle);
				if (TessBaseAPIRecognize(handle, NULL)){
					LOG("recognize-fail\n");
					arcan_shmif_last_words(&cont, "ocr: recognize failed");
					arcan_shmif_drop(&cont);
					goto out;
				}
				char* text = TessBaseAPIGetUTF8Text(handle);
				size_t len;
				if (text && (len = strlen(text))){
					struct arcan_event ev = {
						.ext.kind = ARCAN_EVENT(MESSAGE)
					};
					arcan_shmif_pushutf8(&cont, &ev, text, len);
					LOG("recognize=%s\n", text);
					TessDeleteText(text);
				}

				LOG("request-next\n");
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
