#include <arcan_shmif.h>
#include <arcan_tui.h>
#include "arcan_tui_listwnd.h"
#include <errno.h>
#include <ctype.h>
#include <inttypes.h>
#include <stdint.h>
#include <string.h>

/*
 * Useful enhancements missing:
 *  - scroll the current selected line on tick if cropped
 *  - expose scrollbar metadata
 *  - indicate sublevel / subnodes (can turn into tree-view through mask/unmask)
 *    use an attribute for level so |-> can be added do sub-ones,
 *    more difficult is adding an expand-collapse so selection would expand
 *  - handle accessibility subwindow (provide only selected item for t2s)
 *  - allow multiple column formats for wide windows
 *  - prefix typing for searching
 */

#ifndef COUNT_OF
#define COUNT_OF(x) \
	((sizeof(x)/sizeof(0[x])) / ((size_t)(!(sizeof(x) % sizeof(0[x])))))
#endif

#define INACTIVE_ITEM (LIST_SEPARATOR | LIST_PASSIVE | LIST_HIDE)
#define HIDDEN_ITEM (LIST_HIDE)

#define LISTWND_MAGIC 0xfadef00e
struct listwnd_meta {
/* debug-help, check against LISTWND_MAGIC */
	uint32_t magic;

/* actual entries, flags can mutate, size cannot */
	struct tui_list_entry* list;
	size_t list_sz;

/* current logical cursor position and resolved screen position */
	size_t list_pos;
	size_t list_row;

/* first row start */
	size_t list_ofs;

/* set when user has made a selection, and the selected item */
	int entry_state;
	size_t entry_pos;

/* drawing characters for the flags */
	uint32_t line_ch;
	uint32_t check_ch;
	uint32_t sub_ch;

/* to restore the context */
	struct tui_cbcfg old_handlers;
	int old_flags;
};

/* context validation, perform on every exported symbol */
static bool validate(struct tui_context* T)
{
	if (!T)
		return false;

	struct tui_cbcfg handlers;
	arcan_tui_update_handlers(T, NULL, &handlers, sizeof(struct tui_cbcfg));

	struct listwnd_meta* ch = handlers.tag;
	if (!ch || ch->magic != LISTWND_MAGIC)
		return false;

	return true;
}

static size_t get_visible_offset(struct listwnd_meta* M)
{
	size_t ofs = 0;
	for (size_t i = M->list_ofs; i < M->list_pos; i++){
		if (M->list[i].attributes & HIDDEN_ITEM)
			continue;
		ofs++;
	}
	return ofs;
}

static void redraw(struct tui_context* T, struct listwnd_meta* M)
{
	size_t c_row = 0;
	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);

	if (!rows)
		return;

/* safeguard that we fit in the current screen, else we search */
	for (size_t ofs = get_visible_offset(M); ofs > rows; M->list_ofs++){
		ofs = get_visible_offset(M);
	}

	struct tui_screen_attr reset_def = arcan_tui_defattr(T, NULL);
	struct tui_screen_attr def = arcan_tui_defcattr(T, TUI_COL_LABEL);
	struct tui_screen_attr sel = arcan_tui_defcattr(T, TUI_COL_HIGHLIGHT);
	struct tui_screen_attr inact = arcan_tui_defcattr(T, TUI_COL_INACTIVE);

/* erase the screen as well as the entries can be fewer than the number of rows */
	arcan_tui_defattr(T, &def);
	arcan_tui_erase_screen(T, false);

/* now we can just clear / draw the items on the page */
	c_row = 0;
	for (size_t i = M->list_ofs; rows && i < M->list_sz; i++){
		int lattr = M->list[i].attributes;
		const char* label = M->list[i].label;

		if (lattr & HIDDEN_ITEM)
			continue;

		rows--;
		arcan_tui_move_to(T, 0, c_row);

		struct tui_screen_attr* cattr = &def;
		if (i == M->list_pos){
			cattr = &sel;
			M->list_row = c_row;
		}

/* cursor state doesn't matter for passive */
		if (lattr & LIST_PASSIVE){
			cattr = &inact;
		}

		if (lattr & LIST_SEPARATOR){
			for (size_t c = 0; c < cols; c++)
				arcan_tui_write(T, M->line_ch, &inact);
			c_row++;
			continue;
		}

/* clear the target line with the attribute (as it can contain bgc) */
		size_t ofs = 0;
		arcan_tui_defattr(T, cattr);
		arcan_tui_erase_region(T, 0, c_row, cols, 1, false);

/* tactic: draw as much as possible from starting label offset,
 * recall (& 0xc0) != 0x80 for utf8- start */
		arcan_tui_move_to(T, 1, c_row);
		for (size_t vofs = 0; vofs < cols - 2 && label[ofs]; vofs++){
			size_t end = ofs + 1;
			while (label[end] && (label[end] & 0xc0) == 0x80) end++;
			arcan_tui_writeu8(T, (const uint8_t*)&label[ofs], end - ofs, cattr);
			ofs = end;
		}

/* anotate with symbols */
		if (lattr & LIST_CHECKED){
			arcan_tui_move_to(T, 0, c_row);
			arcan_tui_write(T, M->check_ch, cattr);
		}

		if (lattr & LIST_HAS_SUB){
			arcan_tui_move_to(T, cols-1, c_row);
			arcan_tui_write(T, M->sub_ch, cattr);
		}
		c_row++;
	}

	arcan_tui_defattr(T, &reset_def);
}

