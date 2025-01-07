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
 * update the mask of hooks that trigger the watchdog monitor
 */
void alt_trace_hookmask(uint64_t, bool bkpt);

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
 * use our own internal method to extract the callstack and contents thereof
 */
void alt_trace_callstack_raw(lua_State* L, lua_Debug* D, int levels, FILE* out);

/*
 * append the lua VM call backtrace to [out]
 */
void alt_trace_callstack(lua_State* ctx, FILE* out);

/*
 * print (Stdout) the type at stack index [i] appending the suffix to stdout
 */
void alt_trace_print_type(lua_State* L, int i, const char* suffix, FILE*);
