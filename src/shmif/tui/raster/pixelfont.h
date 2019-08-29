struct tui_pixelfont;

/*
 * Load / initialize built-in pixel fonts,
 * with the number of font-slots that can be appended.
 */
struct tui_pixelfont* tui_pixelfont_open(size_t limit);

/*
 * Free the pixelfont container
 */
void tui_pixelfont_close(struct tui_pixelfont* ctx);

/*
 * Query if there is a matching symbol for the specified code-point
 * or not in the currently used font-set/font-context
 */
bool tui_pixelfont_hascp(struct tui_pixelfont* ctx, uint32_t cp);

/*
 * Switch the active font-size to the desired 'px', will align to whichever
 * loadded font is the closest. The final cell dimensions will be returned
 * in [w, h].
 */
void tui_pixelfont_setsz(
	struct tui_pixelfont* ctx, size_t px, size_t* w, size_t* h);

/*
 * Load/Extend the font-set with a font (PSF2 supported) in [buf, buf_sz]
 * for the pixel-size slot marked as [px_sz]. Set merge if it should
 * extend the slot with new glyphs, otherwise existing ones will be released.
 */
bool tui_pixelfont_load(struct tui_pixelfont* ctx,
	uint8_t* buf, size_t buf_sz, size_t px_sz, bool merge);

/*
 * Return true if the buffer contains a valid font or not
 */
bool tui_pixelfont_valid(uint8_t* buf, size_t buf_sz);

void tui_pixelfont_draw(
	struct tui_pixelfont* ctx, shmif_pixel* c, size_t vidp,
	uint32_t cp, int x, int y, shmif_pixel fg, shmif_pixel bg,
	int maxx, int maxy, bool bgign);
