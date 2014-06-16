/* uuterm, Copyright (C) 2006 Rich Felker; licensed under GNU GPL v2 only */

#include <wchar.h>
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "uuterm.h"

#define isdigit(x) ((unsigned)x-'0' < 10)

static void process_char(struct uuterm *t, unsigned c);

static void scroll(struct uuterm *t, int y1, int y2, int rev)
{
	int fwd = 1-rev;
	struct uurow *new = t->rows[(y1&-fwd)|(y2&-rev)];
	memset(new->cells, 0, t->w * sizeof(struct uucell));
	new->x1 = 0;
	new->x2 = t->w-1;
	memmove(&t->rows[y1+rev], &t->rows[y1+fwd], (y2-y1) * sizeof(struct uurow *));
	t->rows[(y2&-fwd)|(y1&-rev)] = new;
}

static void dirty(struct uuterm *t, int y, int x1, int len)
{
	int x2 = x1 + len - 1;
	struct uurow *r = t->rows[y];
	/* account for potentially affected ligatures */
	if (x1) x1--; if (x2<t->w-1) x2++;
	//r->x1 += (x1 - r->x1) & (x1 - r->x1)>>8*sizeof(int)-1;
	//r->x2 += (x2 - r->x2) & (r->x2 - x2)>>8*sizeof(int)-1;
	if (x1 < r->x1) r->x1 = x1;
	if (x2 > r->x2) r->x2 = x2;
}

static void bell(struct uuterm *t)
{
}

static void erase_line(struct uuterm *t, int dir)
{
	int start[3] = { t->x, 0, 0 };
	int len[3] = { t->w-t->x, t->x+1, t->w };
	if ((unsigned)dir > 2) return;
	memset(t->rows[t->y]->cells+start[dir], 0, len[dir] * sizeof(struct uucell));
	dirty(t, t->y, start[dir], len[dir]);
}

static void erase_display(struct uuterm *t, int dir)
{
	int i;
	int start[3] = { t->y+1, 0, 0 };
	int stop[3] = { t->h, t->y, t->h };
	if ((unsigned)dir > 2) return;
	erase_line(t, dir);
	for (i=start[dir]; i<stop[dir]; i++) {
		memset(t->rows[i]->cells, 0, t->w * sizeof(struct uucell));
		dirty(t, i, 0, t->w);
	}
}

static void reset(struct uuterm *t)
{
	/* cheap trick */
	memset(&t->reset, 0, sizeof *t - offsetof(struct uuterm, reset));
	t->attr = 0;
	t->color = 7;
	t->sr_y2 = t->h - 1;
	erase_display(t, 2);
}

static void ins_del_char(struct uuterm *t, unsigned n, int ins)
{
	int del = 1-ins;
	struct uucell *base;
	if (n >= t->w - t->x) {
		erase_line(t, 0);
		return;
	}
	base = t->rows[t->y]->cells + t->x;
	memmove(base+(n&-ins), base+(n&-del), (t->w-t->x-n) * sizeof(struct uucell));
	memset(base+((t->w-t->x-n)&-del), 0, n * sizeof(struct uucell));
	dirty(t, t->y, t->x, t->w - t->x);
}

static void ins_del_lines(struct uuterm *t, int n, int ins)
{
	if ((unsigned)t->y - t->sr_y1 > t->sr_y2 - t->sr_y1) return;
	while (n--) scroll(t, t->y, t->sr_y2, ins);
}

static void newline(struct uuterm *t)
{
	process_char(t, '\r');
	process_char(t, '\n');
}

static int itoa(char *s, unsigned n)
{
	// FIXME!!
	*s = '1';
	return 1;
}

#define CSI '['
#define OSC ']'
#define IGNORE1 2
#define ID_STRING "\033[?6c"
#define OK_STRING "\033[0n"
#define PRIVATE ((unsigned)-1)

