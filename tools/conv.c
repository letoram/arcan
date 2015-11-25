#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>

typedef uint16_t u_short;
typedef uint16_t ushort;
#include "keymap.h"

static size_t ucs2_to_utf8(int ucs2, uint8_t utf8[])
{
	if (ucs2 < 0x80){
		utf8[0] = ucs2;
		return 1;
	}

	if (ucs2 >= 0x80 && ucs2 < 0x800){
		utf8[0] = (ucs2 >> 6) | 0xc0;
		utf8[1] = (ucs2 & 0x3f) | 0x80;
		return 2;
	}

	if (ucs2 >= 0x800 && ucs2 < 0xdfff){
		if (ucs2 >= 0xd800 && ucs2 <= 0xdfff){
			return 0;
		}

		utf8[0] = ((ucs2 >> 12)) | 0xe0;
		utf8[1] = ((ucs2 >> 6) & 0x3f) | 0x80;
		utf8[2] = (ucs2 & 0x3f) | 0x80;
		return 3;
	}

	if (ucs2 >= 0x1000 && ucs2 < 0x10ffff){
		utf8[0] = (ucs2 >> 18) | 0xf0;
		utf8[1] = ((ucs2 >> 12)) | 0xe0;
		utf8[2] = ((ucs2 >> 6) & 0x3f) | 0x80;
		utf8[3] = (ucs2 & 0x3f) | 0x80;
		return 4;
	}

	return 0;
}

/* just use keymap.h and emit arcan/symtable.lua compatible keymap */
int main(int argc, char** arg)
{
	fprintf(stdout,
"local restbl = {\n\
	name = [[%s]],\n\
	diac_ind = 0,\n\
	map = {},\n\
	platform_flt = function(tbl, str)\n\
		return string.match(str, \"linux\") ~= nil;\n\
	end\n\
};", arg[1]);

/* do plain_map, shift_map, altgr_map, ctrl_map, shift_ctrl_map,
 * altgr_ctrl_map, alt_map - do nothing for 0xf200 */
	struct {
		const char* key;
		u_short* map;
	} maps[] = {
		{.key = "none", .map = plain_map},
		{.key = "altgr", .map = altgr_map},
		{.key = "ctrl", .map = ctrl_map},
		{.key = "shift_ctrl", .map = shift_ctrl_map},
		{.key = "altgr_ctrl", .map = altgr_ctrl_map},
		{.key = "alt", .map = alt_map}
	};
	for (int map=0; map < sizeof(maps)/sizeof(maps[0]); map++){
		fprintf(stdout, "local buf = {};\n");

		for (size_t i = 0; i < NR_KEYS; i++){
			uint8_t u8buf[4];
			size_t nb;

			if (maps[map].map[i] && maps[map].map[i] != 0xf200 &&
				(nb = ucs2_to_utf8(maps[map].map[i], u8buf)) > 0){
				fprintf(stdout, "buf[%zu] = [[", i);
				fwrite(u8buf, 1, nb, stdout);
				fwrite("]];\n", 1, 4, stdout);
			}
		}
		fprintf(stdout, "restbl.map[%s] = buf;\n", maps[map].key);
	}

	fprintf(stdout, "return restbl;\n");
	return EXIT_SUCCESS;
}
