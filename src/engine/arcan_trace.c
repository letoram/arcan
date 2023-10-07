#include <stdint.h>
#include <stdlib.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <stdatomic.h>

#include "arcan_math.h"
#include "arcan_general.h"

#ifdef WITH_TRACY
#include "tracy/TracyC.h"
bool arcan_trace_enabled = true;
#else
bool arcan_trace_enabled = false;
#endif

static uint8_t* buffer;
static size_t buffer_sz;
static size_t buffer_pos;
static bool* buffer_flag;

void arcan_trace_setbuffer(uint8_t* buf, size_t buf_sz, bool* finish_flag)
{
	if (buffer){
		*buffer_flag = true;
		buffer = NULL;
		buffer_flag = NULL;
		buffer_pos = 0;
		#ifndef WITH_TRACE
		arcan_trace_enabled = false;
		#endif
	}

	if (!buf || !buf_sz)
		return;

	buffer = buf;
	buffer_flag = finish_flag;
	buffer_sz = buf_sz;
	arcan_trace_enabled = true;
}

void arcan_trace_log(const char* message, size_t len)
{
	if (!arcan_trace_enabled)
		return;

#ifdef WITH_TRACY
	TracyCMessage(message, len);
#else
	for (int i=0; i < len; i++) {
		if (buffer_pos == buffer_sz)
			return;
		buffer[buffer_pos + i] = message[i];
	}
#endif
}

#ifdef WITH_TRACY
const uint32_t color_lut[] = {
	0x000000, // DEFAULT
	0x02dffc, // SLOW
	0x41d12b, // FAST
	0xefd13b, // WARN
	0xc63629, // ERROR
};

struct MarkID {
	const char* sys;
	const char* subsys;
	uint16_t zone_id;
};

struct ZoneCtx {
	TracyCZoneCtx ctx;
	uint16_t zone_id;
};

#define TRACY_ZONES 256
#define TRACY_MARKS TRACY_ZONES*2
#define TRACY_STACK 64
static struct {
	struct MarkID mark_ids[TRACY_MARKS];

	char* zone_name[TRACY_ZONES];
	uint16_t zone_name_len[TRACY_ZONES];
	struct ___tracy_source_location_data zone_loc[TRACY_ZONES];

	struct ZoneCtx zone_stack[TRACY_STACK];

	uint16_t mark_ids_len;
	uint16_t zone_id;
	uint16_t zone_stack_len;
} tracy_ctx;

uint16_t get_zone_id(const char* sys, const char* subsys, const char* file, const char* function, uint32_t line) {
	// Fast path
	for (uint16_t i=0; i<tracy_ctx.mark_ids_len; i++) {
		const struct MarkID *mark_id = &tracy_ctx.mark_ids[i];
		if (mark_id->sys == sys && mark_id->subsys == subsys)
			return mark_id->zone_id;
	}

	if (tracy_ctx.mark_ids_len == TRACY_MARKS) {
		fprintf(stderr, "trace mark cache overflow");
		exit(EXIT_FAILURE);
	}

	// Slow path
	for (uint16_t i=0; i<tracy_ctx.mark_ids_len; i++) {
		const struct MarkID mark_id = tracy_ctx.mark_ids[i];
		if (strcmp(mark_id.sys, sys) == 0 && strcmp(mark_id.subsys, subsys) == 0) {
			tracy_ctx.mark_ids[tracy_ctx.mark_ids_len] = (struct MarkID){
				.sys = sys,
				.subsys = subsys,
				.zone_id = mark_id.zone_id
			};
			tracy_ctx.mark_ids_len++;
			return mark_id.zone_id;
		}
	}

	if (tracy_ctx.zone_id == TRACY_ZONES) {
		fprintf(stderr, "trace zone cache overflow");
		exit(EXIT_FAILURE);
	}

	// Sluggish path
	const uint16_t s_len = strlen(sys) + strlen(subsys) + 4;
	const uint16_t zone_id = tracy_ctx.zone_id;
	const uint16_t mark_id = tracy_ctx.mark_ids_len;
	tracy_ctx.zone_id++;
	tracy_ctx.mark_ids_len++;

	tracy_ctx.zone_name[zone_id] = malloc(s_len);
	tracy_ctx.zone_name_len[zone_id] = MIN(
		s_len - 1,
		snprintf(tracy_ctx.zone_name[zone_id], s_len, "[%s] %s", sys, subsys)
	);

	tracy_ctx.zone_loc[zone_id] = (struct ___tracy_source_location_data){
		.file = file,
		.function = function,
		.line = line
	};

	tracy_ctx.mark_ids[mark_id] = (struct MarkID){
		.sys = sys,
		.subsys = subsys,
		.zone_id = zone_id
	};

	return zone_id;
}
#endif

