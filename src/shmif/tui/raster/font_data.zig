// Embedded PSF bitmap font data for TUI pixelfont rendering.
// Fonts: Terminus (Lat15) in 3 sizes, from /usr/share/consolefonts.

const font_12x6 = @embedFile("fonts/Lat15-Terminus12x6.psf");
const font_22x11 = @embedFile("fonts/Lat15-Terminus22x11.psf");
const font_32x16 = @embedFile("fonts/Lat15-Terminus32x16.psf");

export const Lat15_Terminus12x6_psf: [*]const u8 = font_12x6.ptr;
export const Lat15_Terminus12x6_psf_len: usize = font_12x6.len;
export const Lat15_Terminus22x11_psf: [*]const u8 = font_22x11.ptr;
export const Lat15_Terminus22x11_psf_len: usize = font_22x11.len;
export const Lat15_Terminus32x16_psf: [*]const u8 = font_32x16.ptr;
export const Lat15_Terminus32x16_psf_len: usize = font_32x16.len;