static void select_current(struct tui_context* T, struct listwnd_meta* M)
{
	int flags = M->list[M->list_pos].attributes;
	if (flags & INACTIVE_ITEM)
		return;
	M->entry_state = 1;
	M->entry_pos = M->list_pos;
}

static void step_page_s(struct tui_context* T, struct listwnd_meta* M)
{
	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);

/* increment offset half- a page */
	rows = (rows >> 1) + 1;
	size_t c_row;
	for (c_row = M->list_ofs; c_row < M->list_sz && rows; c_row++){
		if (M->list[c_row].attributes & INACTIVE_ITEM)
			continue;

		rows--;
	}

/* couldn't be done */
	if (c_row == M->list_sz || M->list_pos == M->list_sz - 1){
		M->list_ofs = 0;
		M->list_pos = 0;
	}
	else{
		M->list_ofs = c_row;
		M->list_pos++;
	}

/* step cursor to next sane */
	for (c_row = M->list_pos; c_row < M->list_sz; c_row++){
		if (!(M->list[c_row].attributes & INACTIVE_ITEM)){
			M->list_pos = c_row;
			break;
		}
	}

	redraw(T, M);
}

static void step_page_n(struct tui_context* T, struct listwnd_meta* M)
{
	printf("go page north\n");
}

static void step_cursor_n(struct tui_context* T, struct listwnd_meta* M)
{
	size_t current = M->list_pos;
	size_t vis_step = 0;
	do {
		current = current > 0 ? current - 1 : M->list_sz - 1;
		if (!(M->list[current].attributes & HIDDEN_ITEM))
			vis_step++;

		if (!(M->list[current].attributes & INACTIVE_ITEM))
			break;

	} while (current != M->list_pos);

	if (M->list_row < vis_step){
		step_page_n(T, M);
		return;
	}

	M->list_pos = current;
	redraw(T, M);
}

static void step_cursor_s(struct tui_context* T, struct listwnd_meta* M)
{
	size_t rows, cols;
	arcan_tui_dimensions(T, &rows, &cols);

/* find the next selectable item, and detect if it is on this page or not */
	size_t current = M->list_pos;
	size_t vis_step = 0, prev_vis = current;
	bool new_page = false;

	do {
		current = (current + 1) % M->list_sz;
		if (!(M->list[current].attributes & HIDDEN_ITEM)){
			vis_step++;

/* track the first visible on the next page */
			if (vis_step + M->list_row >= rows && !new_page){
				new_page = true;
				prev_vis = current;
			}
		}

		if (!(M->list[current].attributes & INACTIVE_ITEM))
			break;

/* end condition is wrap */
	} while (current != M->list_pos);

/* outside window, need to find the new list ofset as well, that is
 * why we need to track the previous visible */
	if (new_page){
		M->list_ofs = prev_vis;
	}
	else if (current < M->list_pos){
		if (prev_vis < rows)
			prev_vis = 0;
		M->list_ofs = prev_vis;
	}

	M->list_pos = current;

	redraw(T, M);
}

void arcan_tui_listwnd_dirty(struct tui_context* T)
{
	if (!validate(T))
		return;

	struct tui_cbcfg handlers;
	arcan_tui_update_handlers(T, NULL, &handlers, sizeof(struct tui_cbcfg));

	redraw(T, (struct listwnd_meta*) handlers.tag);
}

static bool u8(struct tui_context* T, const char* u8, size_t len, void* tag)
{
/* not necessarily terminated, so terminate */
	char cp[len+1];
	memcpy(cp, u8, len);
	cp[len] = '\0';

	struct listwnd_meta* M = tag;
	for (size_t i = 0; i < M->list_sz; i++){
		if (M->list[i].shortcut && strcmp(M->list[i].shortcut, cp) == 0){
			if (M->list[i].attributes & ~(INACTIVE_ITEM)){
				M->list_pos = i;
				redraw(T, M);
			}
			return true;
		}
	}

	return false;
}

