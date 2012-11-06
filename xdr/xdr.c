/*
 * Copyright (c) 2009, Sun Microsystems, Inc.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 * - Redistributions of source code must retain the above copyright notice,
 *   this list of conditions and the following disclaimer.
 * - Redistributions in binary form must reproduce the above copyright notice,
 *   this list of conditions and the following disclaimer in the documentation
 *   and/or other materials provided with the distribution.
 * - Neither the name of Sun Microsystems, Inc. nor the names of its
 *   contributors may be used to endorse or promote products derived
 *   from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

/*
 * xdr.c, Generic XDR routines implementation.
 *
 * Copyright (C) 1986, Sun Microsystems, Inc.
 *
 * These are the "generic" xdr routines used to serialize and de-serialize
 * most common data items.  See xdr.h for more info on the interface to
 * xdr.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "types.h"
#include "xdr.h"

#include "xdr_private.h"

/*
 * constants specific to the xdr "protocol"
 */
#define XDR_FALSE       ((long) 0)
#define XDR_TRUE        ((long) 1)
#define LASTUNSIGNED    ((u_int) 0-1)

/*
 * for unit alignment
 */
static const char xdr_zero[BYTES_PER_XDR_UNIT] = { 0, 0, 0, 0 };

/*
 * Free a data structure using XDR
 * Not a filter, but a convenient utility nonetheless
 */
void
xdr_free (xdrproc_t proc, void *objp)
{
  XDR x;

  x.x_op = XDR_FREE;
  (*proc) (&x, objp);
}

/*
 * XDR nothing
 */
bool_t
xdr_void (void)
{
  return TRUE;
}


/*
 * XDR integers
 */
bool_t
xdr_int (XDR * xdrs, int *ip)
{
#if INT_MAX < LONG_MAX
  long l;
  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      l = (long) *ip;
      return (XDR_PUTLONG (xdrs, &l));

    case XDR_DECODE:
      if (!XDR_GETLONG (xdrs, &l))
        {
          return FALSE;
        }
      *ip = (int) l;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
#elif INT_MAX == LONG_MAX
  return xdr_long (xdrs, (long *) ip);
#else
# error Unexpeced integer sizes in xdr_int()
#endif
}

/*
 * XDR unsigned integers
 */
bool_t
xdr_u_int (XDR * xdrs, u_int * up)
{
#if UINT_MAX < ULONG_MAX
  u_long l;
  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      l = (u_long) * up;
      return (XDR_PUTLONG (xdrs, (long *) &l));

    case XDR_DECODE:
      if (!XDR_GETLONG (xdrs, (long *) &l))
        {
          return FALSE;
        }
      *up = (u_int) (u_long) l;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
#elif UINT_MAX == ULONG_MAX
  return xdr_u_long (xdrs, (u_long *) up);
#else
# error Unexpeced integer sizes in xdr_int()
#endif
}

/*
 * XDR long integers
 */
bool_t
xdr_long (XDR * xdrs, long *lp)
{
#ifdef _MSC_VER
# pragma warning(push)
# pragma warning(disable:4127)
#endif
  if ((xdrs->x_op == XDR_ENCODE)
      && ((sizeof (int32_t) == sizeof (long)) || ((int32_t) *lp == *lp)))
    return XDR_PUTLONG (xdrs, lp);
#ifdef _MSC_VER
# pragma warning(pop)
#endif

  if (xdrs->x_op == XDR_DECODE)
    return XDR_GETLONG (xdrs, lp);

  if (xdrs->x_op == XDR_FREE)
    return TRUE;

  return FALSE;
}

/*
 * XDR unsigned long integers
 */
