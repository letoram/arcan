#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

#include <arcan_shmif.h>

#include "../arcan_tuidefs.h"
#include "../arcan_tui.h"
#include "../arcan_tuiwidgets.h"

void arcan_tui_readline_clear(struct tui_readline* T)
{
}

void arcan_tui_readline_free(struct tui_readline* T)
{
}

void arcan_tui_readline_addhistory(struct tui_readline* T, const char* in)
{
}

bool arcan_tui_readline_savestate(
	struct tui_readline* T, uint8_t** buf, size_t* buf_sz)
{
	return false;
}

bool arcan_tui_readline_loadstate(
	struct tui_readline* T, uint8_t* buf, size_t buf_sz)
{
	return false;
}

void arcan_tui_bufferwnd(
	struct tui_context* T, uint8_t* buf, size_t buf_sz, bool write_enable)
{
}

void arcan_tui_bufferwnd_free(struct tui_context* T)
{
}
