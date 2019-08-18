static bool draw_box_px(
shmif_pixel* px, size_t pitch, size_t max_w, size_t max_h,
int x, int y, size_t w, size_t h, shmif_pixel col)
{
	if (x >= max_w || y >= max_h)
		return false;

	if (x < 0){
		w += x;
		x = 0;
	}

	if (y < 0){
		h += y;
		y = 0;
	}

	if (w < 0 || h < 0)
		return false;

	int ux = x + w > max_w ? max_w : x + w;
	int uy = y + h > max_h ? max_h : y + h;

	for (int cy = y; cy < uy; cy++)
		for (int cx = x; cx < ux; cx++)
			px[ cy * pitch + cx ] = col;

	return true;
}

static bool draw_box(struct arcan_shmif_cont* c,
	int x, int y, int w, int h, shmif_pixel col)
{
	return draw_box_px(c->vidp, c->pitch, c->w, c->h, x, y, w, h, col);
}
