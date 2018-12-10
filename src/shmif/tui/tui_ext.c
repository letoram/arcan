#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <stdbool.h>
#include <inttypes.h>

#include "arcan_tui.h"
#include "arcan_tuiext.h"

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
}

bool arcan_tui_readline_loadstate(
	struct tui_readline* T, uint8_t* buf, size_t buf_sz)
{
}

struct tui_bufferwnd* arcan_tui_bufferwnd(
	struct tui_context* T, uint8_t* buf, size_t buf_sz, bool write_enable)
{
	return NULL;
}

void arcan_tui_bufferwnd_free(struct tui_bufferwnd* T)
{
}

bool arcan_tui_bufferwnd_input_label(
	struct tui_bufferwnd* T, const char* label, bool active)
{
	return false;
}

bool arcan_tui_bufferwnd_input_utf8(
	struct tui_bufferwnd* T, const char* u8, size_t len)
{
}

void arcan_tui_bufferwnd_input_key(struct tui_bufferwnd* T,
	uint32_t symest, uint8_t scanmode, uint8_t mods, uint16_t subid)
{

}

void arcan_tui_bufferwnd_input_mbtn(
	struct tui_bufferwnd* T, int lx, int ly, int button, bool active, int mods)
{

}

