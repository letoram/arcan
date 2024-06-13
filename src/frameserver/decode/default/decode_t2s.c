#include <arcan_shmif.h>
#include <speak_lib.h>
#include <errno.h>
#include "arcan_tuisym.h"

enum pack_format {
	PACK_MONO = 0,
	PACK_LEFT = 1,
	PACK_RIGHT = 2
};

static struct t2s {
	struct arcan_shmif_cont* cont;
	enum pack_format fmt;
	int flags;
	char msgbuf[16384];
	size_t msgofs;
	int defaultRate;
	int curRate;
	bool cancel;
} t2s = {
	.flags = espeakCHARS_UTF8,
	.defaultRate = espeakRATE_NORMAL,
	.curRate = espeakRATE_NORMAL
};

static bool flush_event(arcan_event ev);
static volatile bool in_playback = true;

static void send_rate(bool inc)
{
	int rate = espeak_GetParameter(espeakRATE, 1);
	char buf[24];
	size_t nw = snprintf(buf, 24, "%srate: %d", inc? "inc" : "dec", rate);
	espeak_Synth(buf, nw, 0, POS_WORD, 0, t2s.flags | espeakENDPAUSE, NULL, NULL);
}

static void apply_label(const char* msg)
{
	if (strcmp(msg, "FAST") == 0){
		espeak_SetParameter(espeakRATE, 310, 0);
	}
	else if (strcmp(msg, "SLOW") == 0){
		espeak_SetParameter(espeakRATE, espeakRATE_MINIMUM, 0);
	}
	else if (strcmp(msg, "DEFAULT") == 0){
		espeak_SetParameter(espeakRATE, t2s.defaultRate, 0);
		t2s.curRate = t2s.defaultRate;
	}
	else if (strcmp(msg, "SETRATE") == 0){
		espeak_SetParameter(espeakRATE, t2s.curRate, 0);
	}
	else if (strcmp(msg, "INCRATE") == 0){
		t2s.curRate += 20;
		if (t2s.curRate > 450)
			t2s.curRate = 450;

		espeak_SetParameter(espeakRATE, t2s.curRate, 0);
		send_rate(true);
	}
	else if (strcmp(msg, "DECRATE") == 0){
		t2s.curRate -= 20;
		if (t2s.curRate < espeakRATE_MINIMUM)
			t2s.curRate = espeakRATE_MINIMUM;

		espeak_SetParameter(espeakRATE, t2s.curRate, 0);
		send_rate(false);
	}
	else if (strcmp(msg, "PITCHUP") == 0){
		espeak_SetParameter(espeakPITCH, 10, 1);
	}
	else if (strcmp(msg, "PITCHDOWN") == 0){
		espeak_SetParameter(espeakPITCH, -10, 1);
	}
	else if (strcmp(msg, "RAW") == 0){
		t2s.flags = espeakCHARS_UTF8;
	}
	else if (strcmp(msg, "SSML") == 0){
		t2s.flags = espeakCHARS_UTF8 | espeakSSML;
	}
	else if (strcmp(msg, "PHONEMES") == 0){
		t2s.flags = espeakCHARS_UTF8 | espeakPHONEMES;
	}
}

static void merge_message(struct arcan_tgtevent* ev)
{
	char* dst = (char*) ev->message;

/* buffer multipart up to some small-ish cap */
	if (t2s.msgofs || ev->ioevs[0].iv){
		size_t len = strlen(ev->message);
		if (len + t2s.msgofs >= sizeof(t2s.msgbuf) - 1){
			t2s.msgofs = 0;
			return;
		}

		memcpy(&t2s.msgbuf[t2s.msgofs], ev->message, len);
		t2s.msgofs += len;
		t2s.msgbuf[t2s.msgofs] = '\0';

		if (ev->ioevs[0].iv)
			return;

		dst = t2s.msgbuf;
	}

	size_t len = strlen(dst);
	dst[len] = '\0';
	t2s.msgofs = 0;

/* we have [incoming multipart buffer] ->
 *              espeak-internal-buffer ->
 *          shmif audio segment buffer ->
 *          server-side audio playback ->
 *              audio-library playback
 *
 * all with different reset mechanisms ..
 *
 * for now let 'espeak' act as governing buffer as the _RESET event
 * maps there, so if we overflow through message spam that's where
 * it will be caught.
 */

	if (EE_OK != espeak_Synth(dst,
		len+1, 0, POS_WORD, 0, t2s.flags | espeakENDPAUSE, NULL, NULL)){
	}
}