void arcan_trace_mark(
	const char* sys, const char* subsys,
	uint8_t trigger, uint8_t tracelevel,
	uint64_t ident, uint32_t quant, const char* message,
	const char* file_name, const char* func_name,
    uint32_t line)
{
	if (!arcan_trace_enabled)
		return;

	#ifdef WITH_TRACY
	const uint16_t zid = get_zone_id(sys, subsys, file_name, func_name, line);

	switch (trigger) {
	case 0: // ONESHOT
		{
		TracyCZoneCtx ctx = ___tracy_emit_zone_begin(&tracy_ctx.zone_loc[zid], true);

		___tracy_emit_zone_name(ctx, tracy_ctx.zone_name[zid], tracy_ctx.zone_name_len[zid]);
		___tracy_emit_zone_color(ctx, color_lut[tracelevel]);

		___tracy_emit_zone_text(ctx, "[ONESHOT]", 9);

		___tracy_emit_zone_text(ctx, "Ident:", 6);
		___tracy_emit_zone_value(ctx, ident);

		___tracy_emit_zone_text(ctx, "\nQuant:", 7);
		___tracy_emit_zone_value(ctx, quant);

		if (message) {
			___tracy_emit_zone_text(ctx, "\nMessage:", 9);
			___tracy_emit_zone_text(ctx, message, strlen(message));
		}

		___tracy_emit_zone_end(ctx);
		}
		break;
	case 1: // ENTER
		{
		TracyCZoneCtx ctx = ___tracy_emit_zone_begin_callstack(&tracy_ctx.zone_loc[zid], 8, true);

		___tracy_emit_zone_name(ctx, tracy_ctx.zone_name[zid], tracy_ctx.zone_name_len[zid]);
		___tracy_emit_zone_color(ctx, color_lut[tracelevel]);

		___tracy_emit_zone_text(ctx, "Enter ident:", 12);
		___tracy_emit_zone_value(ctx, ident);

		___tracy_emit_zone_text(ctx, "\nEnter quant:", 13);
		___tracy_emit_zone_value(ctx, quant);

		if (message) {
			___tracy_emit_zone_text(ctx, "\nEnter message:", 15);
			___tracy_emit_zone_text(ctx, message, strlen(message));
		}

		if (tracy_ctx.zone_stack_len == TRACY_STACK) {
			fprintf(stderr, "trace zone stack overflow");
			exit(EXIT_FAILURE);
		}

		const struct ZoneCtx zone = { .ctx = ctx, .zone_id = zid };
		tracy_ctx.zone_stack[tracy_ctx.zone_stack_len] = zone;
		tracy_ctx.zone_stack_len++;
		}
		break;
	case 2: // EXIT
		{
		struct ZoneCtx* ctx = NULL;

		for (uint16_t i=tracy_ctx.zone_stack_len; i>0; i--) {
			if (tracy_ctx.zone_stack[i-1].zone_id == zid) {
				ctx = &tracy_ctx.zone_stack[i-1];

				for (uint16_t j=i; i<tracy_ctx.zone_stack_len-1; j++) {
					tracy_ctx.zone_stack[j-1] = tracy_ctx.zone_stack[j];
				}

				tracy_ctx.zone_stack_len--;
				break;
			}
		}

		if (!ctx) {
			fprintf(stderr, "unmatched trace mark exit (sys: %s, subsys: %s)\n", sys, subsys);
			exit(EXIT_FAILURE);
		}

		___tracy_emit_zone_text(ctx->ctx, "\nExit ident:", 12);
		___tracy_emit_zone_value(ctx->ctx, ident);

		___tracy_emit_zone_text(ctx->ctx, "\nExit quant:", 12);
		___tracy_emit_zone_value(ctx->ctx, quant);

		if (message) {
			___tracy_emit_zone_text(ctx->ctx, "\nExit message:", 14);
			___tracy_emit_zone_text(ctx->ctx, message, strlen(message));
		}

		___tracy_emit_zone_end(ctx->ctx);
		}
		break;
	};
	#endif

	if (!buffer)
		return;

	size_t start_ofs = buffer_pos;

	size_t sys_len = strlen(sys) + 1;
	size_t subsys_len = strlen(subsys) + 1;
	size_t msg_len = message ? strlen(message) + 1 : 1;
	size_t tot =
		1 /* ok marker */   +
		8 /* timestamp */   +
		1 /* trigger */     +
		1 /* trace level */ +
		8 /* identifier */  +
		4 /* quantifier */  +
		sys_len + subsys_len + msg_len;

/* tight packing format, valid- mark (0xaa) then arguments in each order,
 * when we reach end, write eos mark (0xff), set finish_flag and disable
 * tracing - rough safety check first before doing anything */
	if (buffer_sz - buffer_pos < tot)
		goto fail_short;

/* ok marker */
	buffer_pos++;

/* timestamp */
	uint64_t ts = arcan_timemicros();
	memcpy(&buffer[buffer_pos], &ts, sizeof(ts));
	buffer_pos += sizeof(ts);

/* sys / subsys */
	memcpy(&buffer[buffer_pos], sys, sys_len);
	buffer_pos += sys_len;
	memcpy(&buffer[buffer_pos], subsys, subsys_len);
	buffer_pos += subsys_len;

/* trigger */
	memcpy(&buffer[buffer_pos], &trigger, 1);
	buffer_pos += 1;

/* tracelevel */
	memcpy(&buffer[buffer_pos], &tracelevel, 1);
	buffer_pos += 1;

/* identifier */
	memcpy(&buffer[buffer_pos], &ident, 8);
	buffer_pos += 8;

/* quantifier */
	memcpy(&buffer[buffer_pos], &quant, 4);
	buffer_pos += 4;

/* message */
	if (message){
		memcpy(&buffer[buffer_pos], message, msg_len);
		buffer_pos += msg_len;
	}
	else {
		buffer[buffer_pos++] = '\0';
	}

/* mark sample as completed */
	buffer[start_ofs] = 0xff;
	return;

fail_short:
	*buffer_flag = true;
	buffer[start_ofs] = 0xaa;
}

void arcan_trace_close()
{
	if (!arcan_trace_enabled)
		return;

	#ifdef WITH_TRACY
	for (int i=tracy_ctx.zone_stack_len-1; i>=0; --i) {
		___tracy_emit_zone_end(tracy_ctx.zone_stack[i].ctx);
	}
	tracy_ctx.zone_stack_len = 0;
	tracy_ctx.mark_ids_len = 0;
	#endif

	// Releases trace buffer if it exists
	arcan_trace_setbuffer(buffer, 0, NULL);
}