static void key_input(struct tui_context* T, uint32_t keysym,
	uint8_t scancode, uint8_t mods, uint16_t subid, void* tag)
{
	struct listwnd_meta* M = tag;
/* might want to provide the label based approach to these as well, UP/DOWN
 * are at least already registered and handled / forwarded from the base tui */
	if (keysym == TUIK_DOWN){
		step_cursor_s(T, M);
	}
	else if (keysym == TUIK_UP){
		step_cursor_n(T, M);
	}
	else if (keysym == TUIK_PAGEDOWN){
		step_page_s(T, M);
	}
	else if (keysym == TUIK_PAGEUP){
		step_page_n(T, M);
	}
	else if (keysym == TUIK_RIGHT || keysym == TUIK_RETURN){
		select_current(T, M);
	}
	else if (keysym == TUIK_LEFT || keysym == TUIK_ESCAPE){
			M->entry_state = -1;
	}
	else
		;
}

bool arcan_tui_listwnd_status(struct tui_context* T, struct tui_list_entry** out)
{
	if (!validate(T))
		return false;

	struct tui_cbcfg handlers;
	arcan_tui_update_handlers(T, NULL, &handlers, sizeof(struct tui_cbcfg));
	struct listwnd_meta* M = handlers.tag;

	if (!M->entry_state)
		return false;

/* user requested cancellation */
	else if (M->entry_state == -1 && out)
		*out = NULL;
/* or selected a real item */
	else if (M->entry_state == 1 && out)
		*out = &M->list[M->entry_pos];

	M->entry_state = 0;
	return true;
}

void arcan_tui_listwnd_release(struct tui_context* T)
{
	if (!validate(T))
		return;

/* retrieve current handlers, get meta structure from the tag there and
 * use the handle- table in that structure to restore */
	struct tui_cbcfg handlers;
	arcan_tui_update_handlers(T, NULL, &handlers, sizeof(struct tui_cbcfg));
	struct listwnd_meta* meta = handlers.tag;

/* restore old flags */
	arcan_tui_reset_flags(T, ~0);
	arcan_tui_set_flags(T, meta->old_flags);

/* requery label through original handles */
	arcan_tui_reset_labels(T);

	arcan_tui_update_handlers(T,
		&meta->old_handlers, NULL, sizeof(struct tui_cbcfg));

/* LTO could possibly do something about this, but basically just safeguard
 * on a safeguard (UAF detection) for the bufferwnd_meta after freeing it */
	*meta = (struct listwnd_meta){
		.magic = 0xdeadbeef
	};

	free(meta);
}

static void resized(struct tui_context* T,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	struct listwnd_meta* M = t;
	redraw(T, M);
	if (M->old_handlers.resized){
		M->old_handlers.resized(T, neww, newh, col, row, M->old_handlers.tag);
	}
}

static void resize(struct tui_context* T,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	struct listwnd_meta* M = t;
	if (M->old_handlers.resize){
		M->old_handlers.resize(T, neww, newh, col, row, M->old_handlers.tag);
	}
}

static void tick(struct tui_context* T, void* t)
{
/* if current item is cropped, scroll it */
}

static void geohint(struct tui_context* T,
	float lat, float longit, float elev, const char* cnt, const char* lang, void* t)
{
	struct listwnd_meta* M = t;
	if (M->old_handlers.geohint){
		M->old_handlers.geohint(T, lat, longit, elev, cnt, lang, M->old_handlers.tag);
	}
}

static void mouse_motion(struct tui_context* T,
	bool relative, int mouse_x, int mouse_y, int modifiers, void* tag)
{
	struct listwnd_meta* M = tag;

/* uncommon but not impossible */
	if (relative){
		if (!mouse_y)
			return;
		if (mouse_y < 0){
			for (int i = mouse_y; i != 0; i++)
				step_cursor_n(T, M);
		}
		else{
			for (int i = mouse_y; i != 0; i--)
				step_cursor_s(T, M);
		}
		return;
	}

	for (size_t i = M->list_ofs, yp = 0; i < M->list_sz; i++){
		if (M->list[i].attributes & HIDDEN_ITEM)
			continue;

/* find matching position */
		if (yp == mouse_y){
/* and move selection if it has changed */
			if (M->list_pos != i){
				M->list_pos = i;
				redraw(T, M);
			}
			break;
		}
		yp++;
	}
}

static void mouse_button(struct tui_context* T,
	int last_x, int last_y, int button, bool active, int modifiers, void* tag)
{
	struct listwnd_meta* M = tag;
	if (!active)
		return;

/* mouse motion preceeds the button, so we can just trigger */
	if (button == TUIBTN_LEFT || button == TUIBTN_RIGHT){
		select_current(T, M);
	}
	else if (button == TUIBTN_MIDDLE){
		step_page_s(T, M);
	}
	else if (button == TUIBTN_WHEEL_UP){
		step_cursor_n(T, M);
	}
	else if (button == TUIBTN_WHEEL_DOWN){
		step_cursor_s(T, M);
	}
}

