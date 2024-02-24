#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../tui_int.h"
#include "../../../frameserver/util/utf8.c"

#include <stdio.h>
#include <inttypes.h>
#include <math.h>
#include <errno.h>

struct lent {
	int ctx;
	const char* lbl;
	const char* descr;
	uint8_t vsym[5];
	bool(*ptr)(struct tui_context*);
	uint16_t initial;
	uint16_t modifiers;
};

void tui_expose_labels(struct tui_context* tui)
{
	arcan_event ev = {
		.category = EVENT_EXTERNAL,
		.ext.kind = ARCAN_EVENT(LABELHINT),
		.ext.labelhint.idatatype = EVENT_IDATATYPE_DIGITAL
	};

/* send an empty label first as a reset */
	arcan_shmif_enqueue(&tui->acon, &ev);

/* then forward to a possible callback handler */
	size_t ind = 0;
	if (tui->handlers.query_label){
		while (true){
			struct tui_labelent dstlbl = {};
			if (!tui->handlers.query_label(tui,
			ind++, "ENG", "ENG", &dstlbl, tui->handlers.tag))
				break;

			snprintf(ev.ext.labelhint.label,
				COUNT_OF(ev.ext.labelhint.label), "%s", dstlbl.label);
			snprintf(ev.ext.labelhint.descr,
				COUNT_OF(ev.ext.labelhint.descr), "%s", dstlbl.descr);
			ev.ext.labelhint.subv = dstlbl.subv;
			ev.ext.labelhint.idatatype = dstlbl.idatatype ? dstlbl.idatatype : EVENT_IDATATYPE_DIGITAL;
			ev.ext.labelhint.modifiers = dstlbl.modifiers;
			ev.ext.labelhint.initial = dstlbl.initial;
			snprintf((char*)ev.ext.labelhint.vsym,
				COUNT_OF(ev.ext.labelhint.vsym), "%s", dstlbl.vsym);
			arcan_shmif_enqueue(&tui->acon, &ev);
		}
	}
}

static int update_mods(int mods, int sym, bool pressed)
{
	if (pressed)
	switch(sym){
	case TUIK_LSHIFT: return mods | ARKMOD_LSHIFT;
	case TUIK_RSHIFT: return mods | ARKMOD_RSHIFT;
	case TUIK_LCTRL: return mods | ARKMOD_LCTRL;
	case TUIK_RCTRL: return mods | ARKMOD_RCTRL;
	case TUIK_COMPOSE:
	case TUIK_LMETA: return mods | ARKMOD_LMETA;
	case TUIK_RMETA: return mods | ARKMOD_RMETA;
	default:
		return mods;
	}
	else
	switch(sym){
	case TUIK_LSHIFT: return mods & (~ARKMOD_LSHIFT);
	case TUIK_RSHIFT: return mods & (~ARKMOD_RSHIFT);
	case TUIK_LCTRL: return mods & (~ARKMOD_LCTRL);
	case TUIK_RCTRL: return mods & (~ARKMOD_RCTRL);
	case TUIK_COMPOSE:
	case TUIK_LMETA: return mods & (~ARKMOD_LMETA);
	case TUIK_RMETA: return mods & (~ARKMOD_RMETA);
	default:
		return mods;
	}
}

static bool consume_label(
	struct tui_context* tui, arcan_ioevent* ioev, const char* label)
{
	bool res = false;
	if (tui->handlers.input_label){
		res |= tui->handlers.input_label(tui, label, true, tui->handlers.tag);

/* also send release if the forward was ok */
		if (res)
			tui->handlers.input_label(tui, label, false, tui->handlers.tag);
	}

	return res;
}

void tui_input_event(
	struct tui_context* tui, arcan_ioevent* ioev, const char* label)
{
	if (tui->hooks.input){
		return tui->hooks.input(tui, ioev, label);
	}

