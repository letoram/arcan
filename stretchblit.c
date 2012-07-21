/*  
 * Stripped down version of SDL rotozoomer, only RGBA<->RGBA upscale
 *
 */

/*
Copyright (C) 2001-2011  Andreas Schiffler

This software is provided 'as-is', without any express or implied
warranty. In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

   1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.

   2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.

   3. This notice may not be removed or altered from any source
   distribution.

Andreas Schiffler -- aschiffler at ferzkopp dot net

*/

typedef struct tColorRGBA {
	Uint8 r;
	Uint8 g;
	Uint8 b;
	Uint8 a;
} tColorRGBA;

typedef struct tColorY {
	Uint8 y;
} tColorY;

int stretchblit(SDL_Surface* src, uint32_t* dst, int dstw, int dsth, int dstpitch, int flipy)
{
	int x, y, sx, sy, ssx, ssy, *sax, *say, *csax, *csay, *salast;
	int csx, csy, ex, ey, cx, cy, sstep, sstepx, sstepy;

	tColorRGBA *c00, *c01, *c10, *c11;
	tColorRGBA *sp, *csp, *dp;
	
	int spixelgap, spixelw, spixelh, dgap, t1, t2;

	if ((sax = (int *) malloc((dstw + 1) * sizeof(Uint32))) == NULL) {
		return (-1);
	}
	if ((say = (int *) malloc((dsth + 1) * sizeof(Uint32))) == NULL) {
		free(sax);
		return (-1);
	}

	spixelw = (src->w - 1);
	spixelh = (src->h - 1);
	sx = (int) (65536.0 * (float) spixelw / (float) (dstw - 1));
	sy = (int) (65536.0 * (float) spixelh / (float) (dsth - 1));
	
	/* Maximum scaled source size */
	ssx = (src->w << 16) - 1;
	ssy = (src->h << 16) - 1;
	
	/* Precalculate horizontal row increments */
	csx = 0;
	csax = sax;
	for (x = 0; x <= dstw; x++) {
		*csax = csx;
		csax++;
		csx += sx;
		
		/* Guard from overflows */
		if (csx > ssx) { 
			csx = ssx; 
		}
	}
	 
	/* Precalculate vertical row increments */
	csy = 0;
	csay = say;
	for (y = 0; y <= dsth; y++) {
		*csay = csy;
		csay++;
		csy += sy;
		
		/* Guard from overflows */
		if (csy > ssy) {
			csy = ssy;
		}
	}

	sp = (tColorRGBA *) src->pixels;
	dp = (tColorRGBA *) dst;
	dgap = dstpitch - dstw * 4;
	spixelgap = src->pitch/4;

	if (flipy) sp += (spixelgap * spixelh);

	csay = say;
	for (y = 0; y < dsth; y++) {
		csp = sp;
		csax = sax;
		for (x = 0; x < dstw; x++) {
			ex = (*csax & 0xffff);
			ey = (*csay & 0xffff);
			cx = (*csax >> 16);
			cy = (*csay >> 16);
			sstepx = cx < spixelw;
			sstepy = cy < spixelh;
			c00 = sp;
			c01 = sp;
			c10 = sp;
		
			if (sstepy) {
				if (flipy) {
				c10 -= spixelgap;
 			} else {
				c10 += spixelgap;
 				}
 			}
			
			c11 = c10;
			if (sstepx) {
				c01++;
				c11++;
			 }

			t1 = ((((c01->r - c00->r) * ex) >> 16) + c00->r) & 0xff;
			t2 = ((((c11->r - c10->r) * ex) >> 16) + c10->r) & 0xff;
			dp->r = (((t2 - t1) * ey) >> 16) + t1;
			t1 = ((((c01->g - c00->g) * ex) >> 16) + c00->g) & 0xff;
			t2 = ((((c11->g - c10->g) * ex) >> 16) + c10->g) & 0xff;
			dp->g = (((t2 - t1) * ey) >> 16) + t1;
			t1 = ((((c01->b - c00->b) * ex) >> 16) + c00->b) & 0xff;
			t2 = ((((c11->b - c10->b) * ex) >> 16) + c10->b) & 0xff;
			dp->b = (((t2 - t1) * ey) >> 16) + t1;
			t1 = ((((c01->a - c00->a) * ex) >> 16) + c00->a) & 0xff;
			t2 = ((((c11->a - c10->a) * ex) >> 16) + c10->a) & 0xff;
			dp->a = (((t2 - t1) * ey) >> 16) + t1;				

			salast = csax;
			csax++;
			sstep = (*csax >> 16) - (*salast >> 16);
			sp += sstep;
				
			dp++;
		}
		
		salast = csay;
		csay++;
		sstep = (*csay >> 16) - (*salast >> 16);
		sstep *= spixelgap;
		if (flipy) { 
			 sp = csp - sstep;
		} else {
			sp = csp + sstep;
		}

		dp = (tColorRGBA *) ((Uint8 *) dp + dgap);
	}

	free(sax);
	free(say);

	return (0);
}