static void csi(struct uuterm *t, unsigned c)
{
	int i;
	int ins=0;
	if (c == '?') {
		t->param[t->nparam] = PRIVATE;
		if (++t->nparam != 16) return;
	}
	if (isdigit(c)) {
		t->param[t->nparam] = 10*t->param[t->nparam] + c - '0';
		return;
	}
	if (c == ';' && ++t->nparam != 16)
		return;
	t->esc = 0;
	t->nparam++;
	if (strchr("@ABCDEFGHLMPXaefr`", c) && !t->param[0])
		t->param[0]++;
	switch (c) {
	case 'F':
		process_char(t, '\r');
	case 'A':
		t->y -= t->param[0];
		break;
	case 'E':
		process_char(t, '\r');
	case 'e':
	case 'B':
		t->y += t->param[0];
		break;
	case 'a':
	case 'C':
		t->x += t->param[0];
		t->am = 0;
		break;
	case 'D':
		t->x -= t->param[0];
		t->am = 0;
		break;
	case '`':
	case 'G':
		t->x = t->param[0]-1;
		t->am = 0;
		break;
	case 'f':
	case 'H':
		if (!t->param[1]) t->param[1]++;
		t->y = t->param[0]-1;
		t->x = t->param[1]-1;
		t->am = 0;
		break;
	case 'J':
		erase_display(t, t->param[0]);
		break;
	case 'K':
		erase_line(t, t->param[0]);
		break;
	case 'L':
		ins=1;
	case 'M':
		ins_del_lines(t, t->param[0], ins);
		break;
	case '@':
		ins=1;
	case 'P':
		ins_del_char(t, t->param[0], ins);
		break;
	case 'd':
		t->y = t->param[0]-1;
		break;
	case 'h':
	case 'l':
		i = c=='h';
		switch (t->param[0]) {
		case PRIVATE:
			switch(t->param[1]) {
			case 1:
				t->ckp = i;
				break;
			}
			break;
		case 4:
			t->ins = i;
			break;
		}
		break;
	case 'm':
		for (i=0; i<t->nparam; i++) {
			static const unsigned short attr[] = {
				UU_ATTR_BOLD, UU_ATTR_DIM, 0,
				UU_ATTR_UL, UU_ATTR_BLINK, 0,
				UU_ATTR_REV
			};
			if (t->param[i] == 39) t->param[i] = 37;
			if (t->param[i] == 49) t->param[i] = 40;
			if (!t->param[i]) {
				t->attr = 0;
				t->color = 7;
			} else if (t->param[i] < 8) {
				t->attr |= attr[t->param[i]-1];
			} else if (t->param[i]-21 < 7) {
				t->attr &= ~attr[t->param[i]-21];
			} else if (t->param[i]-30 < 8) {
				t->color &= ~255;
				t->color |= t->param[i] - 30;
			} else if (t->param[i]-40 < 8) {
				t->color &= ~(255<<8);
				t->color |= t->param[i] - 40 << 8;
			}
		}
		if ((t->color&255) < 16)
			if (t->attr & UU_ATTR_BOLD)
				t->color |= 8;
			else
				t->color &= ~8;
		if ((t->color>>8) < 16)
			if (t->attr & UU_ATTR_BLINK)
				t->color |= 8<<8;
			else
				t->color &= ~(8<<8);
		break;
	case 'n':
		switch (t->param[0]) {
		case 5:
			strcpy(t->res, OK_STRING);
			t->reslen = sizeof(OK_STRING)-1;
			break;
		case 6:
			t->res[0] = 033;
			t->res[1] = '[';
			i=2+itoa(t->res+2, t->x+1);
			t->res[i++] = ';';
			i+=itoa(t->res+i, t->y+1);
			t->res[i++] = 'R';
			t->reslen = i;
			break;
		}
		break;
	case 'r':
		if (!t->param[1]) t->param[1] = t->h;
		t->sr_y1 = t->param[0]-1;
		t->sr_y2 = t->param[1]-1;
		if (t->sr_y1 < 0) t->sr_y1 = 0;
		if (t->sr_y2 >= t->h) t->sr_y2 = t->h-1;
		if (t->sr_y1 > t->sr_y2) {
			t->sr_y1 = 0;
			t->sr_y2 = t->h-1;
		}
		break;
	case 's':
		t->save_x = t->x;
		t->save_y = t->y;
		break;
	case 'u':
		t->x = t->save_x;
		t->y = t->save_y;
		t->am = 0;
		break;
	case '[':
		t->esc = IGNORE1;
		break;
	}
	if ((unsigned)t->y >= t->h) {
		if (t->y < 0) t->y = 0;
		else t->y = t->h-1;
	}
	if ((unsigned)t->x >= t->w) {
		if (t->x < 0) t->x = 0;
		else t->x = t->w-1;
	}
}

static void escape(struct uuterm *t, unsigned c)
{
	int rev=0;
	if ((c & ~2) == 030) {
		t->esc = 0;
		return;
	}
	if (t->esc == CSI) {
		csi(t, c);
		return;
	} else if (t->esc == OSC) {
		//FIXME
		t->esc = 0;
		return;
	} else if (t->esc == IGNORE1) {
		t->esc = 0;
		return;
	}
	t->esc = 0;
	switch (c) {
	case 'c':
		reset(t);
		break;
	case 'D':
		process_char(t, '\n');
		break;
	case 'E':
		newline(t);
		break;
	case 'M':
		if (t->y == t->sr_y1) scroll(t, t->sr_y1, t->sr_y2, 1);
		else if (t->y > 0) t->y--;
		break;
	case 'Z':
		strcpy(t->res, ID_STRING);
		t->reslen = sizeof(ID_STRING)-1;
		break;
	case '7':
		t->save_attr = t->attr;
		t->save_x = t->x;
		t->save_y = t->y;
		break;
	case '8':
		t->attr = t->save_attr;
		t->x = t->save_x;
		t->y = t->save_y;
		t->am = 0;
		break;
	case '[':
		t->esc = CSI;
		t->nparam = 0;
		memset(t->param, 0, sizeof t->param);
		break;
	case '>':
		t->kp = 0;
		break;
	case '=':
		t->kp = 1;
		break;
	case ']':
		t->esc = OSC;
		t->nparam = 0;
		memset(t->param, 0, sizeof t->param);
		break;
	}
}

