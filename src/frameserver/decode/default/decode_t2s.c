#include <arcan_shmif.h>
#include <speak_lib.h>
#include <errno.h>

enum pack_format {
	PACK_MONO = 0,
	PACK_LEFT = 1,
	PACK_RIGHT = 2
};

static struct arcan_t2s {
	struct arcan_shmif_cont* cont;
	enum pack_format fmt;
} arcan_t2s;

static volatile bool in_playback = true;

static int on_sound(short* buf, int ns, espeak_EVENT* ev)
{
	if (ns < 0)
		return 1;

	struct arcan_t2s* t2s = &arcan_t2s;

/* flush any pending frames */
	if (ns == 0){
		if (t2s->cont->abufpos)
			arcan_shmif_signal(t2s->cont, SHMIF_SIGAUD);

		in_playback = false;
		return 0;
	}

	for (size_t i = 0; i < ns; i++){
/* first flush if we are full */
		if (t2s->cont->abufpos >= t2s->cont->abufcount){
			arcan_shmif_signal(t2s->cont, SHMIF_SIGAUD);
		}
		switch (t2s->fmt){
		case PACK_MONO:
			t2s->cont->audp[t2s->cont->abufpos++] = SHMIF_AINT16(buf[i]);
			t2s->cont->audp[t2s->cont->abufpos++] = SHMIF_AINT16(buf[i]);
		break;
		case PACK_LEFT:
			t2s->cont->audp[t2s->cont->abufpos++] = SHMIF_AINT16(buf[i]);
			t2s->cont->audp[t2s->cont->abufpos++] = SHMIF_AINT16(0);
		break;
		case PACK_RIGHT:
			t2s->cont->audp[t2s->cont->abufpos++] = SHMIF_AINT16(0);
			t2s->cont->audp[t2s->cont->abufpos++] = SHMIF_AINT16(buf[i]);
		break;
		}
		in_playback = true;
	}

	return 0;
}

