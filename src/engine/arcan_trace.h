#ifndef HAVE_ARCAN_TRACE
#define HAVE_ARCAN_TRACE

/*
 * used throughout the engine (if set), using macro form in order for high-
 * optimized builds that disable tracing entirely
 */
extern bool arcan_trace_enabled;

/*
 * enable collection buffer, collection will continue until the next call
 * to setbuffer or when the buffer is full. When that occurs finish_flag
 * is set to true and control over buf will be relinquished.
 *
 * the buffer will be packaged as follow:
 * [status flag] (1b) 0xff for complete, otherwise invalid and processing
 * can stop.
 * timestamp (uint64_t)
 * variable-length system marker (char*)
 * variable-length subsystem marker (char*)
 * tracelevel (uint8_t)
 * quantifier (uint32_t)
 * variable-length message (char*)
 */
void arcan_trace_setbuffer(uint8_t* buf, size_t buf_sz, bool* finish_flag);

/*
 * some tracing implementations are able to bind to the Lua VM directly, as to not pull in those headers everywhere, just void* it.
 */
void arcan_trace_init(void* vmcontext);
/*
 * appends a plain log message to the trace buffer
 */
void arcan_trace_log(const char* message, size_t len);

/*
 * mark the name of the current thread
 */
void arcan_trace_threadname(const char* name);

/*
 * cleans up trace buffer and tracy zones
 */
void arcan_trace_close();

/* add a trace entry-point (though call through the TRACE_MARK macros),
 * sys returns to the main system group (graphics, video, 3d, ...) and
 * subsys for a group specific subsystem (where useful distinctions exist).
 *
 * trigger tells if this is a oneshot (0), enter (1) or exit (2) of the
 * specified subsystem. This is an important grouping to show when a set
 * of values logically belong together, and can be thought of as (unique)
 * <group> ... </group> entries in a markup language.
 *
 * tracelevel is to indicate if the typical path is executed or some
 * deviation (slow, warning, error) is triggered.
 *
 * identifier is some unspecified object identifier when there is a specific
 * object within the system/subsystem
 *
 * quant is some unspecified quantifier when there exist O(n) like relations
 * and the 'n' is dynamic between trace entries.
 *
 * message is some final user readable indicator. */
void arcan_trace_mark(
	const char* sys, const char* subsys,
	uint8_t trigger, uint8_t tracelevel,
	uint64_t identifier,
	uint32_t quant, const char* message,
	const char* file_name, const char* func_name,
	uint32_t line);

enum trace_level {
	TRACE_SYS_DEFAULT = 0,
	TRACE_SYS_SLOW = 1,
	TRACE_SYS_FAST = 2,
	TRACE_SYS_WARN = 3,
	TRACE_SYS_ERROR = 4
};

#ifndef TRACE_MARK_ENTER
#define TRACE_MARK_ENTER(A, B, C, D, E, F) do { \
	if (arcan_trace_enabled){ \
		arcan_trace_mark((A), (B), 1, (C), (D), (E), (F), __FILE__, __FUNCTION__, __LINE__);\
	}\
} while (0);
#endif

#ifndef TRACE_MARK_ONESHOT
#define TRACE_MARK_ONESHOT(A, B, C, D, E, F) do { \
	if (arcan_trace_enabled){ \
		arcan_trace_mark((A), (B), 0, (C), (D), (E), (F), __FILE__, __FUNCTION__, __LINE__);\
	}\
} while (0);
#endif

#ifndef TRACE_MARK_EXIT
#define TRACE_MARK_EXIT(A, B, C, D, E, F) do { \
	if (arcan_trace_enabled){ \
		arcan_trace_mark((A), (B), 2, (C), (D), (E), (F), __FILE__, __FUNCTION__, __LINE__);\
	}\
} while (0);
#endif

#endif