	if (ioev->datatype == EVENT_IDATATYPE_TRANSLATED){
		bool pressed = ioev->input.translated.active;
		int sym = ioev->input.translated.keysym;
		int oldm = tui->modifiers;
		tui->modifiers = update_mods(tui->modifiers, sym, pressed);

/* note that after this point we always fake 'release' and forward as a
 * press->release on the same label within consume label */
		if (!pressed)
			return;

		tui->inact_timer = -4;
		if (label[0] && consume_label(tui, ioev, label))
			return;

/* modifiers doesn't get set for the symbol itself which is a problem
 * for when we want to forward modifier data to another handler like mbtn */
		if (sym >= 300 && sym <= 314)
			return;

/* check the incoming utf8 if it's valid, if so forward and if the handler
 * consumed the value, leave the function */
		int len = 0;
		bool valid = true;
		uint32_t codepoint = 0, state = 0;
		while (len < 5 && ioev->input.translated.utf8[len]){
			if (UTF8_REJECT == utf8_decode(&state, &codepoint,
				ioev->input.translated.utf8[len])){
				valid = false;
				break;
			}
			len++;
		}

/* disallow the private-use area */
		if ((codepoint >= 0xe000 && codepoint <= 0xf8ff))
			valid = false;

		if (valid && ioev->input.translated.utf8[0] && tui->handlers.input_utf8){
			if (tui->handlers.input_utf8 && tui->handlers.input_utf8(tui,
					(const char*)ioev->input.translated.utf8,
					len, tui->handlers.tag))
				return;
		}

/* otherwise, forward as much of the key as we know */
		if (tui->handlers.input_key)
			tui->handlers.input_key(tui,
				sym,
				ioev->input.translated.scancode,
				ioev->input.translated.modifiers,
				ioev->subid, tui->handlers.tag
			);
	}
	else if (ioev->devkind == EVENT_IDEVKIND_MOUSE){
		if (ioev->datatype == EVENT_IDATATYPE_ANALOG){
			bool update = false;
			int x, y;
			if (!arcan_shmif_mousestate_ioev(&tui->acon, tui->mouse_state, ioev, &x, &y))
				return;

			tui->mouse_x = x / tui->cell_w;
			tui->mouse_y = y / tui->cell_h;

			if (tui->mouse_y >= tui->rows)
				tui->mouse_y = tui->rows - 1;

			if (tui->mouse_x >= tui->cols)
				tui->mouse_x = tui->cols - 1;

			if (tui->handlers.input_mouse_motion){
				tui->handlers.input_mouse_motion(tui, false,
					tui->mouse_x, tui->mouse_y, tui->modifiers, tui->handlers.tag);
			}

			return;
		}
		else if (ioev->datatype == EVENT_IDATATYPE_DIGITAL){
			if (ioev->subid){
				if (ioev->input.digital.active)
					tui->mouse_btnmask |=  (1 << (ioev->subid-1));
				else
					tui->mouse_btnmask &= ~(1 << (ioev->subid-1));
			}
			if (tui->handlers.input_mouse_button){
				tui->handlers.input_mouse_button(tui, tui->mouse_x,
					tui->mouse_y, ioev->subid, ioev->input.digital.active,
					tui->modifiers, tui->handlers.tag
				);
				return;
			}

			if (ioev->flags & ARCAN_IOFL_GESTURE){
				if (strcmp(ioev->label, "dblclick") == 0){
				}
				else if (strcmp(ioev->label, "click") == 0){
				}
				return;
			}

			if (ioev->subid == TUIBTN_WHEEL_UP){
				if (ioev->input.digital.active && tui->handlers.input_key){
						tui->handlers.input_key(tui,
						((tui->modifiers & (ARKMOD_LSHIFT | ARKMOD_RSHIFT)) ? TUIK_PAGEUP : TUIK_UP),
						ioev->input.translated.scancode,
						0,
						ioev->subid, tui->handlers.tag
					);
				}
			}
			else if (ioev->subid == TUIBTN_WHEEL_DOWN){
				if (ioev->input.digital.active && tui->handlers.input_key){
					tui->handlers.input_key(tui,
						((tui->modifiers & (ARKMOD_LSHIFT | ARKMOD_RSHIFT)) ? TUIK_PAGEDOWN : TUIK_DOWN),
						ioev->input.translated.scancode,
						0,
						ioev->subid, tui->handlers.tag
					);
				}
			}
		}
		else if (tui->handlers.input_misc)
			tui->handlers.input_misc(tui, ioev, tui->handlers.tag);
	}
}