static int on_sound(short* buf, int ns, espeak_EVENT* ev)
{
	if (ns < 0)
		return 1;

/* With *ev being espeakEVENT_MSG_TERMINATED and espeakEVENT_END we can
 * distinguish between requests. Debugging can be helped somewhat here
 * using a TUI context on the output and rendering which message that
 * just completed to understand synch between buffers.
 *
 * The other potentiality is to set RHINT to EMPTY and use SIGVID to
 * let the server end control stepping between queued messages (at the
 * cost of eventually reaching backpressure caps).
 */

/* flush any pending frames */
	if (ns == 0){
		if (t2s.cont->abufpos)
			arcan_shmif_signal(t2s.cont, SHMIF_SIGAUD);

		in_playback = false;
		return 0;
	}

	struct arcan_shmif_cont* C = t2s.cont;

	for (size_t i = 0; i < ns; i++){
/* first flush if we are full, but process events as well as we might have
 * received a RESET that should take priority, uncertain what eSpeak thinks
 * of us calling synth while inside the callback, possible that we need to
 * queue MESSAGE events */
		if (C->abufpos >= C->abufcount){
			arcan_event ev;
			while (arcan_shmif_poll(t2s.cont, &ev) > 0){
				if (!flush_event(ev)){
					C->abufpos = 0;
					return 1;
				}
			}

			arcan_shmif_signal(C, SHMIF_SIGAUD);
		}

		switch (t2s.fmt){
		case PACK_MONO:
			C->audp[C->abufpos++] = SHMIF_AINT16(buf[i]);
			C->audp[C->abufpos++] = SHMIF_AINT16(buf[i]);
		break;
		case PACK_LEFT:
			C->audp[C->abufpos++] = SHMIF_AINT16(buf[i]);
			C->audp[C->abufpos++] = SHMIF_AINT16(0);
		break;
		case PACK_RIGHT:
			C->audp[C->abufpos++] = SHMIF_AINT16(0);
			C->audp[C->abufpos++] = SHMIF_AINT16(buf[i]);
		break;
		}
		in_playback = true;
	}

	if (C->abufpos)
		arcan_shmif_signal(C, SHMIF_SIGAUD);

	return 0;
}