static void recolor(struct tui_context* T, void* t)
{
	struct listwnd_meta* M = t;
	redraw(T, M);
}

bool arcan_tui_listwnd_setup(
	struct tui_context* T, struct tui_list_entry* L, size_t n_entries)
{
	if (!T || !L || n_entries == 0)
		return false;

	struct listwnd_meta* meta = malloc(sizeof(struct listwnd_meta));
	if (!meta)
		return false;

	*meta = (struct listwnd_meta){
		.magic = LISTWND_MAGIC,
		.list_sz = n_entries,
		.list = L,
	};

/* save old flags and just set clean + ALTERNATE */
	meta->old_flags = arcan_tui_set_flags(T, 0);
	arcan_tui_reset_flags(T, ~0);
	arcan_tui_set_flags(T, TUI_ALTERNATE | TUI_HIDE_CURSOR);

	struct tui_cbcfg cbcfg = {
		.tag = meta,
		.resize = resize,
		.resized = resized,
		.recolor = recolor,
		.tick = tick,
		.geohint = geohint,
		.input_key = key_input,
		.input_mouse_motion = mouse_motion,
		.input_mouse_button = mouse_button,
		.input_utf8 = u8
	};

	/* BOX DRAWINGS LIGHT HORIZONTAL U+2500 */
	meta->line_ch = arcan_tui_hasglyph(T, 0x2500) ? 0x2500 : '-';
	/* MODIFIER LETTER RIGHT ARROWHEAD U+02c3 */
	meta->sub_ch = arcan_tui_hasglyph(T, 0x02c3) ? 0x02c3 : '>';
	/* CHECK MARK U+2713 */
	meta->check_ch = arcan_tui_hasglyph(T, 0x2713) ? 0x2713 : '*';

/* save old handlers and set new ones */
	arcan_tui_update_handlers(T,
		&cbcfg, &meta->old_handlers, sizeof(struct tui_cbcfg));

/* requery label through new handles (removes existing ones) */
	arcan_tui_reset_labels(T);
	redraw(T, meta);

	return true;
}

#ifdef EXAMPLE

static struct tui_list_entry test_easy[] = {
	{
		.label = "hi",
		.attributes = LIST_CHECKED,
		.tag = 0,
	},
	{
		.label = "there",
		.attributes = LIST_PASSIVE,
		.shortcut = "t",
		.tag = 1
	},
	{
		.attributes = LIST_SEPARATOR,
	},
	{
		.label = "lolita",
		.attributes = LIST_HAS_SUB,
		.shortcut = "l",
		.tag = 2
	}
};

int main(int argc, char** argv)
{
	struct tui_cbcfg cbcfg = {0};
	arcan_tui_conn* conn = arcan_tui_open_display("test", "");
	struct tui_settings cfg = arcan_tui_defaults(conn, NULL);
	cfg.cursor_period = 0;
	struct tui_context* tui = arcan_tui_setup(conn, &cfg, &cbcfg, sizeof(cbcfg));
	size_t test_cases = 2;
	size_t index = 0;

	if (argc > 1){
		index = strtoull(argv[1], NULL, 10);
	}

	if (index > test_cases - 1){
		fprintf(stderr, "Index (%zu) out of bounds\n", index);
		return EXIT_FAILURE;
	}

	switch(index){
	case 0:
		arcan_tui_listwnd_setup(tui, test_easy, COUNT_OF(test_easy));
	break;
	case 1:{
		struct tui_list_entry* ent = malloc(256 * sizeof(struct tui_list_entry));
		for (size_t i = 0; i < 256; i++){
			char buf[8];
			snprintf(buf, 8, "%zu %c", i, (char)('a' + i % 10));
			ent[i] = (struct tui_list_entry){
				.label = strdup((char*)buf),
				.tag = i
			};
			if (i % 5 == 0)
				ent[i].attributes = LIST_HIDE;
			if (i % 3 == 0 || i % 4 == 0)
				ent[i].attributes = LIST_PASSIVE;
		}
		arcan_tui_listwnd_setup(tui, ent, 256);
	}
	break;
	}

	while(1){
		struct tui_process_res res = arcan_tui_process(&tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
				break;
		}
		else
			break;

		struct tui_list_entry* ent;
		if (arcan_tui_listwnd_status(tui, &ent)){
			if (ent)
				printf("user picked: %s\n", ent->label);
			else
				printf("user cancelled\n");
			break;
		}
	}
	arcan_tui_destroy(tui, NULL);
	return 0;
}
#endif