bool_t
xdr_u_long (XDR * xdrs, u_long * ulp)
{
  switch (xdrs->x_op)
    {
#ifdef _MSC_VER
# pragma warning(push)
# pragma warning(disable:4127)
#endif
    case XDR_ENCODE:
      if ((sizeof (uint32_t) != sizeof (u_long)) && ((uint32_t) *ulp != *ulp))
        return FALSE;
      return (XDR_PUTLONG (xdrs, (long *) ulp));
#ifdef _MSC_VER
# pragma warning(pop)
#endif

    case XDR_DECODE:
      {
        long int tmp;
        if (XDR_GETLONG (xdrs, &tmp) == FALSE)
          return FALSE;
        *ulp = (u_long) (uint32_t) tmp;
        return TRUE;
      }

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}


/*
 * XDR 32-bit integers
 */
bool_t
xdr_int32_t (XDR * xdrs, int32_t * int32_p)
{
  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      return XDR_PUTINT32 (xdrs, int32_p);

    case XDR_DECODE:
      return XDR_GETINT32(xdrs, int32_p);

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR unsigned 32-bit integers
 */
bool_t
xdr_u_int32_t (XDR * xdrs, u_int32_t * u_int32_p)
{
  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      return XDR_PUTINT32 (xdrs, (int32_t *)u_int32_p);

    case XDR_DECODE:
      return XDR_GETINT32 (xdrs, (int32_t *)u_int32_p);

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR unsigned 32-bit integers
 */
bool_t
xdr_uint32_t (XDR * xdrs, uint32_t * uint32_p)
{
  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      return XDR_PUTINT32 (xdrs, (int32_t *)uint32_p);

    case XDR_DECODE:
      return XDR_GETINT32 (xdrs, (int32_t *)uint32_p);

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR short integers
 */
bool_t
xdr_short (XDR * xdrs, short *sp)
{
  long l;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      l = (long) *sp;
      return (XDR_PUTLONG (xdrs, &l));

    case XDR_DECODE:
      if (!XDR_GETLONG (xdrs, &l))
        return FALSE;
      *sp = (short) l;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR unsigned short integers
 */
bool_t
xdr_u_short (XDR * xdrs, u_short * usp)
{
  long l;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      l = (u_long) * usp;
      return XDR_PUTLONG (xdrs, &l);

    case XDR_DECODE:
      if (!XDR_GETLONG (xdrs, &l))
        return FALSE;
      *usp = (u_short) (u_long) l;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}


/*
 * XDR 16-bit integers
 */
bool_t
xdr_int16_t (XDR * xdrs, int16_t * int16_p)
{
  int32_t t;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      t = (int32_t) *int16_p;
      return XDR_PUTINT32 (xdrs, &t);

    case XDR_DECODE:
      if (!XDR_GETINT32 (xdrs, &t))
        return FALSE;
      *int16_p = (int16_t) t;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR unsigned 16-bit integers
 */
bool_t
xdr_u_int16_t (XDR * xdrs, u_int16_t * u_int16_p)
{
  uint32_t ut;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      ut = (uint32_t) *u_int16_p;
      return XDR_PUTINT32 (xdrs, (int32_t *)&ut);

    case XDR_DECODE:
      if (!XDR_GETINT32 (xdrs, (int32_t *)&ut))
        return FALSE;
      *u_int16_p = (u_int16_t) ut;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR unsigned 16-bit integers
 */
bool_t
xdr_uint16_t (XDR * xdrs, uint16_t * uint16_p)
{
  uint32_t ut;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      ut = (uint32_t) *uint16_p;
      return XDR_PUTINT32 (xdrs, (int32_t *)&ut);

    case XDR_DECODE:
      if (!XDR_GETINT32 (xdrs, (int32_t *)&ut))
        return FALSE;
      *uint16_p = (uint16_t) ut;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR 8-bit integers
 */
bool_t
xdr_int8_t (XDR * xdrs, int8_t * int8_p)
{
  int32_t t;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      t = (int32_t) *int8_p;
      return XDR_PUTINT32 (xdrs, &t);

    case XDR_DECODE:
      if (!XDR_GETINT32 (xdrs, &t))
        return FALSE;
      *int8_p = (int8_t) t;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR unsigned 8-bit integers
 */
bool_t
xdr_u_int8_t (XDR * xdrs, u_int8_t * u_int8_p)
{
  uint32_t ut;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      ut = (uint32_t) *u_int8_p;
      return XDR_PUTINT32 (xdrs, (int32_t *)&ut);

    case XDR_DECODE:
      if (!XDR_GETINT32 (xdrs, (int32_t *)&ut))
        return FALSE;
      *u_int8_p = (u_int8_t) ut;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR unsigned 8-bit integers
 */
bool_t
xdr_uint8_t (XDR * xdrs, uint8_t * uint8_p)
{
  uint32_t ut;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      ut = (uint32_t) *uint8_p;
      return XDR_PUTINT32 (xdrs, (int32_t *)&ut);

    case XDR_DECODE:
      if (!XDR_GETINT32 (xdrs, (int32_t *)&ut))
        return FALSE;
      *uint8_p = (uint8_t) ut;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;

}


/*
 * XDR a char
 */
bool_t
xdr_char (XDR * xdrs, char *cp)
{
  int i;

  i = (*cp);
  if (!xdr_int (xdrs, &i))
    return FALSE;
  *cp = (char) i;
  return TRUE;
}

/*
 * XDR an unsigned char
 */
bool_t
xdr_u_char (XDR * xdrs, u_char * cp)
{
  u_int u;

  u = (*cp);
  if (!xdr_u_int (xdrs, &u))
    return FALSE;
  *cp = (u_char) u;
  return TRUE;
}

/*
 * XDR booleans
 */
bool_t
xdr_bool (XDR * xdrs, bool_t * bp)
{
  long lb;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      lb = *bp ? XDR_TRUE : XDR_FALSE;
      return XDR_PUTLONG (xdrs, &lb);

    case XDR_DECODE:
      if (!XDR_GETLONG (xdrs, &lb))
        return FALSE;
      *bp = (lb == XDR_FALSE) ? FALSE : TRUE;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR enumerations
 */
bool_t
xdr_enum (XDR * xdrs, enum_t * ep)
{
  enum sizecheck
  { SIZEVAL };                  /* used to find the size of an enum */

  /*
   * enums are treated as ints
   */
#ifdef _MSC_VER
# pragma warning(push)
# pragma warning(disable:4127)
#endif
  /* LINTED */ if (sizeof (enum sizecheck) == 4)
    {
#if INT_MAX < LONG_MAX
      long l;
      switch (xdrs->x_op)
        {
        case XDR_ENCODE:
          l = (long) *ep;
          return XDR_PUTLONG (xdrs, &l);

        case XDR_DECODE:
          if (!XDR_GETLONG (xdrs, &l))
            return FALSE;
          *ep = l;
        case XDR_FREE:
          return TRUE;
        }
#else
       return xdr_long (xdrs, (long *) (void *) ep);
#endif
    }
  else /* LINTED */ if (sizeof (enum sizecheck) == sizeof (short))
    {
       return (xdr_short (xdrs, (short *) (void *) ep));
    }
  return FALSE;
#ifdef _MSC_VER
# pragma warning(pop)
#endif
}

/*
 * XDR opaque data
 * Allows the specification of a fixed size sequence of opaque bytes.
 * cp points to the opaque object and cnt gives the byte length.
 */
bool_t
xdr_opaque (XDR * xdrs, caddr_t cp, u_int cnt)
{
  u_int rndup;
  static char crud[BYTES_PER_XDR_UNIT];

  /*
   * if no data we are done
   */
  if (cnt == 0)
    return TRUE;

  /*
   * round byte count to full xdr units
   */
  rndup = cnt % BYTES_PER_XDR_UNIT;
  if (rndup > 0)
    rndup = BYTES_PER_XDR_UNIT - rndup;

  switch (xdrs->x_op)
    {
    case XDR_DECODE:
      if (!XDR_GETBYTES (xdrs, cp, cnt))
        return FALSE;
      if (rndup == 0)
        return TRUE;
      return XDR_GETBYTES (xdrs, (caddr_t) crud, rndup);

    case XDR_ENCODE:
      if (!XDR_PUTBYTES (xdrs, cp, cnt))
        return FALSE;
      if (rndup == 0)
        return TRUE;
      return (XDR_PUTBYTES (xdrs, xdr_zero, rndup));

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR counted bytes
 * *cpp is a pointer to the bytes, *sizep is the count.
 * If *cpp is NULL maxsize bytes are allocated
 */
bool_t
xdr_bytes (XDR * xdrs, char **cpp, u_int * sizep, u_int maxsize)
{
  char *sp = *cpp;              /* sp is the actual string pointer */
  u_int nodesize;

  /*
   * first deal with the length since xdr bytes are counted
   */
  if (!xdr_u_int (xdrs, sizep))
    return FALSE;

  nodesize = *sizep;
  if ((nodesize > maxsize) && (xdrs->x_op != XDR_FREE))
    return FALSE;

  /*
   * now deal with the actual bytes
   */
  switch (xdrs->x_op)
    {
    case XDR_DECODE:
      if (nodesize == 0)
        return TRUE;
      if (sp == NULL)
        *cpp = sp = mem_alloc (nodesize);
      if (sp == NULL)
        {
          xdr_warnx ("xdr_bytes: out of memory");
          return FALSE;
        }
      /* FALLTHROUGH */

    case XDR_ENCODE:
      return xdr_opaque (xdrs, sp, nodesize);

    case XDR_FREE:
      if (sp != NULL)
        {
          mem_free (sp, nodesize);
          *cpp = NULL;
        }
      return TRUE;
    }
  return FALSE;
}

/*
 * Implemented here due to commonality of the object.
 */
bool_t
xdr_netobj (XDR * xdrs, struct netobj * np)
{
  return (xdr_bytes (xdrs, &np->n_bytes, &np->n_len, MAX_NETOBJ_SZ));
}

/*
 * XDR a descriminated union
 * Support routine for discriminated unions.
 * You create an array of xdrdiscrim structures, terminated with
 * an entry with a null procedure pointer.  The routine gets
 * the discriminant value and then searches the array of xdrdiscrims
 * looking for that value.  It calls the procedure given in the xdrdiscrim
 * to handle the discriminant.  If there is no specific routine a default
 * routine may be called.
 * If there is no specific or default routine an error is returned.
 *   dscmp:    enum to decide which arm to work on
 *   unp:      ptr to the union itself
 *   choices:  ptr to array of [value, xdr proc] for each arm
 *   dfault:   default xdr routine
 */
bool_t
xdr_union (XDR * xdrs, enum_t * dscmp, char *unp,
           const struct xdr_discrim * choices, xdrproc_t dfault)
{
  enum_t dscm;

  /*
   * we deal with the discriminator;  it's an enum
   */
  if (!xdr_enum (xdrs, dscmp))
    return FALSE;

  dscm = *dscmp;

  /*
   * search choices for a value that matches the discriminator.
   * if we find one, execute the xdr routine for that value.
   */
  for (; choices->proc != NULL_xdrproc_t; choices++)
    {
      if (choices->value == dscm)
        return ((*(choices->proc)) (xdrs, unp, LASTUNSIGNED));
    }

  /*
   * no match - execute the default xdr routine if there is one
   */
  return ((dfault == NULL_xdrproc_t) ? FALSE : (*dfault) (xdrs, unp, LASTUNSIGNED));
}


/*
 * Non-portable xdr primitives.
 * Care should be taken when moving these routines to new architectures.
 */


/*
 * XDR null terminated ASCII strings
 * xdr_string deals with "C strings" - arrays of bytes that are
 * terminated by a NULL character.  The parameter cpp references a
 * pointer to storage; If the pointer is null, then the necessary
 * storage is allocated.  The last parameter is the max allowed length
 * of the string as specified by a protocol.
 */
bool_t
xdr_string (XDR * xdrs, char **cpp, u_int maxsize)
{
  char *sp = *cpp;              /* sp is the actual string pointer */
  u_int size;
  u_int nodesize;

  /*
   * first deal with the length since xdr strings are counted-strings
   */
  switch (xdrs->x_op)
    {
    case XDR_FREE:
      if (sp == NULL)
        return TRUE;        /* already free */

      /* FALLTHROUGH */
    case XDR_ENCODE:
      if (sp == NULL)
        return FALSE;

      size = strlen (sp);
      break;
    case XDR_DECODE:
      break;
    }
  if (!xdr_u_int (xdrs, &size))
      return FALSE;

  if (size > maxsize)
    return FALSE;

  nodesize = size + 1;
  if (nodesize == 0)
    {
      /* This means an overflow.  It a bug in the caller which
       * provided a too large maxsize but nevertheless catch it
       * here.
       */
      return FALSE;
    }

  /*
   * now deal with the actual bytes
   */
  switch (xdrs->x_op)
    {

    case XDR_DECODE:
      if (sp == NULL)
        *cpp = sp = mem_alloc (nodesize);
      if (sp == NULL)
        {
          xdr_warnx ("xdr_string: out of memory");
          return FALSE;
        }
      sp[size] = 0;
      /* FALLTHROUGH */

    case XDR_ENCODE:
      return xdr_opaque (xdrs, sp, size);

    case XDR_FREE:
      mem_free (sp, nodesize);
      *cpp = NULL;
      return TRUE;
    }
  return FALSE;
}

/*
 * Wrapper for xdr_string that can be called directly from
 * routines like clnt_call
 */
bool_t
xdr_wrapstring (XDR * xdrs, char **cpp)
{
  return xdr_string (xdrs, cpp, LASTUNSIGNED);
}

/*
 * NOTE: xdr_hyper(), xdr_u_hyper(), xdr_longlong_t(), and xdr_u_longlong_t()
 * are in the "non-portable" section because they require that a `long long'
 * be a 64-bit type.
 *
 * --thorpej@netbsd.org, November 30, 1999
 */

/*
 * XDR 64-bit integers
 */
bool_t
xdr_int64_t (XDR * xdrs, int64_t * llp)
{
  int32_t t1, t2;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      t1 = (int32_t) ((*llp) >> 32);
      t2 = (int32_t) (*llp);
      return (XDR_PUTINT32 (xdrs, &t1) && XDR_PUTINT32 (xdrs, &t2));

    case XDR_DECODE:
      if (!XDR_GETINT32 (xdrs, &t1) || !XDR_GETINT32 (xdrs, &t2))
        return FALSE;
      *llp = ((int64_t) t1) << 32;
      *llp |= (uint32_t) t2;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}


/*
 * XDR unsigned 64-bit integers
 */
bool_t
xdr_u_int64_t (XDR * xdrs, u_int64_t * ullp)
{
  uint32_t t1, t2;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      t1 = (uint32_t) ((*ullp) >> 32);
      t2 = (uint32_t) (*ullp);
      return (XDR_PUTINT32 (xdrs, (int32_t *)&t1) &&
              XDR_PUTINT32 (xdrs, (int32_t *)&t2));

    case XDR_DECODE:
      if (!XDR_GETINT32 (xdrs, (int32_t *)&t1) ||
          !XDR_GETINT32 (xdrs, (int32_t *)&t2))
        return FALSE;
      *ullp = ((u_int64_t) t1) << 32;
      *ullp |= t2;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}

/*
 * XDR unsigned 64-bit integers
 */
bool_t
xdr_uint64_t (XDR * xdrs, uint64_t * ullp)
{
  uint32_t t1, t2;

  switch (xdrs->x_op)
    {
    case XDR_ENCODE:
      t1 = (uint32_t) ((*ullp) >> 32);
      t2 = (uint32_t) (*ullp);
      return (XDR_PUTINT32 (xdrs, (int32_t *)&t1) &&
              XDR_PUTINT32 (xdrs, (int32_t *)&t2));

    case XDR_DECODE:
      if (!XDR_GETINT32 (xdrs, (int32_t *)&t1) ||
          !XDR_GETINT32 (xdrs, (int32_t *)&t2))
        return FALSE;
      *ullp = ((uint64_t) t1) << 32;
      *ullp |= t2;
      return TRUE;

    case XDR_FREE:
      return TRUE;
    }
  return FALSE;
}


/*
 * XDR hypers
 */
bool_t
xdr_hyper (XDR * xdrs, quad_t * llp)
{
  /*
   * Don't bother open-coding this; it's a fair amount of code.  Just
   * call xdr_int64_t().
   */
  return (xdr_int64_t (xdrs, (int64_t *) llp));
}


/*
 * XDR unsigned hypers
 */
bool_t
xdr_u_hyper (XDR * xdrs, u_quad_t * ullp)
{
  /*
   * Don't bother open-coding this; it's a fair amount of code.  Just
   * call xdr_uint64_t().
   */
  return (xdr_uint64_t (xdrs, (uint64_t *) ullp));
}


/*
 * XDR longlong_t's
 */
bool_t
xdr_longlong_t (XDR * xdrs, quad_t * llp)
{
  /*
   * Don't bother open-coding this; it's a fair amount of code.  Just
   * call xdr_int64_t().
   */
  return (xdr_int64_t (xdrs, (int64_t *) llp));
}


/*
 * XDR u_longlong_t's
 */
bool_t
xdr_u_longlong_t (XDR * xdrs, u_quad_t * ullp)
{
  /*
   * Don't bother open-coding this; it's a fair amount of code.  Just
   * call xdr_u_int64_t().
   */
  return (xdr_uint64_t (xdrs, (uint64_t *) ullp));
}
