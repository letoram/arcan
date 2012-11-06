/* xdr_private.h - declarations of utility functions for porting xdr
 *
 * Copyright (c) 2009 Charles S. Wilson
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR
 * OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */
#ifndef _XDR_PRIVATE_H
#define _XDR_PRIVATE_H

#include <stdarg.h>
#if !defined(_MSC_VER)
# include <sys/param.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Need to replace these with functions that can
   refer error handling to function pointer */
void xdr_vwarnx (const char *format, va_list ap);
void xdr_warnx (const char *fmt, ...);

/* endian issues */
#if defined(_MSC_VER) || defined(__MINGW32__)
# ifndef BIG_ENDIAN
#  define BIG_ENDIAN 4321
# endif
# ifndef LITTLE_ENDIAN
#  define LITTLE_ENDIAN 1234
# endif
# ifndef __IEEE_LITTLE_ENDIAN
#  define __IEEE_LITTLE_ENDIAN
# endif
# undef  __IEEE_BIG_ENDIAN
# ifndef BYTE_ORDER
#  define BYTE_ORDER LITTLE_ENDIAN
# endif
# define IEEEFP
#elif defined(__CYGWIN__)
# include <machine/endian.h>
# define IEEEFP
#else  /* not _MSC_VER and not __MINGW32__, and not __CYGWIN__ */
# if defined(__m68k__) || defined(__sparc__) || defined(__i386__) || \
     defined(__mips__) || defined(__ns32k__) || defined(__alpha__) || \
     defined(__arm__) || defined(__ppc__) || defined(__ia64__) || \
     defined(__arm26__) || defined(__sparc64__) || defined(__amd64__)
#  include <endian.h>
#  define IEEEFP
# endif
#endif /* not _MSC_VER and not __MINGW32__ */

#ifdef __cplusplus
}
#endif

#endif /* _XDR_PRIVATE_H */

