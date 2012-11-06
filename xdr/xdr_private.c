/* xdr_private.c - utility functions for porting xdr
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
#include <stdarg.h>
#include <stdio.h>

#if defined(__CYGWIN__) || defined(__MINGW32__) || defined(_MSC_VER)
# define NOMINMAX
# define WIN_LEAN_AND_MEAN
# include <windows.h>
# include <ctype.h>
#endif /* not (__CYGWIN__ || __MINGW32__ || _MSC_VER) */

#include "xdr_private.h"


static const char *progname;
static const char *
get_progname (void)
{
  if (progname && *progname)
    return progname;
#if defined(__CYGWIN__) || defined(__MINGW32__) || defined(_MSC_VER)
  {
    static char buf[1025];
    const char *p = buf;
    GetModuleFileName (NULL, buf, 1024);
    buf[1024] = '\0';

    /* Skip over the disk name in MSDOS pathnames. */
    if (isalpha ((unsigned char) p[0]) && p[1] == ':')
      p += 2;
    for (progname = p; *p; p++)
      if (((*p) == '/') || ((*p) == '\\'))
        progname = p + 1;
  }
#endif /* not (__CYGWIN__ || __MINGW32__ || _MSC_VER) */
  return progname;
}

void
xdr_vwarnx (const char *format, va_list ap)
{
  if (get_progname ())
    fprintf (stderr, "%s: ", get_progname ());
  if (format)
    vfprintf (stderr, format, ap);
  putc ('\n', stderr);
}

void
xdr_warnx (const char *fmt, ...)
{
  va_list ap;
  va_start (ap, fmt);
  xdr_vwarnx (fmt, ap);
  va_end (ap);
}
