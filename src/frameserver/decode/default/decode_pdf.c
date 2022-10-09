#include <arcan_shmif.h>
#include <arcan_tuisym.h>
#include <math.h>

#include "decode.h"
#include "mupdf/fitz.h"
#include "util/labelhint.h"

#define MIN(a, b)	((a) < (b) ? (a) : (b))

static void rebuild_pixmap();

static struct {
/* action schedule triggers */
	bool hinted;
	bool dirty;
	bool locked;
	bool rezoom;

/* context tracking */
	fz_context* ctx;
	fz_document* doc;
	fz_pixmap* pmap;
	fz_device *dev;
	fz_page *page;
	struct arcan_shmif_cont con;

/* input states */
	int32_t modifiers;
	uint8_t mstate[ASHMIF_MSTATE_SZ];

/* render state modifiers */
	struct arcan_shmif_initial dpy;
	size_t hw, hh;
	bool annotations;
	bool in_drag;
	bool panned;
	float scale;
	int page_no;
	int dx, dy;

} apdf = {
	.scale = 1.0,
	.annotations = true,
	.dirty = true,
};

static bool auto_size(void* tag);
static void calculate_zoom_factor();

static fz_matrix get_transform(bool translate)
{
	fz_matrix ctm = fz_rotate(0);
	float fact = apdf.scale + (apdf.dpy.density * 2.54 / 72.0);
	if (translate)
		ctm = fz_pre_translate(ctm, apdf.dx, apdf.dy);
	ctm = fz_pre_scale(ctm, fact, fact);

	return ctm;
}

static void calculate_zoom_factor()
{
	fz_rect rect = fz_bound_page(apdf.ctx, apdf.page);
	float wofs = (apdf.dpy.density * 2.54) / 72.0;

	float imgw = (rect.x1 - rect.x0) * wofs;
	float imgh = (rect.y1 - rect.y0) * wofs;
	float wnd_ar = apdf.con.w / apdf.con.h;
	float doc_ar = imgw / imgh;

	if (doc_ar > wnd_ar){
		apdf.scale = (float) apdf.con.w / imgw;
	}
	else {
		apdf.scale = (float) apdf.con.h / imgh;
	}
}

static void render()
{
	rebuild_pixmap();

	bool repack = true;
	fz_matrix transform = get_transform(true);

/* pad? */
	fz_rect rect = fz_bound_page(apdf.ctx, apdf.page);
	rect = fz_transform_rect(rect, transform);

	shmif_pixel bg_pixel = SHMIF_RGBA(0x40, 0x40, 0x40, 0xff);

/* clear to 'background' first */
	if (rect.y0 > 0.0){
		for (size_t y = 0; y < apdf.con.h && y < rect.y0; y++){
			shmif_pixel* out = &apdf.con.vidp[y * apdf.con.pitch];
			for (size_t x = 0; x < apdf.con.w; x++)
				out[x] = bg_pixel;
		}
	}

	if (rect.y1 < apdf.con.h){
		for (size_t y = rect.y1 + 1; y < apdf.con.h; y++){
			shmif_pixel* out = &apdf.con.vidp[y * apdf.con.pitch];
			for (size_t x = 0; x < apdf.con.w; x++)
				out[x] = bg_pixel;
		}
	}

	for (size_t y = 0; y < apdf.con.h; y++){
		shmif_pixel* out = &apdf.con.vidp[y * apdf.con.pitch];
		for (size_t x = 0; x < rect.x0 && x < apdf.con.w; x++)
			out[x] = bg_pixel;
		for (size_t x = rect.x1 < 0 ? 0 : rect.x1; x < apdf.con.w; x++)
			out[x] = bg_pixel;
	}

/* then draw in the paper */
	shmif_pixel fg_pixel = SHMIF_RGBA(0xff, 0xff, 0xff, 0xff);
	for (size_t y = rect.y0 > 0 ? rect.y0 : 0; y < apdf.con.h && y <= rect.y1; y++){
		shmif_pixel* out = &apdf.con.vidp[y * apdf.con.pitch];
		for (size_t x = rect.x0 > 0 ? rect.x0 : 0; x < apdf.con.w && x <= rect.x1; x++){
			out[x] = fg_pixel;
		}
	}

	fz_try(apdf.ctx)
		fz_run_page_contents(apdf.ctx, apdf.page, apdf.dev, transform, NULL);

/* option here: toggle annotations on / off - possibly also as an overlay
 * window so the WM gets to split out */

	fz_catch(apdf.ctx){
		fprintf(stderr, "couldn't run page: %s\n", fz_caught_message(apdf.ctx));
		repack = false;
	}

	if (!repack)
		return;

	if (apdf.annotations){
		fz_try(apdf.ctx)
			fz_run_page_annots(apdf.ctx, apdf.page, apdf.dev, transform, NULL);
		fz_catch(apdf.ctx){
			fprintf(stderr, "couldn't run annotations: %s\n", fz_caught_message(apdf.ctx));
		}
	}

	arcan_shmif_signal(&apdf.con, SHMIF_SIGVID | SHMIF_SIGBLK_NONE);
	apdf.locked = true;
}