static void speak_sym(int sym, int mods)
{
	if (mods){
		if (mods & TUIM_SHIFT){
			espeak_Key("SHIFT");
		}
		if (mods & TUIM_CTRL){
			espeak_Key("CONTROL");
		}
		if (mods & TUIM_ALT){
			espeak_Key("ALT");
		}
		if (mods & TUIM_META){
			espeak_Key("META");
		}
	}

#define S(X) espeak_Key(X); break;

	switch (sym){
	case TUIK_UNKNOWN: S("unknown")
	case TUIK_BACKSPACE: S("backspace")
	case TUIK_TAB: S("tab")
	case TUIK_CLEAR: S("clear")
	case TUIK_RETURN: S("return")
	case TUIK_PAUSE: S("pause")
	case TUIK_ESCAPE: S("escape")
	case TUIK_SPACE: S("space")
	case TUIK_EXCLAIM: S("exclaim")
	case TUIK_QUOTEDBL: S("doublequote")
	case TUIK_HASH: S("hash")
	case TUIK_DOLLAR: S("dollar")
	case TUIK_0:S("zero")
	case TUIK_1:S("one")
	case TUIK_2:S("two")
	case TUIK_3:S("three")
	case TUIK_4:S("four")
	case TUIK_5:S("five")
	case TUIK_6:S("six")
	case TUIK_7:S("seven")
	case TUIK_8:S("eight")
	case TUIK_9:S("nine")
	case TUIK_MINUS: S("minus")
	case TUIK_EQUALS: S("equals")
	case TUIK_A: S("a")
	case TUIK_B: S("b")
	case TUIK_C: S("c")
	case TUIK_D: S("d")
	case TUIK_E: S("e")
	case TUIK_F: S("f")
	case TUIK_G: S("g")
	case TUIK_H: S("h")
	case TUIK_I: S("i")
	case TUIK_J: S("j")
	case TUIK_K: S("k")
	case TUIK_L: S("l")
	case TUIK_M: S("m")
	case TUIK_N: S("n")
	case TUIK_O: S("o")
	case TUIK_P: S("p")
	case TUIK_Q: S("q")
	case TUIK_R: S("r")
	case TUIK_S: S("s")
	case TUIK_T: S("t")
	case TUIK_U: S("u")
	case TUIK_V: S("v")
	case TUIK_W: S("w")
	case TUIK_X: S("x")
	case TUIK_Y: S("y")
	case TUIK_Z: S("z")
	case TUIK_LESS: S("less")
	case TUIK_KP_LEFTBRACE: S("leftbrace")
	case TUIK_KP_RIGHTBRACE: S("rightbrace")
	case TUIK_KP_ENTER: S("keypadenter")
	case TUIK_LCTRL: S("leftcontrol")
	case TUIK_SEMICOLON: S("semicolon")
	case TUIK_LSHIFT: S("leftshift")
	case TUIK_BACKSLASH: S("backslash")
	case TUIK_COMMA: S("comma")
	case TUIK_PERIOD: S("period")
	case TUIK_SLASH: S("slash")
	case TUIK_RSHIFT: S("rshift")
	case TUIK_KP_MULTIPLY: S("multiply")
	case TUIK_LALT: S("leftalt")
	case TUIK_CAPSLOCK: S("capslock")
	case TUIK_F1: S("f1")
	case TUIK_F2: S("f2")
	case TUIK_F3: S("f3")
	case TUIK_F4: S("f4")
	case TUIK_F5: S("f5")
	case TUIK_F6: S("f6")
	case TUIK_F7: S("f7")
	case TUIK_F8: S("f8")
	case TUIK_F9: S("f9")
	case TUIK_F10: S("f10")
	case TUIK_NUMLOCKCLEAR: S("numlock")
	case TUIK_SCROLLLOCK: S("scrollock")
	case TUIK_KP_0: S("kp0")
	case TUIK_KP_1: S("kp1")
	case TUIK_KP_2: S("kp2")
	case TUIK_KP_3: S("kp3")
	case TUIK_KP_4: S("kp4")
	case TUIK_KP_5: S("kp5")
	case TUIK_KP_6: S("kp6")
	case TUIK_KP_7: S("kp7")
	case TUIK_KP_8: S("kp8")
	case TUIK_KP_9: S("kp9")
	case TUIK_KP_MINUS: S("kpminus")
	case TUIK_KP_PLUS: S("kpplus")
	case TUIK_KP_PERIOD: S("kpperiod")
	case TUIK_F11: S("f11")
	case TUIK_F12: S("f12")
	case TUIK_INTERNATIONAL3: S("int3")
	case TUIK_INTERNATIONAL4: S("int4")
	case TUIK_INTERNATIONAL5: S("int5")
	case TUIK_INTERNATIONAL6: S("int6")
	case TUIK_INTERNATIONAL7: S("int7")
	case TUIK_INTERNATIONAL8: S("int8")
	case TUIK_RCTRL: S("rightcontrol")
	case TUIK_KP_DIVIDE: S("kpdivide")
	case TUIK_PRINT: S("print")
	case TUIK_SYSREQ: S("sysreq")
	case TUIK_RALT: S("rightalt")
	case TUIK_HOME: S("home")
	case TUIK_UP: S("up")
	case TUIK_PAGEUP: S("pageup")
	case TUIK_LEFT: S("left")
	case TUIK_RIGHT: S("right")
	case TUIK_END: S("end")
	case TUIK_DOWN: S("down")
	case TUIK_PAGEDOWN: S("pagedown")
	case TUIK_INSERT: S("insert")
	case TUIK_DELETE: S("delete")
	case TUIK_LMETA: S("leftmeta")
	case TUIK_RMETA: S("rightmeta")
	case TUIK_COMPOSE: S("compose")
	case TUIK_MUTE: S("mute")
	case TUIK_POWER: S("power")
	case TUIK_KP_EQUALS: S("kpequal")
	case TUIK_KP_PLUSMINUS: S("plusminus")
	case TUIK_LANG1: S("lang1")
	case TUIK_LANG2: S("lang2")
	case TUIK_LANG3: S("lang3")
	case TUIK_LGUI: S("leftgui")
	case TUIK_RGUI: S("rightgui")
	case TUIK_STOP: S("stop")
	case TUIK_AGAIN: S("again")
	default: S("unknownkey")
	}
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

	t2s.cont = cont;
	t2s.fmt = fmt;

	if (arg_lookup(args, "pitch", 0, &work) && work){
		unsigned long val = strtoul(work, NULL, 10);
		if (val == 0 && val <= 100){
			espeak_SetParameter(espeakPITCH, val, 0);
		}
	}

	if (arg_lookup(args, "cappitch", 0, &work) && work){
		unsigned long val = strtoul(work, NULL, 10);
		if (val <= 10000){
			espeak_SetParameter(espeakCAPITALS, 3 + val, 0);
		}
	}
	else if (arg_lookup(args, "capmode", 0, &work) && work){
		if (strcmp(work, "icon") == 0){
			espeak_SetParameter(espeakCAPITALS, 1, 0);
		}
		else if (strcmp(work, "spelling") == 0){
			espeak_SetParameter(espeakCAPITALS, 2, 0);
		}
		else
			espeak_SetParameter(espeakCAPITALS, 0, 0);
	}

	if (arg_lookup(args, "punct", 0, &work) && work){
		unsigned long val = strtoul(work, NULL, 10);
		espeak_SetParameter(espeakPUNCTUATION, val, 0);
	}

	if (arg_lookup(args, "range", 0, &work) && work){
		unsigned long val = strtoul(work, NULL, 10);
		if (val <= 100){
			espeak_SetParameter(espeakRANGE, val, 0);
		}
	}

	if (arg_lookup(args, "gap", 0, &work) && work){
		unsigned long val = strtoul(work, NULL, 10);
		if (val <= 100){
			espeak_SetParameter(espeakWORDGAP, val, 0);
		}
	}

	if (arg_lookup(args, "rate", 0, &work) && work){
		unsigned long val = strtoul(work, NULL, 10);
		if (val >= 80 && val <= 450){
			espeak_SetParameter(espeakRATE, val, 0);
		}
		t2s.defaultRate = val;
	}
	if (arg_lookup(args, "voice", 0, &work) && work){
		espeak_SetVoiceByName(work);
	}

#define ENCLABEL(X) arcan_shmif_enqueue(t2s.cont, &(struct arcan_event){\
		.ext.kind = ARCAN_EVENT(LABELHINT),\
		.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL,\
		.ext.labelhint.label = X});

	arcan_event ev;
	ENCLABEL("FAST");
	ENCLABEL("SLOW");
	ENCLABEL("DEFAULT");
	ENCLABEL("INCRATE");
	ENCLABEL("DECRATE");
	ENCLABEL("PITCHUP");
	ENCLABEL("PITCHDOWN");
	ENCLABEL("RAW");
	ENCLABEL("SSML");
	ENCLABEL("PHONEMES");
	ENCLABEL("SETRATE");

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

		if (EE_OK != espeak_Synth(msg,
			strlen(msg)+1, 0, POS_WORD, 0, t2s.flags | espeakENDPAUSE, NULL, NULL)){
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
		flush_event(ev);

/* this can happen with MESSAGE -> MESSAGE -> RESET (inside callback) as we
 * are not allowed to call Cancel from within the callback */
		if (t2s.cancel){
			espeak_Cancel();
			t2s.cancel = false;
		}
	}
	return EXIT_SUCCESS;
}