static void process_char(struct uuterm *t, unsigned c)
{
	int x, y, w;
	t->reslen = 0; // default no response
	if (c - 0x80 < 0x20) {
		/* C1 control codes */
		process_char(t, 033);
		process_char(t, c-0x40);
		return;
	}
	if (t->esc) {
		escape(t, c);
		return;
	}
	if (iswcntrl(c)) w = -1;
	else if ((w = wcwidth(c)) < 0) w = 1;
	switch(w) {
	case -1:
		switch (c) {
		case 033:
			t->esc = 1;
			break;
		case '\r':
			t->x = 0;
			t->am = 0;
			break;
		case '\n':
			if (t->y == t->sr_y2) scroll(t, t->sr_y1, t->sr_y2, 0);
			else if (t->y < t->h-1) t->y++;
			break;
		case '\t':
			t->x = (t->x + 8) & ~7;
			t->am = 1;
			if (t->x >= t->w)
				t->x = t->w - 1;
			else
				t->am = 0;
			break;
		case '\b':
			if (!t->am && t->x) t->x--;
			t->am = 0;
			break;
		case '\a':
			bell(t);
			break;
		default:
			process_char(t, 0xfffd);
			break;
		}
		break;
	case 0:
		y = t->y;
		x = t->x;
		if (t->am) x++;
		if (!x--) {
			/* nothing to combine at home position */
			if (!y--) return;
			x = 0;
		}

		uucell_append(&t->rows[y]->cells[x], c);
		dirty(t, y, x, 1);
		break;
	case 1:
	case 2:
		if (t->ins) ins_del_char(t, w, 1);
		while (w--) {
			if (t->am) newline(t); // kills am flag
			dirty(t, t->y, t->x, 1);
			uucell_set(&t->rows[t->y]->cells[t->x++],
				w?UU_FULLWIDTH:c, t->attr, t->color);
			if (t->x == t->w) {
				t->x--;
				t->am=1;
			}
		}
		break;
	}
}

#define BAD_CHAR 0xffff

void uuterm_stuff_byte(struct uuterm *t, unsigned char b)
{
	int i, l;
	wchar_t wc;
	mbstate_t init_mbs = { };

	for (i=0; i<2; i++) {
		l = mbrtowc(&wc, &b, 1, &t->mbs);
		if (l >= 0) {
			if (wc) process_char(t, wc);
			return;
		} else if (l == -2) return;

		if (!i) process_char(t, BAD_CHAR);
		t->mbs = init_mbs;
	}
}

void uuterm_replace_buffer(struct uuterm *t, int w, int h, void *buf)
{
	int i;
	char *p = buf;
	struct uurow **rows;
	int wmin = w < t->w ? w : t->w;

	// keep the cursor on the screen after resizing
	if (t->y >= h) {
		int n = t->y - h + 1;
		t->y -= n;
		t->sr_y1 -= n;
		t->sr_y2 -= n;
		if (t->sr_y1 < 0) t->sr_y1 = 0;
		if (t->sr_y2 < 0) t->sr_y2 = 0;
		while (n--) scroll(t, 0, t->h-1, 0);
	}

	memset(p, 0, UU_BUF_SIZE(w, h));

	rows = (void *)p;
	p += h*sizeof(struct uurow *);

	for (i=0; i<h; i++, p+=UU_ROW_SIZE(w)) {
		rows[i] = (void *)p;
		if (i < t->h)
			memcpy(rows[i], t->rows[i], UU_ROW_SIZE(wmin));
		rows[i]->idx = i;
		rows[i]->x1 = 0;
		rows[i]->x2 = w-1;
	}

	if (t->sr_y2 == t->h-1) t->sr_y2 = h-1;

	t->w = w;
	t->h = h;
	t->rows = rows;

	if (t->x >= t->w) t->x = t->w - 1;
	if (t->sr_y1 >= t->h) t->sr_y1 = t->h - 1;
	if (t->sr_y2 >= t->h) t->sr_y2 = t->h - 1;
}

void uuterm_reset(struct uuterm *t)
{
	reset(t);
}
