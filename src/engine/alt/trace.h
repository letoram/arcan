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
 * sweep the current stack and dump the members on it
 */
void alt_trace_dumpstack_raw(lua_State* L, FILE* out);

/*
 * shallow- dump the table at the top of the stack starting at ofs (or 0)
 * and limit to cap (or 0 for no limit) number of keys
 */
void alt_trace_dumptable_raw(lua_State* L, int ofs, int cap, FILE* out);

/*
 * append the lua VM call backtrace to [out]
 */
void alt_trace_callstack(lua_State* ctx, FILE* out);

/*
 * print (Stdout) the type at stack index [i] appending the suffix to stdout
 */
void alt_trace_print_type(lua_State* L, int i, const char* suffix, FILE*);

/*
 * convert back / forth from single entrypoint enum (lua.h)
 */
void alt_trace_cbstate(uint64_t* kind, int64_t* luavid, int64_t* vid);
const char* alt_trace_eptostr(uint64_t ep);
uint64_t alt_trace_strtoep(const char* ep);