static void set_page(int no)
{
	if (apdf.page)
		apdf.page = (fz_drop_page(apdf.ctx, apdf.page), NULL);

	int np = fz_count_pages(apdf.ctx, apdf.doc);

/* don't permit negative wraparound (expensive and rarely desired) */
	if (no < 0 || !np)
		no = 0;
	else if (no >= np)
		no = np - 1;

	fz_try(apdf.ctx)
		apdf.page = fz_load_page(apdf.ctx, apdf.doc, no);
	fz_catch(apdf.ctx){
		fprintf(stderr, "couldn't load page %d: %s\n", no, fz_caught_message(apdf.ctx));
		return;
	}

	apdf.page_no = no;
	apdf.dirty = true;
}

static void rebuild_pixmap()
{
	apdf.dirty = true;
	if (apdf.pmap){
		apdf.pmap = (fz_drop_pixmap(apdf.ctx, apdf.pmap), NULL);
	}

/* two different modes here, one is where we switch page size to fit when stepping
 * (assuming it has changed from last time) - or we pan. There is also:
 * fz_is_document_reflowable -> fz_layout_document(ctx, doc, w, h, em_font_sz) */

	size_t w = apdf.con.w;
	size_t h = apdf.con.h;

	if (apdf.hinted){
		w = apdf.hw;
		h = apdf.hh;
	}

/* prevent the thing from starting with a bad size / resolution */
	if (w < 32 && h < 32){
		auto_size(NULL);
		apdf.rezoom = true;
	}

	arcan_shmif_resize_ext(&apdf.con, w, h, (struct shmif_resize_ext){.vbuf_cnt = 2});
	if (apdf.rezoom){
		calculate_zoom_factor();
		apdf.rezoom = false;
	}

/* Now we have the 'negotiated' size - that might not match the actual size of
 * the page though so we might want to pan / offset. Doing that requires we
 * offset the vidb accordingly (and reduce w / h). */

/* For big-endian it might be better to probe shmif_pixel through the packing
 * macro and switch between bgr and rgb there, the [1] sets n=4 for alpha ch. */
	fz_colorspace* cspace = fz_device_bgr(apdf.ctx);
	fz_try(apdf.ctx)
		apdf.pmap = fz_new_pixmap_with_data(apdf.ctx, cspace,
			apdf.con.w, apdf.con.h, NULL, 1, apdf.con.stride, apdf.con.vidb);

	fz_catch(apdf.ctx){
		fprintf(stderr, "pixmap creation failed: %s\n", fz_caught_message(apdf.ctx));
	}

	apdf.pmap->flags &= ~1; /* stop it from free:ing our buffer */

/* change the >density< of the pixmap from the assumed default 72, though
 * can't find a control for also setting the subchannel layout for hinting */
	float dpi = apdf.dpy.density * 2.54;
	fz_set_pixmap_resolution(apdf.ctx, apdf.pmap, dpi, dpi);

	fz_try(apdf.ctx)
		apdf.dev = fz_new_draw_device(apdf.ctx, fz_identity, apdf.pmap);

	fz_catch(apdf.ctx){
		fprintf(stderr, "device creation failed: %s\n", fz_caught_message(apdf.ctx));
	}

/* another interesting bit here is that we could add our own font hooks and map
 * that to the fonthints that we receive over the connection */
}

