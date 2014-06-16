


struct slice
{
	int y;
	unsigned long *colors;
	unsigned char *bitmap;
};

struct dblbuf
{
	struct slice *slices;
	unsigned cs, ch;

	int active, repaint;
	unsigned curs_x;
	unsigned curs_y;

	unsigned char *vidmem;
	unsigned row_stride;
	unsigned line_stride;
	unsigned bytes_per_pixel;
};

#define SLICE_BUF_SIZE(w, h, cs, ch) \
	( (h)*(sizeof(struct slice) + (w)*(2*sizeof(long) + (cs)*(ch))) )

struct slice *dblbuf_setup_buf(int, int, int, int, unsigned char *);

