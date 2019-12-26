/*
 * Arcan Text-Oriented User Interface Library, Extensions
 * Copyright: 2019, Bjorn Stahl
 * License: 3-clause BSD
 */

#include <unistd.h>
#include <fcntl.h>

#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../../arcan_tui_readline.h"

#define READLINE_MAGIC 0xfefef00d

struct readline_meta {
	uint32_t magic;
	struct tui_cbcfg old_handlers;
	struct tui_readline_opts opts;
	int old_flags;
};

static bool validate_context(struct tui_context* T, struct readline_meta** M)
{
	if (!T)
		return false;

	struct tui_cbcfg handlers;
	arcan_tui_update_handlers(T, NULL, &handlers, sizeof(struct tui_cbcfg));

	struct readline_meta* ch = handlers.tag;
	if (!ch || ch->magic != READLINE_MAGIC)
		return false;

	*M = ch;
	return true;
}

void arcan_tui_readline_setup(
	struct tui_context* C, struct tui_readline_opts* opts, size_t opt_sz)
{
	struct readline_meta* meta = malloc(sizeof(struct readline_meta));
	if (!meta)
		return;

	*meta = (struct readline_meta){
		.magic = READLINE_MAGIC,
	};
}

void arcan_tui_readline_release(struct tui_context* C)
{
}

bool arcan_tui_readline_finished(struct tui_context* C, char** buffer)
{
	return false;
}

void arcan_tui_readline_region(
	struct tui_context* C, size_t x1, size_t y1, size_t x2, size_t y2)
{

}
