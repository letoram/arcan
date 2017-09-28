/*
 * GPLv2 only -
 * Derived from linux kbd project, see the COPYING file from
 * git://git.kernel.org/pub/scm/linux/kernel/git/legion/kbd.git
 */
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include <keymap/common.h>
#include <keymap/context.h>
#include <keymap/dump.h>
#include <keymap/kmap.h>

/* for shift state, we alias to both lshift and rshift */
static char * mk_mapname(char modifier, bool* alias)
{
	static char *mods[8] = {
		"shift", "ralt", "ctrl", "lalt", "lshift", "rshift", "lctrl", "rctrl"
	};
	static char buf[60];
	int i;

	if (!modifier)
		return "plain";
	buf[0] = 0;

	for (i = 0; i < 8; i++)
		if (modifier & (1 << i)){
			if (buf[0])
				strcat(buf, "_");

			if (i == 0){
				strcat(buf, *alias ? "rshift" : "lshift");
				*alias = true;
			}
			else
				strcat(buf, mods[i]);
		}

	return buf;
}

static inline size_t u32u8(uint32_t u32, uint8_t* u8)
{
    if (u32 < 0x80) {
        *u8 = (uint8_t)u32;
        return 1;
    }
    if (u32 < 0x800) {
        u8[0] = 0xc0 | ((u32 & 0x07c0) >> 6);
        u8[1] = 0x80 |  (u32 & 0x003f);
        return 2;
    }
    if (u32 < 0x10000) {
        u8[0] = 0xe0 | ((u32 & 0xf000) >> 12);
        u8[1] = 0x80 | ((u32 & 0x0fc0) >>  6);
        u8[2] = 0x80 |  (u32 & 0x003f);
        return 3;
    }
    if (u32 < 0x110000) {
        u8[0] = 0xf0 | ((u32 & 0x1c0000) >> 18);
        u8[1] = 0x80 | ((u32 & 0x03f000) >> 12);
        u8[2] = 0x80 | ((u32 & 0x000fc0) >>  6);
        u8[3] = 0x80 |  (u32 & 0x00003f);
        return 4;
    }
    return 0;
}

static void dump_utf8(uint8_t ub[4], size_t nb)
{
	if (nb == 1)
		fprintf(stdout, "\\%.3d", ub[0]);
	else if (nb == 2)
		fprintf(stdout, "\\%.3d\\%.3d", ub[0], ub[1]);
	else if (nb == 3)
		fprintf(stdout, "\\%.3d\\%.3d\\%.3d", ub[0], ub[1], ub[2]);
	else if (nb == 4)
		fprintf(stdout, "\\%.3d\\%.3d\\%.3d\\%.3d", ub[0], ub[1], ub[2], ub[3]);
}

static size_t code_tou8(struct lk_ctx* ctx, int code, uint8_t ub[4])
{
	char* sym = lk_code_to_ksym(ctx, code);
	if (!sym || strcmp(sym, "VoidSymbol") == 0){
		free(sym);
		return 0;
	}

	size_t nb = u32u8(lk_ksym_to_unicode(ctx, sym), ub);
	if (0 == nb){
		free(sym);
		return 0;
	}

	free(sym);
	return nb;
}

int main(int argc, char** argv)
{
	struct lk_ctx* ctx = lk_init();

	if (argc < 3){
			fprintf(stderr, "usage: conv name keymap1 keymap2 .. keymapn \n");
			return EXIT_FAILURE;
	}

	lk_add_constants(ctx);
	lk_set_log_fn(ctx, NULL, NULL);
	lk_set_parser_flags(ctx, LK_FLAG_UNICODE_MODE | LK_FLAG_PREFER_UNICODE);

	for (size_t i = 2; i < argc; i++){
		lkfile_t* file = lk_fpopen(argv[i]);
	if (file){
		lk_parse_keymap(ctx, file);
		lk_fpclose(file);
	}
	else
		fprintf(stderr, "couldn't load keymap (%s)\n", argv[i]);
	}

	fprintf(stdout,
"local restbl = {\n\
	name = [[%s]],\n\
	diac_ind = 0,\n\
	diac = {},\n\
	map = {},\n\
	platform_flt = function(tbl, str)\n\
		return string.match(str, \"linux\") ~= nil;\n\
	end\n\
};", argv[1]);

	for (size_t i = 0; i < MAX_NR_KEYMAPS; i++){
		if (lk_map_exists(ctx, i)){
			fprintf(stdout, "local buf = {};\n");
			for (size_t j = 0; j < NR_KEYS; j++){
				int code = lk_get_key(ctx, i, j);
				uint8_t ub[4];
				size_t nb = code_tou8(ctx, code, ub);
				if (0 == nb)
					continue;
				fprintf(stdout, "buf[%zu] = \"", j);
				dump_utf8(ub, nb);
				fprintf(stdout, "\";\n");
			}
			bool alias = false;
			fprintf(stdout, "restbl.map[\"%s\"] = buf;\n", mk_mapname(i, &alias));
			if (alias)
				fprintf(stdout, "restbl.map[\"%s\"] = buf;\n", mk_mapname(i, &alias));
		}
	}

	int ind = 1;
	for (size_t i=0; i < MAX_DIACR; i++){
		if (lk_diacr_exists(ctx, i)){
			struct lk_kbdiacr dcr;
			lk_get_diacr(ctx, i, &dcr);

			uint8_t base[4], diacr[4], res[4];
			size_t base_sz = code_tou8(ctx, dcr.base, base);
			size_t diacr_sz = code_tou8(ctx, dcr.diacr, diacr);
			size_t res_sz = code_tou8(ctx, dcr.result, res);
			if (base_sz && diacr_sz && res_sz){
				fprintf(stdout, "restbl.diac[%d] = {\"", ind++);
				dump_utf8(base, base_sz);
				fprintf(stdout, "\", \"");
				dump_utf8(diacr, diacr_sz);
				fprintf(stdout, "\", \"");
				dump_utf8(res, res_sz);
				fprintf(stdout, "\"};\n");
			}
			else
				fprintf(stdout, "failed on diacr %zu\n", i);
		}
	}

	fprintf(stdout, "return restbl;\n");
	return EXIT_SUCCESS;
}
