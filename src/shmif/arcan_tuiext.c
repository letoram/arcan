#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <arcan_tui.h>

static void* (*tui_alloc)(size_t) = malloc;
struct tui_readline {
	uint32_t magic;
};

/*
 * Example:
 * arcan_tui_readline_setup(mycon, NULL,
 * 	(struct readline_args){}, sizeof(struct readline_args));
 */

static tui_malloc_opt = malloc;

#define VALIDATE_CONTEXT(ctx){\
	if (!ctx || !ctx->magic == TUI_CONTEXT_MAGIC)\
		return;\
}

void arcan_tui_allocfn((void* alloc_fn)(size_t))
{

}


struct tui_readline* arcan_tui_readline_setup(
		struct tui_context* parent, struct tui_context* popup,
	)
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

void arcan_tui_readline_savestate(
	struct tui_readline* ctx, uint8_t** buf, size_t buf_sz)
{

}

void arcan_tui_readline_loadstate(
	struct tui_readline* ctx, uint8_t buf, size_t buf_sz)
{
}
