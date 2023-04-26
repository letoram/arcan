/*
 * simple skeleton for using TUI, useful as template to
 * only have to deal with a minimum of boilerplate
 */
#include <arcan_shmif.h>
#include <arcan_tui.h>
#include <arcan_tui_bufferwnd.h>
#include <inttypes.h>
#include <stdarg.h>
#include <errno.h>

struct data_buffer {
	ssize_t offset;
	uint32_t* buffer;
	size_t buffer_count;
};

#define TRACE_ENABLE
static inline void trace(const char* msg, ...)
{
#ifdef TRACE_ENABLE
	va_list args;
	va_start( args, msg );
		vfprintf(stderr,  msg, args );
	va_end( args);
	fprintf(stderr, "\n");
#endif
}

static void draw(struct tui_context* ctx, uint32_t* buffer, size_t lim)
{
	struct tui_screen_attr def_text = arcan_tui_defcattr(ctx, TUI_COL_TEXT);
	arcan_tui_erase_screen(ctx, false);
	size_t rows, cols;
	arcan_tui_dimensions(ctx, &rows, &cols);
	arcan_tui_move_to(ctx, 0, 0);

	for (size_t i = 0; i < lim && i < rows * cols; i++)
		arcan_tui_write(ctx, buffer[i], &def_text);
}

static bool query_label(struct tui_context* ctx,
	size_t ind, const char* country, const char* lang,
	struct tui_labelent* dstlbl, void* t)
{
	trace("query_label(%zu for %s:%s)\n",
		ind, country ? country : "unknown(country)",
		lang ? lang : "unknown(language)");

	return false;
}

static bool on_label(struct tui_context* c, const char* label, bool act, void* t)
{
	trace("label(%s)", label);
	return false;
}

static bool on_alabel(struct tui_context* c, const char* label,
		const int16_t* smpls, size_t n, bool rel, uint8_t datatype, void* t)
{
	trace("a-label(%s)", label);
	return false;
}

static void on_mouse(struct tui_context* c,
	bool relative, int x, int y, int modifiers, void* t)
{
	trace("mouse(%d:%d, mods:%d, rel: %d", x, y, modifiers, (int) relative);

	size_t rows, cols;
	arcan_tui_dimensions(c, &rows, &cols);

	struct data_buffer* T = t;
	size_t ofs = T->offset + (y * cols) + x;
	if (ofs < T->buffer_count){
		uint8_t buf[4];
		arcan_tui_move_to(c, x, y);
		arcan_tui_ucs4utf8(T->buffer[ofs], (char*) buf);
		printf("@ (%zu) UCS4: %"PRIx32", utf-8: %02"PRIx8" %02"PRIx8
			" %02"PRIx8" %02"PRIx8"\n",
			ofs, T->buffer[ofs], buf[0], buf[1], buf[2], buf[3]);
	}
}

static void on_key(struct tui_context* c, uint32_t keysym,
	uint8_t scancode, uint16_t mods, uint16_t subid, void* t)
{
	trace("unknown_key(%"PRIu32",%"PRIu8",%"PRIu16")", keysym, scancode, subid);
	struct data_buffer* T = t;
	size_t rows, cols;
	arcan_tui_dimensions(c, &rows, &cols);

	if (keysym == TUIK_UP){
		T->offset = T->offset - cols;
	}
	else if (keysym == TUIK_DOWN){
		T->offset = T->offset + cols;
	}
	else if (keysym == TUIK_LEFT){
		T->offset = T->offset - 1;
	}
	else if (keysym == TUIK_RIGHT){
		T->offset = T->offset + 1;
	}

	if (T->offset < 0)
		T->offset = 0;

	if (T->offset >= T->buffer_count)
		T->offset = T->buffer_count - 1;

	printf("offset %zd - %zu\n", T->offset, T->buffer_count);

	draw(c, &T->buffer[T->offset], T->buffer_count - T->offset);
}

static bool on_u8(struct tui_context* c, const char* u8, size_t len, void* t)
{
	return false;
}

static void on_misc(struct tui_context* c, const arcan_ioevent* ev, void* t)
{
	trace("on_ioevent()");
}

static void on_state(struct tui_context* c, bool input, int fd, void* t)
{
	trace("on-state(in:%d)", (int)input);
}

static void on_bchunk(struct tui_context* c,
	bool input, uint64_t size, int fd, const char* id, void* t)
{
	close(fd);
	trace("on_bchunk(%"PRIu64", in:%d)", size, (int)input);
}

static void on_vpaste(struct tui_context* c,
		shmif_pixel* vidp, size_t w, size_t h, size_t stride, void* t)
{
	trace("on_vpaste(%zu, %zu str %zu)", w, h, stride);
}

static void on_apaste(struct tui_context* c,
	shmif_asample* audp, size_t n_samples, size_t frequency, size_t nch, void* t)
{
	trace("on_apaste(%zu @ %zu:%zu)", n_samples, frequency, nch);
}

static void on_tick(struct tui_context* c, void* t)
{
/* ignore this, rather noise:	trace("[tick]"); */
}

static void on_utf8_paste(struct tui_context* c,
	const uint8_t* str, size_t len, bool cont, void* t)
{
	trace("utf8-paste(%s):%d", str, (int) cont);
}

static void on_resize(struct tui_context* c,
	size_t neww, size_t newh, size_t col, size_t row, void* t)
{
	trace("resize(%zu(%zu),%zu(%zu))", neww, col, newh, row);
	struct data_buffer* T = t;
	draw(c, &T->buffer[T->offset], T->buffer_count - T->offset);
}

int main(int argc, char** argv)
{
	arcan_tui_conn* conn = arcan_tui_open_display("tui-test", "");

	struct data_buffer buf = {
		.buffer = malloc(64 * 1024 * 4),
		.buffer_count = 0,
		.offset = 0
	};

/*
 * only the ones that are relevant needs to be filled
 */
	struct tui_cbcfg cbcfg = {
		.query_label = query_label,
		.input_label = on_label,
		.input_alabel = on_alabel,
		.input_mouse_motion = on_mouse,
		.input_utf8 = on_u8,
		.input_key = on_key,
		.input_misc = on_misc,
		.state = on_state,
		.bchunk = on_bchunk,
		.vpaste = on_vpaste,
		.apaste = on_apaste,
		.tick = on_tick,
		.utf8 = on_utf8_paste,
		.resized = on_resize,
		.tag = &buf
	};

/* even though we handle over management of con to TUI, we can
 * still get access to its internal reference at will */
	struct tui_context* tui = arcan_tui_setup(conn, NULL, &cbcfg, sizeof(cbcfg));
	arcan_tui_set_flags(tui, TUI_ALTERNATE | TUI_AUTO_WRAP | TUI_MOUSE);

	if (!tui){
		fprintf(stderr, "failed to setup TUI connection\n");
		return EXIT_FAILURE;
	}

/* ofc. not correct */
	for (size_t i = 0; i < 65536; i++){
		if (arcan_tui_hasglyph(tui, i)){
			buf.buffer[buf.buffer_count++] = i;
		}
	}

	printf("%zu glyphs found\n", buf.buffer_count);

	while (1){
		struct tui_process_res res = arcan_tui_process(&tui, 1, NULL, 0, -1);
		if (res.errc == TUI_ERRC_OK){
			if (-1 == arcan_tui_refresh(tui) && errno == EINVAL)
				break;

			if (res.ok)
				fgetc(stdin);
		}
		else
			break;
	}

	arcan_tui_destroy(tui, NULL);

	return EXIT_SUCCESS;
}