static bool flush_event(arcan_event ev)
{
/* mainly here as a debugging facility as it is only the individual utf8-
 * characters that gets spoken, so anything higher level is better sent as
 * simple messages */
	if (ev.category == EVENT_IO){
		if (ev.io.datatype == EVENT_IDATATYPE_TRANSLATED){
			if (!ev.io.input.translated.active)
				return true;

			if (!ev.io.input.translated.utf8[0] || ev.io.input.translated.utf8[0] == 0x08)
				speak_sym(ev.io.input.translated.keysym, ev.io.input.translated.modifiers);
			else
				espeak_Key((char*)ev.io.input.translated.utf8);
		}
		else if (ev.io.datatype == EVENT_IDATATYPE_DIGITAL){
			apply_label(ev.io.label);
		}
	}
	else if (ev.category == EVENT_TARGET){
		switch (ev.tgt.kind){
/* the UTF-8 validation should be stronger here, which can just be lifted
 * from the way it is done in arcan_tui */
		case TARGET_COMMAND_MESSAGE:
			merge_message(&ev.tgt);
		break;
		case TARGET_COMMAND_RESET:{
	/*
			arcan_shmif_enqueue(t2s.cont,
				&(arcan_event){
				.category = EVENT_EXTERNAL,
				.ext.kind = ARCAN_EVENT(FLUSHAUD)}
			);
	*/
			t2s.cancel = true;
			return false;
		}
		break;
		default:
		break;
		}
	}
	return true;
}
