/* uuterm, Copyright (C) 2006 Rich Felker; licensed under GNU GPL v2 only */

#include <stddef.h>
#include <stdint.h>
#include <wchar.h>

struct uucell
{
	uint32_t x[3];
};

struct uurow
{
	int idx;
	int x1, x2; /* dirty region */
	struct uucell cells[1];
};

/* Cell-preserved attributes must lie in 0xC000FC01, see cell.c */

#define UU_ATTR_UL      0x00000001
#define UU_ATTR_BOLD    0x00000002
#define UU_ATTR_BLINK   0x00000004
#define UU_ATTR_DIM     0x00000008
#define UU_ATTR_REV     0x00000010

struct uuterm
{
	struct uurow **rows;
	int w, h;

	// all members past this point are zero-filled on reset!
	int reset;

	// output state
	int x, y;
	int attr;
	int color;
	int sr_y1, sr_y2;
	int ins  :1;
	int am   :1;
	int noam :1;

	// input state
	int ckp  :1;
	int kp   :1;
	char reslen;
	char res[16];

	// saved state
	int save_x, save_y;
	int save_attr, save_fg, save_bg;

	// escape sequence processing
	int esc;
	unsigned param[16];
	int nparam;

	// multibyte parsing
	mbstate_t mbs;
};

struct uudisp
{
	int cell_w, cell_h;
	int w, h;
	int inlen;
	unsigned char *intext;
	unsigned char inbuf[64];
	int blink;
	void *font;
	long priv[64];
};

#define UU_FULLWIDTH 0xfffe

#define UU_ROW_SIZE(w) (sizeof(struct uurow) + (w)*sizeof(struct uucell))
#define UU_BUF_SIZE(w, h) ( (h) * (sizeof(struct uurow *) * UU_ROW_SIZE((w))) )

void uuterm_reset(struct uuterm *);
void uuterm_replace_buffer(struct uuterm *, int, int, void *);
void uuterm_stuff_byte(struct uuterm *, unsigned char);

void uuterm_refresh_row(struct uudisp *, struct uurow *, int, int);

void uucell_set(struct uucell *, wchar_t, int, int);
void uucell_append(struct uucell *, wchar_t);
int uucell_get_attr(struct uucell *);
int uucell_get_color(struct uucell *);
int uucell_get_wcs(struct uucell *, wchar_t *, size_t);

int uu_decompose_char(unsigned, unsigned *, unsigned);

int uudisp_open(struct uudisp *);
int uudisp_fd_set(struct uudisp *, int, void *);
void uudisp_next_event(struct uudisp *, void *);
void uudisp_close(struct uudisp *);
void uudisp_refresh(struct uudisp *, struct uuterm *);
void uudisp_predraw_cell(struct uudisp *, int, int, int);
void uudisp_draw_glyph(struct uudisp *, int, int, const void *);

void *uuterm_alloc(size_t);
void uuterm_free(void *);
void *uuterm_buf_alloc(int, int);

void uutty_resize(int, int, int);
int uutty_open(char **, int, int);