static bool zoom_in(void* tag)
{
	apdf.scale += 0.1;
	apdf.dirty = true;

	return true;
}

static bool page_prev(void* tag)
{
	set_page(apdf.page_no - 1);
	apdf.dx = 0;
	apdf.dy = 0;
	return true;
}

static bool page_next(void* tag)
{
	set_page(apdf.page_no + 1);
	apdf.dx = 0;
	apdf.dy = 0;
	return true;
}

static bool line_up(void* tag)
{
/* better metrics calculations are needed here - the number of pixels depends
 * on the scale over the current density, and font size */
	apdf.dirty = true;
	apdf.dy -= apdf.con.h * 0.1;
	return true;
}

static bool line_down(void* tag)
{
	apdf.dy += apdf.con.h * 0.1;
	apdf.dirty = true;
	return true;
}

static bool zoom_out(void* tag)
{
	apdf.scale -= 0.1;

	if (apdf.scale < 0.1)
		apdf.scale = 0.1;

	apdf.dirty = true;
	return true;
}

static bool zoom_reset(void* tag)
{
	apdf.scale = 1.0;
	apdf.dirty = true;
	return true;
}

static bool zoom_auto(void* tag)
{
	calculate_zoom_factor();
	apdf.dirty = true;
	return true;
}

static bool auto_size(void* tag)
{
	fz_rect rect = fz_bound_page(apdf.ctx, apdf.page);
	float wofs = (apdf.dpy.density * 2.54) / 72.0 * apdf.scale;
	apdf.hh = ceilf(rect.x1 * wofs);
	apdf.hw = ceilf(rect.y1 * wofs);
	apdf.hinted = true;
	return true;
}

static struct labelent ihandlers[] =
{
	{
		.lbl = "ZOOM_IN",
		.descr = "Increment zoom level by 10%",
/*	.vsym = right_arrow */
		.ptr = zoom_in,
		.initial = TUIK_EQUALS,
	},
	{
		.lbl = "ZOOM_OUT",
		.descr = "Decrement zoom level by 10%",
		.ptr = zoom_out,
		.initial = TUIK_MINUS,
	},
	{
		.lbl = "ZOOM_RESET",
		.descr = "Reset magnification",
		.ptr = zoom_reset,
		.initial = TUIK_R,
	},
	{
		.lbl = "ZOOM_AUTO",
		.descr = "Toggle auto-zoom to fit window on/off",
		.ptr = zoom_auto,
		.initial = TUIK_F1,
	},
	{
		.lbl = "AUTO_SIZE",
		.descr = "Resize window to fit page content at current zoom",
		.ptr = auto_size,
		.initial = TUIK_F2,
	},
	{
		.lbl = "REFLOW",
		.descr = "Reflow page layout to fit current window",
		.ptr = NULL, /* set dynamically based on if document supports or not */
		.initial = TUIK_F3
	},
	{
		.lbl = "LINE_BACK",
		.descr = "Scroll page backwards",
		.ptr = line_up,
		.initial = TUIK_UP
	},
	{
		.lbl = "LINE_FWD",
		.descr = "Scroll page forward",
		.ptr = line_down,
		.initial = TUIK_DOWN
	},
	{
		.lbl = "NEXT_PAGE",
		.descr = "Step to the next page",
		.ptr = page_next,
		.initial = TUIK_RIGHT
	},
	{
		.lbl = "PREV_PAGE",
		.descr = "Step to the previous page",
		.ptr = page_prev,
		.initial = TUIK_LEFT
	},
/*
 * we have:
 * fz_make_bookmark (also apply on changing em size, then count pages, find new location
 */
	{.lbl = NULL},
};

static bool open_document(FILE* fpek, char* magic)
{
	fz_stream* stream = fz_open_file_ptr_no_close(apdf.ctx, fpek);

	fz_try(apdf.ctx) {
		apdf.doc = fz_open_document_with_stream(apdf.ctx, magic ? magic : "pdf", stream);
	}
	fz_catch(apdf.ctx) {
		fprintf(stdout, "Couldn't parse/read file\n");
		fz_drop_context(apdf.ctx);
		return EXIT_FAILURE;
	}

	return true;
}

