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

bool arcan_trace_enabled = false;

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
	}

	if (!buf || !buf_sz)
		return;

	buffer = buf;
	buffer_flag = finish_flag;
	buffer_sz = buf_sz;
	arcan_trace_enabled = true;
}

void arcan_trace_threadname(const char* name)
{
}

void arcan_trace_log(const char* message, size_t len)
{
	if (!arcan_trace_enabled)
		return;

	for (int i=0; i < len; i++) {
		if (buffer_pos == buffer_sz)
			return;
		buffer[buffer_pos + i] = message[i];
	}
}

void arcan_trace_init(void* vm)
{
}

void arcan_trace_mark(
	const char* sys, const char* subsys,
	uint8_t trigger, uint8_t tracelevel,
	uint64_t ident, uint32_t quant, const char* message,
	const char* file_name, const char* func_name,
    uint32_t line)
{
	if (!arcan_trace_enabled)
		return;

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

	// Releases trace buffer if it exists
	arcan_trace_setbuffer(buffer, 0, NULL);
}
