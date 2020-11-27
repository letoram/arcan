#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <arcan_tuisym.h>
#include <inttypes.h>
#include "../../../frameserver/util/utf8.c"

#include "parser.h"

static int ch_mask(char ch)
{
	switch (ch){
	case 'i':
		return TUI_ATTR_ITALIC;
	break;
	case 'u':
		return TUI_ATTR_UNDERLINE;
	break;
	case 'b':
		return TUI_ATTR_BOLD;
	break;
	default:
		return 0;
	break;
	}
}

static void set_attr(struct tui_screen_attr* a, char ch, bool val)
{
	int mask = ch_mask(ch);
	if (!mask)
		return;

	if (val){
		a->aflags |= mask;
	}
	else
		a->aflags &= ~mask;
}

static void flip_attr(struct tui_screen_attr* a, char ch)
{
	int mask = ch_mask(ch);
	a->aflags ^= mask;
}

static uint8_t hexv(char ch)
{
	return ((ch & 0xf) + (ch >> 6)) | ((ch >> 3) & 0x8);
}

static uint8_t chhex(char data[static 2])
{
	return 16 * hexv(data[0]) + hexv(data[1]);
}

static void col_to_attr(char data[static 6], uint8_t dst[static 3])
{
	dst[0] = chhex(&data[0]);
	dst[1] = chhex(&data[2]);
	dst[2] = chhex(&data[4]);
}

/* process [cmd] with data from [data] and store results in [texticon_state] */
static void update_cattr(
	struct tui_context* tui,
	int cmd,
	struct texticon_state* state,
	char data[static 32])
{
	switch (cmd){
/* '-' means revert to default, # sets hex color */
	case 'B':
		if (data[0] == '-'){
			arcan_tui_get_bgcolor(tui, TUI_COL_BG, state->attr.bc);
		}
		else if (data[0] == '#'){
			col_to_attr(&data[1], state->attr.bc);
		}
	break;
/* same with fg color */
	case 'F':
		if (data[0] == '-'){
			arcan_tui_get_color(tui, TUI_COL_TEXT, state->attr.fc);
		}
		else if (data[0] == '#'){
			col_to_attr(&data[1], state->attr.fc);
		}
	break;
	case 'R':{
		uint8_t bc[3];
		memcpy(bc, state->attr.bc, 3);
		memcpy(state->attr.bc, state->attr.fc, 3);
		memcpy(state->attr.fc, bc, 3);
	}
	break;
	case 'i':
		state->align = -1;
	break;
	case 'c':
		state->align = 0;
	break;
	case 'r':
		state->align = 1;
/* a defines clickable region[num:msg:] start, empty A defines clock stop */
	case 'A':
/* if not ":" in buffer, stop parsing */
	break;
	case 'U':
/* we can't color underline at the moment */
	break;
	case 'u':
		state->attr.aflags |= TUI_ATTR_UNDERLINE;
	break;
	case 'o':
	break;
/* set, invert, unset attributes (u underline, b bold, i italic) */
	case '+':
		set_attr(&state->attr, data[0], true);
	break;
	case '!':
		flip_attr(&state->attr, data[0]);
	break;
	case '-':
		set_attr(&state->attr, data[0], false);
	break;
	case 'T':
/* font controls not supported */
	break;
/* offset is a no-op as we don't have per-pixel addressing */
	case 'O':
	break;
	}
}

/* split into tag+buffer */
struct parser_state {
	int level;
	int cmd;
	size_t ppos;
	char data[32];
};

void parse_lemon(
	struct tui_context* tui, struct parser_data* dst, char* inbuf)
{
/* Fill with a base attribute, the input format can override it locally */
	struct tui_cell cell = {};
	static struct parser_state parser = {
		.level = 0
	};

	arcan_tui_get_color(tui, TUI_COL_TEXT, cell.attr.fc);
	arcan_tui_get_bgcolor(tui, TUI_COL_BG, cell.attr.bc);

/* reset render buffer to default state */
	for (size_t i = 0; i < dst->buffer_count; i++){
		dst->buffer[i] = cell;
	}

/* process input string and apply to buffer state */
	size_t in = 0, out = 0;
	uint32_t cp = 0;
	uint32_t utf = 0;
	const char token = '%';

	while(inbuf[in]){
/* process parser logic that might update the cell.attr */
		if (parser.level == 1){
			switch(inbuf[in]){
			case '{' :
			case '[' :
			case '(' :
				parser.level++;
			break;
/* re-emit / escaped */
			case '%' :
				parser.level = 0;
				dst->buffer[out++].ch = '%';
/* wrong format */
			break;
			}
		in++;
		}
		else if (parser.level == 2){
			switch (inbuf[in]){
/* no-op or process buffer into attribute */
			case ')' :
			case '}' :
			case ']' :
				parser.level = 0;
				parser.ppos = 0;
			break;
			default:
				parser.cmd = inbuf[in];
				parser.level++;
			break;
			}
			in++;
		}
/* buffer until ), truncate on overflow */
		else if (parser.level == 3){
			switch (inbuf[in]){
			case ')' :
			case '}' :
			case ']' :
				update_cattr(tui, parser.cmd, &dst->icon, parser.data);
				parser.ppos = 0;
				parser.level = 0;
				parser.cmd = 0;
				memset(parser.data, '\0', sizeof(parser.data));
			break;
			default:
				if (parser.ppos < sizeof(parser.data)-1)
					parser.data[parser.ppos++] = inbuf[in];
			break;
			}
			in++;
		}
		else if (inbuf[in] == token){
			parser.level++;
			in++;
		}
/* or let the utf8 state machine consume and spit it out */
		else
			if ((utf8_decode(&utf, &cp, inbuf[in++]) != UTF8_REJECT)){
				if (utf== UTF8_ACCEPT){
					dst->buffer[out].ch = cp;
					dst->buffer[out].attr = dst->icon.attr;
					out++;
				}
			}
	}

	dst->buffer_used = out;
}
