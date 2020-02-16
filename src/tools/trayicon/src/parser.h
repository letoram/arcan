#ifndef HAVE_PARSER
#define HAVE_PARSER

/* used in the stdin text mode */
struct texticon_state {
	struct tui_screen_attr attr;
	int align; /* -1: left, 0: center, 1: right */
	char buttons[5][32]; /* click output */
	bool in_button; /* tag the cell with the button index */
};

/* Alternate tray icon mode where we simply read from stdin and render as much
 * as we can into a tui context. Intended to be used with some input script
 * that monitors some source and expose as updates into a button. */
struct parser_data {
	struct tui_cell* buffer;
	size_t buffer_count;
	size_t buffer_used;
	struct texticon_state icon;
};

void parse_lemon(struct tui_context*, struct parser_data*, char* inbuf);

#endif