static void process_input(arcan_event* inev)
{
	arcan_ioevent* ev = &inev->io;

	if (ev->kind == EVENT_IO_BUTTON){
/* special case, mouse */
		if (ev->devkind == EVENT_IDEVKIND_MOUSE){
			int delta = 0;

			switch(ev->subid){
			case MBTN_LEFT_IND:
				apdf.in_drag = ev->input.digital.active;
/* on_release also check for 'click' tag or no-delta */
			break;
			case MBTN_RIGHT_IND:
			break;
			case MBTN_MIDDLE_IND:
			break;
			case MBTN_WHEEL_UP_IND:
				if (apdf.modifiers){
					zoom_in(NULL);
				}
				else if (ev->input.digital.active)
					page_prev(NULL);
			break;
			case MBTN_WHEEL_DOWN_IND:
				if (apdf.modifiers){
					zoom_out(NULL);
				}
				else if (ev->input.digital.active)
					page_next(NULL);
			break;
			}
			return;
		}

/* track modifiers for mod+mouse */
		if (ev->devkind == EVENT_IDEVKIND_KEYBOARD &&
			ev->datatype == EVENT_IDATATYPE_TRANSLATED){
			int sym = ev->input.translated.keysym;
			if (sym == TUIK_LCTRL || sym == TUIK_RCTRL)
				apdf.modifiers = ev->input.translated.active;
		}

/* labelhint helper will check for tagged and apply to any input event */
		if (labelhint_consume(ev, NULL))
			return;

/* some appls doesn't provide tagging (booh) so the polite fallback is
 * to provide some kind of keyboard defaults for stepping, ... */
		if (
			ev->devkind == EVENT_IDEVKIND_KEYBOARD &&
			ev->datatype == EVENT_IDATATYPE_TRANSLATED)
		{
			if (!ev->input.translated.active)
				return;
			switch (ev->input.translated.keysym){
			case TUIK_UP:
			case TUIK_K:
				line_up(NULL);
			break;
			case TUIK_DOWN:
			case TUIK_J:
				line_down(NULL);
			break;
			case TUIK_RIGHT:
			case TUIK_L:
				page_next(NULL);
			break;
			case TUIK_LEFT:
			case TUIK_H:
				page_prev(NULL);
			break;
			default:
				return;
			}
		}
	}

	if (ev->devkind == EVENT_IDEVKIND_MOUSE &&
		ev->datatype == EVENT_IDATATYPE_ANALOG){
		int dx, dy;

/* update the panning region if it doesn't actually fit screen */
		if (arcan_shmif_mousestate(&apdf.con, apdf.mstate, inev, &dx, &dy)){
			if (apdf.in_drag){
				apdf.dx += dx;
				apdf.dy += dy;
				apdf.dirty = true;
			}
		}
	}

/*
 * missing:
 * 	click to resolve_link and jump
 */

	return;
}

