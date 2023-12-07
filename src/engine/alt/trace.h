/*
 * setup a tracing session where [cb] will be held until [sz]
 * buffer has been filled or the tracing is explicitly finished.
 */
bool alt_trace_start(lua_State* ctx, intptr_t cb, size_t sz);

/*
 * activate / flush any pending trace buffer
 */
void alt_trace_finish(lua_State* ctx);

/*
 * logs text string in stdout and in active trace buffer
 */
int alt_trace_log(lua_State* ctx);

/*
 * copy [msg] and keep as the last known crash source in the
 * accumulated trash buffer.
 */
void alt_trace_set_crash_source(const char* msg);

/*
 * retrieve the last set trace buffer, valid until the next
 * call to _set_crash_source
 */
char* alt_trace_crash_source(void);

/*
 * append the lua VM call backtrace to [out]
 */
void alt_trace_callstack(lua_State* ctx, FILE* out);
