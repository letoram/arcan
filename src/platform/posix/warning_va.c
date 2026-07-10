/*
 * Variadic bodies for arcan_warning / arcan_fatal, compiled via `zig cc`
 * (bundled clang) for targets where the Zig backend cannot generate a
 * variadic function body:
 *   - x86_64-windows: LLVM backend disables @cVaStart ("miscompilations")
 *     and the self-hosted backend has no Win64 var-arg codegen yet.
 * On aarch64 (linux/macOS) the self-hosted backend handles @cVaStart, so
 * warning.zig defines these in pure Zig and this file is not compiled
 * (build.zig only adds it for the affected targets). See warning.zig.
 *
 * Symbols consumed here (defined in warning.zig, C-ABI):
 *   arcan_warning_log_dst : FILE*   (log destination; null → drop)
 *   arcan_fatal_hook      : void(*)(void)
 */
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>

extern void *arcan_warning_log_dst;
extern void (*arcan_fatal_hook)(void);

void arcan_warning(const char *msg, ...)
{
	FILE *dst = (FILE *) arcan_warning_log_dst;
	if (!dst)
		return;
	va_list ap;
	va_start(ap, msg);
	vfprintf(dst, msg, ap);
	va_end(ap);
}

void arcan_fatal(const char *msg, ...)
{
	va_list ap;
	va_start(ap, msg);
	vfprintf(stderr, msg, ap);
	va_end(ap);
	fflush(stderr);
	if (arcan_fatal_hook)
		arcan_fatal_hook();
	abort();
}
