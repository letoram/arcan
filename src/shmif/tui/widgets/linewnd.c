#include <unistd.h>
#include <fcntl.h>

#include "../../arcan_shmif.h"
#include "../../arcan_tui.h"
#include "../../arcan_tui_linewnd.h"

/*
 Arcan Text-Oriented User Interface Library, Extensions
 Copyright: 2019, Bjorn Stahl
 License: 3-clause BSD
 Description: This widget adds support for transforming a tui context
 into a line oriented window with scrollback.
*/
size_t arcan_tui_linewnd_render(
	struct tui_context* C,
	struct tui_linewnd_line* line, size_t n_lines,
	size_t start_row, size_t start_col,
	size_t end_row, size_t end_col,
	size_t* tabs, size_t n_tabs,
	int flags
)
{
	return 0;
}

void arcan_tui_linewnd_set_buffer(
	struct tui_context* C, struct tui_linewnd_line* lines, size_t n_lines)
{
}

size_t arcan_tui_linewnd_get_buffer(
	struct tui_context* C, struct tui_linewnd_line* lines, size_t n_lines)
{
	return 0;
}

void arcan_tui_linewnd_add_line(
	struct tui_context* C, const struct tui_linewnd_line* line)
{

}

void arcan_tui_linewnd_release(struct tui_context* C)
{
}