static void run_event(struct arcan_event* ev)
{
	if (ev->category == EVENT_IO)
		return process_input(ev);

/* an interesting possiblity when this is added to afsrv_decode is to have an
 * AGP backend that translates into PDF -> renders through decode and then just
 * maps the buffer to the KMS plane */

/* tons of PDF features to map here, selection of text, stepping blocks,
 * converting to accessibility segment, converting to clipboard segment,
 * outline, password authentication, form, bookmarks, links, annotations,
 * forwarding the content appropriate side or force scaling, decryption key,
 * ...
 *
 * for clipboard there is the option to create a text output and draw to it,
 * but for selections there is mupdf_page_extrace_text and fz_copy_selection
 * from(ctx, text, pa, pb)
 *
 * presentation details and CLOCK for autostep (fz_page_presentation)
 *
 * for chapters we need:
 *  fz_next_page to step -> fz_location then resolve
 *  fz_page_number_from_location
 *
 * set ident with title, ch, page
 *
 * then BCHUNKs we can also use extension (json, html, xhtml, text) though
 * this behaves more like ENCODE ..
 *
 * open questions:
 *  separations, overprint, output intents, widgets, forms, search?
 *
 * allow shmif_ext? we basically save the upload and minor fillrate
 *
 * progressive loading (fz_open_file_progressive, then provide feed
 * function to block/ready more. Nice when we get BCHUNK with stream
 */

	if (ev->category != EVENT_TARGET)
		return;

	if (ev->tgt.kind == TARGET_COMMAND_STEPFRAME){
		apdf.locked = false;
		return;
	}
	if (ev->tgt.kind == TARGET_COMMAND_RESET){
		apdf.locked = false;
		apdf.dirty = true;
		apdf.modifiers = 0;
	}

	if (ev->tgt.kind == TARGET_COMMAND_DISPLAYHINT){
		apdf.hinted = false;
		if (ev->tgt.ioevs[0].iv && ev->tgt.ioevs[1].iv){
			apdf.hw = ev->tgt.ioevs[0].iv;
			apdf.hh = ev->tgt.ioevs[1].iv;
			apdf.hinted = true;
		}
		if (ev->tgt.ioevs[4].fv && ev->tgt.ioevs[4].fv != apdf.dpy.density){
			apdf.dpy.density = ev->tgt.ioevs[4].fv;
		}
		apdf.dirty = true;
		return;
	}

	if (ev->tgt.kind == TARGET_COMMAND_SEEKCONTENT){
/* figure out page and possibly bbox offset if we don't fit */
	}
	else if (ev->tgt.kind == TARGET_COMMAND_BCHUNK_IN){
/* if seekable, just wrap dup:ed FD in file, otherwise read into buffer and
 * wrap memory buffer as FILE. Need to announce:
 * .html, .pdf, .xps, .epub, .cbz. */
	}

/* for STATE_IN/OUT we need some magic signature, bake in the contents of the
 * document itself, grab bookmarks and annotations */

/* fz_count_pages -> get range for contenthint */
}

int decode_pdf(struct arcan_shmif_cont* C, struct arg_arr* args)
{
	FILE* fpek = NULL;
	char* idstr = NULL;
	const char* val;

	if (arg_lookup(args, "file", 0, &val)){
		if (!val || strlen(val) == 0){
			return show_use(C, "file=arg [arg] missing");
		}
		fpek = fopen(val, "r");
		if (fpek)
			idstr = strdup(val);
	}
	else {
		int fd = wait_for_file(C, "pdf", &idstr);
		if (-1 == fd)
			return EXIT_SUCCESS;
		fpek = fdopen(fd, "r");
	}

	if (!fpek){
		return show_use(C, "file=arg [arg] couldn't be opened");
	}

	apdf.ctx = fz_new_context(NULL, NULL, FZ_STORE_DEFAULT);
	fz_register_document_handlers(apdf.ctx);

	if (!open_document(fpek, idstr))
		return EXIT_FAILURE;

	apdf.con = *C;
	labelhint_table(ihandlers);
	labelhint_announce(&apdf.con);

/* keep this around so we can just re-use for DISPLAYHINT changes */
	struct arcan_shmif_initial* init;
	arcan_shmif_initial(&apdf.con, &init);
	apdf.dpy = *init;
	apdf.hw = apdf.con.w;
	apdf.hh = apdf.con.h;
	apdf.con.hints = SHMIF_RHINT_VSIGNAL_EV;
	arcan_shmif_mousestate_setup(&apdf.con, true, apdf.mstate);

	set_page(0);
	render();

	struct arcan_event ev;

/* normal double-dispatch structure to deal with storms without unnecessary refreshes */
	while (arcan_shmif_wait(&apdf.con, &ev)){
		run_event(&ev);
		while (arcan_shmif_poll(&apdf.con, &ev) > 0)
			run_event(&ev);

		if (apdf.dirty && !apdf.locked){
			render();
			apdf.dirty = false;
		}
	}

	fz_drop_document(apdf.ctx, apdf.doc);
	fz_drop_context(apdf.ctx);
	arcan_shmif_drop(&apdf.con);
	return EXIT_SUCCESS;
}