int decode_t2s(struct arcan_shmif_cont* cont, struct arg_arr* args)
{
/* want a query / probe mode to get capabilities */

/* interesting controls:
 * language
 * mono / stereo behavior (multiplex or just queue)
 */
	int srate = espeak_Initialize(
		AUDIO_OUTPUT_RETRIEVAL, 0, NULL, 1 << 15);

	if (-1 == srate){
		arcan_shmif_last_words(cont, "espeak failed, no espeak-data");
		arcan_shmif_drop(cont);
		return EXIT_FAILURE;
	}

/* switch buffer sizes and sample rate to mach what espeak wants */
	if (!arcan_shmif_resize_ext(cont, cont->w, cont->h,
		(struct shmif_resize_ext){
			.samplerate = srate,
			.abuf_cnt = 12,
			.abuf_sz = 2048})){
		arcan_shmif_last_words(cont, "last words rejected");
		arcan_shmif_drop(cont);
		return EXIT_FAILURE;
	}

	if (arg_lookup(args, "list", 0, NULL)){
		const espeak_VOICE** base = espeak_ListVoices(NULL);
		while(base && *base){
			struct arcan_event msg = {
				.category = EVENT_EXTERNAL,
				.ext.kind = ARCAN_EVENT(MESSAGE)
			};
/* if we want to pick based on language we should use the segment initial
 * locale data, and provide an extended form */
			snprintf((char*)msg.ext.message.data,
				COUNT_OF(msg.ext.message.data) , "name=%s", (*base)->name);
			base++;
			arcan_shmif_enqueue(cont, &msg);
		}

/* some blocking / synch action to make sure the _drop doesn't get precedence
 * over event propagation to the server side */
		arcan_shmif_signal(cont, SHMIF_SIGVID);
		arcan_shmif_drop(cont);
		return EXIT_SUCCESS;
	}

	espeak_SetSynthCallback(on_sound);

/* espeak_SetVoiceByProperties
 * name, languages, gender, age, variant, index)
 */

	int fmt = PACK_MONO;
	const char* work;
	if (arg_lookup(args, "channel", 0, &work) && work){
		if (strcmp(work, "l") == 0)
			fmt = PACK_LEFT;
		else if (strcmp(work, "r") == 0)
			fmt = PACK_RIGHT;
	}

	arcan_t2s.cont = cont;
	arcan_t2s.fmt = fmt;

	if (arg_lookup(args, "pitch", 0, &work) && work){
		errno = 0;
		unsigned long val = strtoul(work, NULL, 10);
		if (errno == 0 && val <= 100){
			espeak_SetParameter(espeakPITCH, val, 0);
		}
	}

	if (arg_lookup(args, "range", 0, &work) && work){
		errno = 0;
		unsigned long val = strtoul(work, NULL, 10);
		if (errno == 0 && val <= 100){
			espeak_SetParameter(espeakRANGE, val, 0);
		}
	}

	if (arg_lookup(args, "gap", 0, &work) && work){
		errno = 0;
		unsigned long val = strtoul(work, NULL, 10);
		if (errno == 0 && val <= 100){
			espeak_SetParameter(espeakWORDGAP, val, 0);
		}
	}

	if (arg_lookup(args, "rate", 0, &work) && work){
		errno = 0;
		unsigned long val = strtoul(work, NULL, 10);
		if (errno == 0 && val >= 80 && val <= 450){
			espeak_SetParameter(espeakRATE, val, 0);
		}
	}

	int useSSML = 0;
	if (arg_lookup(args, "ssml", 0, NULL)){
		useSSML = espeakSSML;
	}

	int usePHONEMES = 0;
	if (arg_lookup(args, "phonemes", 0, NULL)){
		usePHONEMES = espeakPHONEMES;
	}

	arcan_event ev;

/* now we know everything in order to drop privileges - "little" detail here is
 * that espeak threads internally, and if this gets emulated through seccomp,
 * there might be a wake to break things there */


	const char* msg;
	if (arg_lookup(args, "text", 0, &msg)){
		if (!msg){
			arcan_shmif_last_words(cont, "empty 'text' argument");
			arcan_shmif_drop(cont);
			return EXIT_FAILURE;
		}

		if (EE_OK != espeak_Synth(msg, strlen(msg)+1, 0, POS_WORD, 0,
			espeakCHARS_UTF8 | useSSML | usePHONEMES, NULL, NULL)){
			arcan_shmif_last_words(cont, "synth call failed");
			arcan_shmif_drop(cont);
			return EXIT_FAILURE;
		}

/* rather crude but not quite worth the cost of doing it pretty */
		while(in_playback){
			sleep(1);
		}
		return EXIT_SUCCESS;
	}

	while (arcan_shmif_wait(cont, &ev)){

/* mainly here as a debugging facility as it is only the individual utf8-
 * characters that gets spoken, so anything higher level is better sent as
 * simple messages */
		if (ev.category == EVENT_IO){
			if (ev.io.datatype == EVENT_IDATATYPE_TRANSLATED){
				if (!ev.io.input.translated.active)
					continue;
				espeak_Key((char*)ev.io.input.translated.utf8);
			}
		}
		else if (ev.category == EVENT_TARGET){
			switch (ev.tgt.kind){
/* the UTF-8 validation should be stronger here, which can just be lifted
 * from the way it is done in arcan_tui */
			case TARGET_COMMAND_MESSAGE:{
				char buf[sizeof(ev.tgt.message)+1];
				size_t len = strlen(ev.tgt.message);
				buf[len] = 0;
				memcpy(buf, ev.tgt.message, len);
				if (EE_OK != espeak_Synth(buf, len+1, 0, POS_WORD, 0,
					espeakCHARS_UTF8 | useSSML | usePHONEMES, NULL, NULL)){
/* log, couldn't buffer */
				}
			}
			case TARGET_COMMAND_RESET:{
				arcan_shmif_enqueue(cont,
					&(arcan_event){
					.category = EVENT_EXTERNAL,
					.ext.kind = ARCAN_EVENT(FLUSHAUD)}
				);
				espeak_Cancel();
			}
			break;
			default:
			break;
			}
		}
		else
			;
	}
	return EXIT_SUCCESS;
}
