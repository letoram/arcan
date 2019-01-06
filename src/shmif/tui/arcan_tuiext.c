#include <stdlib.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <arcan_tui.h>
#include <arcan_tuiext.h>

static void* (*tui_alloc)(size_t) = malloc;
struct tui_readline {
	uint32_t magic;
};

/*
 * Example:
 * arcan_tui_readline_setup(mycon, NULL,
 * 	(struct readline_args){}, sizeof(struct readline_args));
 */

#define TUI_CONTEXT_MAGIC 0xfeedface

#define VALIDATE_CONTEXT(ctx){\
	if (!ctx || !ctx->magic == TUI_CONTEXT_MAGIC)\
		return;\
}

/*
 * Possible that this should be shared for all tui
 */
void arcan_tui_allocfn(void*(*alloc_fn)(size_t))
{
	if (alloc_fn)
		tui_alloc = alloc_fn;
}

struct tui_readline* arcan_tui_readline_setup(
	struct tui_context* parent,
	struct tui_context* popup,

	void (*on_update)(struct tui_context*,
		size_t ofs_x, size_t ofs_y, const char* msg,
		const char* hint_msg, bool done, void*),

	bool (*on_completion)(struct tui_context*,
		const char* inmsg, int index,
		char** outmsg, uint8_t* outrgb[3],
		void* tag
	),

	struct readline_args opts,
	void* tag)
{

}

void arcan_tui_readline_clear(struct tui_readline* ctx)
{

}

void arcan_tui_readline_free(struct tui_readline* ctx)
{

}

void arcan_tui_readline_addhistory(struct tui_readline* ctx, const char* in)
{
	VALIDATE_CONTEXT(ctx);

}

bool arcan_tui_readline_savestate(
	struct tui_readline* ctx, uint8_t** buf, size_t* buf_sz)
{

}

bool arcan_tui_readline_loadstate(
	struct tui_readline* ctx, uint8_t* buf, size_t buf_sz)
{
}

void arcan_tui_bufferwnd(
	struct tui_context* ctx, uint8_t* buf, size_t buf_sz, bool write_enable)
{
}

void arcan_tui_bufferwnd_free(struct tui_context* ctx)
{

}

void arcan_tui_listwnd_setup(struct tui_context* src,
	struct tui_list_entry** list, size_t struct_listent_sz)
{

}

void arcan_tui_listwnd_restore(struct tui_context* src)
{

}
