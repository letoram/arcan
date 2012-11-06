
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
 * xdr_rec.c, Implements TCP/IP based XDR streams with a "record marking"
 * layer above tcp (for rpc's use).
 *
 * Copyright (C) 1984, Sun Microsystems, Inc.
 *
 * These routines interface XDRSTREAMS to a tcp/ip connection.
 * There is a record marking layer between the xdr stream
 * and the tcp transport level.  A record is composed on one or more
 * record fragments.  A record fragment is a thirty-two bit header followed
 * by n bytes of data, where n is contained in the header.  The header
 * is represented as a htonl(u_long).  Thegh order bit encodes
 * whether or not the fragment is the last fragment of the record
 * (1 => fragment is last, 0 => more fragments to follow.
 * The other 31 bits encode the byte length of the fragment.
 */

#include <stddef.h>
#include <sys/types.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>
#if defined(_MSC_VER) || defined(__MINGW32__)
# include <io.h>
# include <process.h>
#else
# include <unistd.h>
#endif

#include "types.h"
#include "xdr.h"
#include "xdr_private.h"

enum xprt_stat
{
  XPRT_DIED,
  XPRT_MOREREQS,
  XPRT_IDLE
};

static u_int fix_buf_size ();

static bool_t xdrrec_getlong (XDR *, long *);
static bool_t xdrrec_putlong (XDR *, const long *);
static bool_t xdrrec_getbytes (XDR *, char *, u_int);
static bool_t xdrrec_putbytes (XDR *, const char *, u_int);
static u_int xdrrec_getpos (XDR *);
static bool_t xdrrec_setpos (XDR *, u_int);
static int32_t *xdrrec_inline (XDR *, u_int);
static void xdrrec_destroy (XDR *);
static bool_t xdrrec_getint32 (XDR *, int32_t *);
static bool_t xdrrec_putint32 (XDR *, const int32_t *);

static const struct xdr_ops xdrrec_ops = {
  xdrrec_getlong,
  xdrrec_putlong,
  xdrrec_getbytes,
  xdrrec_putbytes,
  xdrrec_getpos,
  xdrrec_setpos,
  xdrrec_inline,
  xdrrec_destroy,
  xdrrec_getint32,
  xdrrec_putint32
};

/*
 * A record is composed of one or more record fragments.
 * A record fragment is a four-byte header followed by zero to
 * 2**32-1 bytes.  The header is treated as a long unsigned and is
 * encode/decoded to the network via htonl/ntohl.  The low order 31 bits
 * are a byte count of the fragment.  The highest order bit is a boolean:
 * 1 => this fragment is the last fragment of the record,
 * 0 => this fragment is followed by more fragment(s).
 *
 * The fragment/record machinery is not general;  it is constructed to
 * meet the needs of xdr and rpc based on tcp.
 */

#define LAST_FRAG ((u_int32_t)(UINT32_C(1) << 31))

typedef struct rec_strm
{
  caddr_t tcp_handle;
  /*
   * out-goung bits
   */
  caddr_t out_buffer;           /* buffer as allocated; may not be aligned */
  int (*writeit) (void *, void *, int);
  caddr_t out_base;             /* output buffer (points to frag header) */
  caddr_t out_finger;           /* next output position */
  caddr_t out_boundry;          /* data cannot up to this address */
  u_int32_t *frag_header;       /* beginning of curren fragment */
  bool_t frag_sent;             /* true if buffer sent in middle of record */
  /*
   * in-coming bits
   */
  caddr_t in_buffer;            /* buffer as allocated; may not be aligned */
  int (*readit) (void *, void *, int);
  u_long in_size;               /* fixed size of the input buffer */
  caddr_t in_base;
  caddr_t in_finger;            /* location of next byte to be had */
  caddr_t in_boundry;           /* can read up to this location */
  long fbtbc;                   /* fragment bytes to be consumed */
  bool_t last_frag;
  u_int sendsize;               /* must be <= INT_MAX */
  u_int recvsize;               /* must be <= INT_MAX */

  bool_t nonblock;
  bool_t in_haveheader;
  u_int32_t in_header;
  char *in_hdrp;
  int in_hdrlen;
  int in_reclen;
  int in_received;
  int in_maxrec;
} RECSTREAM;

static u_int fix_buf_size (u_int);
static bool_t flush_out (RECSTREAM *, bool_t);
static bool_t fill_input_buf (RECSTREAM *);
static bool_t get_input_bytes (RECSTREAM *, char *, size_t);
static bool_t set_input_fragment (RECSTREAM *);
static bool_t skip_input_bytes (RECSTREAM *, long);
static bool_t realloc_stream (RECSTREAM *, int);

bool_t __xdrrec_getrec (XDR *, enum xprt_stat *, bool_t);
bool_t __xdrrec_setnonblock (XDR *, int);

/*
 * Create an xdr handle for xdrrec
 * xdrrec_create fills in xdrs.  Sendsize and recvsize are
 * send and recv buffer sizes (0 => use default), and must be <= INT_MAX.
 * tcp_handle is an opaque handle that is passed as the first parameter to
 * the procedures readit and writeit.  Readit and writeit are read and
 * write respectively.   They are like the system
 * calls except that they take an opaque handle rather than an fd.
 */
void
xdrrec_create (XDR * xdrs, u_int sendsize, u_int recvsize, void *tcp_handle,
               int (*readit) (void *, void *, int),
               int (*writeit) (void *, void *, int))
{
  RECSTREAM *rstrm;
  /* Although sendsize and recvsize are u_int, we require
   * that they be less than INT_MAX, because often we need
   * to compare against values held in (signed) integers.
   * Please don't try to use send/recv buffers > 2GB...
   */
  assert (sendsize < (u_int)INT_MAX);
  assert (recvsize < (u_int)INT_MAX);

  rstrm = (RECSTREAM *) mem_alloc (sizeof (RECSTREAM));
  if (rstrm == NULL)
    {
      xdr_warnx ("xdrrec_create: out of memory");
      /*
       *  This is bad.  Should rework xdrrec_create to
       *  return a handle, and in this case return NULL
       */
      return;
    }


  /* allocate send buffer; insure BYTES_PER_UNIT alignment */
  rstrm->sendsize = sendsize = fix_buf_size (sendsize);
  rstrm->out_buffer = mem_alloc (rstrm->sendsize + BYTES_PER_XDR_UNIT);
  if (rstrm->out_buffer == NULL)
    {
      xdr_warnx ("xdrrec_create: out of memory");
      mem_free (rstrm, sizeof (RECSTREAM));
      return;
    }
  for (rstrm->out_base = rstrm->out_buffer;
       (long) rstrm->out_base % BYTES_PER_XDR_UNIT != 0; rstrm->out_base++)
    ;

  /* allocate recv buffer; insure BYTES_PER_UNIT alignment */
  rstrm->recvsize = recvsize = fix_buf_size (recvsize);
  rstrm->in_buffer = mem_alloc (recvsize + BYTES_PER_XDR_UNIT);
  if (rstrm->in_buffer == NULL)
    {
      xdr_warnx ("xdrrec_create: out of memory");
      mem_free (rstrm->out_buffer, sendsize + BYTES_PER_XDR_UNIT);
      mem_free (rstrm, sizeof (RECSTREAM));
      return;
    }
  for (rstrm->in_base = rstrm->in_buffer;
       (long) rstrm->in_base % BYTES_PER_XDR_UNIT != 0; rstrm->in_base++)
    ;

  /*
   * now the rest ...
   */
  xdrs->x_ops = &xdrrec_ops;
  xdrs->x_private = rstrm;
  rstrm->tcp_handle = tcp_handle;
  rstrm->readit = readit;
  rstrm->writeit = writeit;
  rstrm->out_finger = rstrm->out_boundry = rstrm->out_base;
  rstrm->frag_header = (u_int32_t *) (void *) rstrm->out_base;
  rstrm->out_finger += sizeof (u_int32_t);
  rstrm->out_boundry += sendsize;
  rstrm->frag_sent = FALSE;
  rstrm->in_size = recvsize;
  rstrm->in_boundry = rstrm->in_base;
  rstrm->in_finger = (rstrm->in_boundry += recvsize);
  rstrm->fbtbc = 0;
  rstrm->last_frag = TRUE;
  rstrm->in_haveheader = FALSE;
  rstrm->in_hdrlen = 0;
  rstrm->in_hdrp = (char *) (void *) &rstrm->in_header;
  rstrm->nonblock = FALSE;
  rstrm->in_reclen = 0;
  rstrm->in_received = 0;
}


/*
 * The reoutines defined below are the xdr ops which will go into the
 * xdr handle filled in by xdrrec_create.
 */

static bool_t
xdrrec_getlong (XDR * xdrs, long *lp)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);
  int32_t *buflp = (int32_t *) (void *) (rstrm->in_finger);
  int32_t mylong;

  /* first try the inline, fast case */
  if ((rstrm->fbtbc >= sizeof (int32_t)) &&
      (((long) rstrm->in_boundry - (long) buflp) >= sizeof (int32_t)))
    {
      *lp = (long) ntohl ((u_int32_t) (*buflp));
      rstrm->fbtbc -= sizeof (int32_t);
      rstrm->in_finger += sizeof (int32_t);
    }
  else
    {
      if (!xdrrec_getbytes (xdrs, (char *) (void *) &mylong,
                            sizeof (int32_t)))
        return FALSE;
      *lp = (long) ntohl ((u_int32_t) mylong);
    }
  return TRUE;
}

static bool_t
xdrrec_putlong (XDR * xdrs, const long *lp)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);
  int32_t *dest_lp = ((int32_t *) (void *) (rstrm->out_finger));

  if ((rstrm->out_finger += sizeof (int32_t)) > rstrm->out_boundry)
    {
      /*
       * this case should almost never happen so the code is
       * inefficient
       */
      rstrm->out_finger -= sizeof (int32_t);
      rstrm->frag_sent = TRUE;
      if (!flush_out (rstrm, FALSE))
        return FALSE;
      dest_lp = ((int32_t *) (void *) (rstrm->out_finger));
      rstrm->out_finger += sizeof (int32_t);
    }
  *dest_lp = (int32_t) htonl ((u_int32_t) (*lp));
  return TRUE;
}

static bool_t                   /* must manage buffers, fragments, and records */
xdrrec_getbytes (XDR * xdrs, char *addr, u_int len)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);
  size_t current;

  while (len > 0)
    {
      current = (int) rstrm->fbtbc;
      if (current == 0)
        {
          if (rstrm->last_frag)
            return FALSE;
          if (!set_input_fragment (rstrm))
            return FALSE;
          continue;
        }
      current = (len < current) ? len : current;
      if (!get_input_bytes (rstrm, addr, current))
        return FALSE;
      addr += current;
      rstrm->fbtbc -= current;
      len -= current;
    }
  return TRUE;
}

static bool_t
xdrrec_putbytes (XDR * xdrs, const char *addr, u_int len)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);
  size_t current;

  while (len > 0)
    {
      current = (size_t) ((u_long) rstrm->out_boundry -
                          (u_long) rstrm->out_finger);
      current = (len < current) ? len : current;
      memmove (rstrm->out_finger, addr, current);
      rstrm->out_finger += current;
      addr += current;
      len -= current;
      if (rstrm->out_finger == rstrm->out_boundry)
        {
          rstrm->frag_sent = TRUE;
          if (!flush_out (rstrm, FALSE))
            return FALSE;
        }
    }
  return TRUE;
}

static u_int
xdrrec_getpos (XDR * xdrs)
{
  RECSTREAM *rstrm = (RECSTREAM *) xdrs->x_private;
  off_t pos;

  pos = lseek ((int) (u_long) rstrm->tcp_handle, (off_t) 0, 1);
  if (pos != -1)
    switch (xdrs->x_op)
      {

      case XDR_ENCODE:
        pos += rstrm->out_finger - rstrm->out_base;
        break;

      case XDR_DECODE:
        pos -= rstrm->in_boundry - rstrm->in_finger;
        break;

      default:
        pos = (off_t) - 1;
        break;
      }
  return ((u_int) pos);
}

static bool_t
xdrrec_setpos (XDR * xdrs, u_int pos)
{
  RECSTREAM *rstrm = (RECSTREAM *) xdrs->x_private;
  u_int currpos = xdrrec_getpos (xdrs);
  int delta = currpos - pos;
  char *newpos;

  if ((int) currpos != -1)
    switch (xdrs->x_op)
      {

      case XDR_ENCODE:
        newpos = rstrm->out_finger - delta;
        if ((newpos > (char *) (void *) (rstrm->frag_header)) &&
            (newpos < rstrm->out_boundry))
          {
            rstrm->out_finger = newpos;
            return TRUE;
          }
        break;

      case XDR_DECODE:
        newpos = rstrm->in_finger - delta;
        if ((delta < (int) (rstrm->fbtbc)) &&
            (newpos <= rstrm->in_boundry) && (newpos >= rstrm->in_base))
          {
            rstrm->in_finger = newpos;
            rstrm->fbtbc -= delta;
            return TRUE;
          }
        break;

      case XDR_FREE:
        break;
      }
  return FALSE;
}

static int32_t *
xdrrec_inline (XDR * xdrs, u_int len)
{
  RECSTREAM *rstrm = (RECSTREAM *) xdrs->x_private;
  int32_t *buf = NULL;
  /* len represents the number of bytes to extract
   * from the buffer. The number of bytes remaining
   * in the buffer is rstrm->fbtbc, which is a long.
   * Thus, the buffer size maximum is 2GB (!), and
   * we require that no one ever try to read more
   * than than number of bytes at once.
   */
  assert (len < (u_int)LONG_MAX);

  switch (xdrs->x_op)
    {

    case XDR_ENCODE:
      if ((rstrm->out_finger + len) <= rstrm->out_boundry)
        {
          buf = (int32_t *) (void *) rstrm->out_finger;
          rstrm->out_finger += len;
        }
      break;

    case XDR_DECODE:
      if (((long)len <= rstrm->fbtbc) &&
          ((rstrm->in_finger + len) <= rstrm->in_boundry))
        {
          buf = (int32_t *) (void *) rstrm->in_finger;
          rstrm->fbtbc -= len;
          rstrm->in_finger += len;
        }
      break;

    case XDR_FREE:
      break;
    }
  return (buf);
}

static void
xdrrec_destroy (XDR * xdrs)
{
  RECSTREAM *rstrm = (RECSTREAM *) xdrs->x_private;

  mem_free (rstrm->out_buffer, rstrm->sendsize + BYTES_PER_XDR_UNIT);
  mem_free (rstrm->in_buffer, rstrm->recvsize + BYTES_PER_XDR_UNIT);
  mem_free (rstrm, sizeof (RECSTREAM));
}

static bool_t
xdrrec_getint32 (XDR *xdrs, int32_t *ip)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);
  int32_t *bufip = (int32_t *) (void *) (rstrm->in_finger);
  int32_t mylong;

  /* first try the inline, fast case */
  if ((rstrm->fbtbc >= sizeof (int32_t)) &&
      (( rstrm->in_boundry - (char *) bufip) >= sizeof (int32_t)))
    {
      *ip = (int32_t) ntohl (*bufip);
      rstrm->fbtbc -= sizeof (int32_t);
      rstrm->in_finger += sizeof (int32_t);
    }
  else
    {
      if (!xdrrec_getbytes (xdrs, (char *) (void *) &mylong,
                            sizeof (int32_t)))
        return FALSE;
      *ip = (int32_t) ntohl (mylong);
    }
  return TRUE;
}

static bool_t
xdrrec_putint32 (XDR *xdrs, const int32_t *ip)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);
  int32_t *dest_ip = ((int32_t *) (void *) (rstrm->out_finger));

  if ((rstrm->out_finger += sizeof (int32_t)) > rstrm->out_boundry)
    {
      /*
       * this case should almost never happen so the code is
       * inefficient
       */
      rstrm->out_finger -= sizeof (int32_t);
      rstrm->frag_sent = TRUE;
      if (!flush_out (rstrm, FALSE))
        return FALSE;
      dest_ip = ((int32_t *) (void *) (rstrm->out_finger));
      rstrm->out_finger += sizeof (int32_t);
    }
  *dest_ip = (int32_t) htonl (*ip);
  return TRUE;
}

/*
 * Exported routines to manage xdr records
 */

/*
 * Before reading (deserializing from the stream, one should always call
 * this procedure to guarantee proper record alignment.
 */
bool_t
xdrrec_skiprecord (XDR * xdrs)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);
  enum xprt_stat xstat;

  if (rstrm->nonblock)
    {
      if (__xdrrec_getrec (xdrs, &xstat, FALSE))
        {
          rstrm->fbtbc = 0;
          return TRUE;
        }
      if (rstrm->in_finger == rstrm->in_boundry && xstat == XPRT_MOREREQS)
        {
          rstrm->fbtbc = 0;
          return TRUE;
        }
      return FALSE;
    }

  while (rstrm->fbtbc > 0 || (!rstrm->last_frag))
    {
      if (!skip_input_bytes (rstrm, rstrm->fbtbc))
        return FALSE;
      rstrm->fbtbc = 0;
      if ((!rstrm->last_frag) && (!set_input_fragment (rstrm)))
        return FALSE;
    }
  rstrm->last_frag = FALSE;
  return TRUE;
}

/*
 * Look ahead function.
 * Returns TRUE iff there is no more input in the buffer
 * after consuming the rest of the current record.
 */
bool_t
xdrrec_eof (XDR * xdrs)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);

  while (rstrm->fbtbc > 0 || (!rstrm->last_frag))
    {
      if (!skip_input_bytes (rstrm, rstrm->fbtbc))
        return TRUE;
      rstrm->fbtbc = 0;
      if ((!rstrm->last_frag) && (!set_input_fragment (rstrm)))
        return TRUE;
    }
  if (rstrm->in_finger == rstrm->in_boundry)
    return TRUE;
  return FALSE;
}

/*
 * The client must tell the package when an end-of-record has occurred.
 * The second paraemters tells whether the record should be flushed to the
 * (output) tcp stream.  (This let's the package support batched or
 * pipelined procedure calls.)  TRUE => immmediate flush to tcp connection.
 */
bool_t
xdrrec_endofrecord (XDR * xdrs, bool_t sendnow)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);
  u_long len;                   /* fragment length */

  if (sendnow || rstrm->frag_sent ||
      ((u_long) rstrm->out_finger + sizeof (u_int32_t) >=
       (u_long) rstrm->out_boundry))
    {
      rstrm->frag_sent = FALSE;
      return (flush_out (rstrm, TRUE));
    }
  len = (u_long) (rstrm->out_finger) - (u_long) (rstrm->frag_header) -
    sizeof (u_int32_t);
  *(rstrm->frag_header) = htonl ((u_int32_t) len | LAST_FRAG);
  rstrm->frag_header = (u_int32_t *) (void *) rstrm->out_finger;
  rstrm->out_finger += sizeof (u_int32_t);
  return TRUE;
}

/*
 * Fill the stream buffer with a record for a non-blocking connection.
 * Return true if a record is available in the buffer, false if not.
 */
bool_t
__xdrrec_getrec (XDR * xdrs, enum xprt_stat * statp, bool_t expectdata)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);
  ssize_t n;
  int fraglen;

  if (!rstrm->in_haveheader)
    {
      n = rstrm->readit (rstrm->tcp_handle, rstrm->in_hdrp,
                         (int) sizeof (rstrm->in_header) - rstrm->in_hdrlen);
      if (n == 0)
        {
          *statp = expectdata ? XPRT_DIED : XPRT_IDLE;
          return FALSE;
        }
      if (n < 0)
        {
          *statp = XPRT_DIED;
          return FALSE;
        }
      rstrm->in_hdrp += n;
      rstrm->in_hdrlen += n;
      if (rstrm->in_hdrlen < sizeof (rstrm->in_header))
        {
          *statp = XPRT_MOREREQS;
          return FALSE;
        }
      rstrm->in_header = ntohl (rstrm->in_header);
      fraglen = (int) (rstrm->in_header & ~LAST_FRAG);
      if (fraglen == 0 || fraglen > rstrm->in_maxrec ||
          (rstrm->in_reclen + fraglen) > rstrm->in_maxrec)
        {
          *statp = XPRT_DIED;
          return FALSE;
        }
      rstrm->in_reclen += fraglen;
      if (rstrm->in_reclen > (int)rstrm->recvsize) /* guaranteed recvsize < INT_MAX */
        realloc_stream (rstrm, rstrm->in_reclen);
      if (rstrm->in_header & LAST_FRAG)
        {
          rstrm->in_header &= ~LAST_FRAG;
          rstrm->last_frag = TRUE;
        }
      /*
       * We can only reasonably expect to read once from a
       * non-blocking stream. Reading the fragment header
       * may have drained the stream.
       */
      expectdata = FALSE;
    }

  n = rstrm->readit (rstrm->tcp_handle,
                     rstrm->in_base + rstrm->in_received,
                     (rstrm->in_reclen - rstrm->in_received));

  if (n < 0)
    {
      *statp = XPRT_DIED;
      return FALSE;
    }

  if (n == 0)
    {
      *statp = expectdata ? XPRT_DIED : XPRT_IDLE;
      return FALSE;
    }

  rstrm->in_received += n;

  if (rstrm->in_received == rstrm->in_reclen)
    {
      rstrm->in_haveheader = FALSE;
      rstrm->in_hdrp = (char *) (void *) &rstrm->in_header;
      rstrm->in_hdrlen = 0;
      if (rstrm->last_frag)
        {
          rstrm->fbtbc = rstrm->in_reclen;
          rstrm->in_boundry = rstrm->in_base + rstrm->in_reclen;
          rstrm->in_finger = rstrm->in_base;
          rstrm->in_reclen = rstrm->in_received = 0;
          *statp = XPRT_MOREREQS;
          return TRUE;
        }
    }

  *statp = XPRT_MOREREQS;
  return FALSE;
}

bool_t
__xdrrec_setnonblock (XDR * xdrs, int maxrec)
{
  RECSTREAM *rstrm = (RECSTREAM *) (xdrs->x_private);

  rstrm->nonblock = TRUE;
  if (maxrec == 0)
    maxrec = rstrm->recvsize;
  rstrm->in_maxrec = maxrec;
  return TRUE;
}

/*
 * Internal useful routines
 */
static bool_t
flush_out (RECSTREAM * rstrm, bool_t eor)
{
  u_int32_t eormask = (eor == TRUE) ? LAST_FRAG : 0;
  u_int32_t len = (u_int32_t) ((u_long) (rstrm->out_finger) -
                               (u_long) (rstrm->frag_header) -
                               sizeof (u_int32_t));

  *(rstrm->frag_header) = htonl (len | eormask);
  len = (u_int32_t) ((u_long) (rstrm->out_finger) -
                     (u_long) (rstrm->out_base));
  if ((*(rstrm->writeit)) (rstrm->tcp_handle, rstrm->out_base, (int) len)
      != (int) len)
    return FALSE;
  rstrm->frag_header = (u_int32_t *) (void *) rstrm->out_base;
  rstrm->out_finger = (char *) rstrm->out_base + sizeof (u_int32_t);
  return TRUE;
}

static bool_t                   /* knows nothing about records!  Only about input buffers */
fill_input_buf (RECSTREAM * rstrm)
{
  char *where;
  u_int32_t i;
  int len;

  if (rstrm->nonblock)
    return FALSE;

  where = rstrm->in_base;
  i = (u_int32_t) ((u_long) rstrm->in_boundry % BYTES_PER_XDR_UNIT);
  where += i;
  len = (u_int32_t) (rstrm->in_size - i);
  if ((len = (*(rstrm->readit)) (rstrm->tcp_handle, where, len)) == -1)
    return FALSE;
  rstrm->in_finger = where;
  where += len;
  rstrm->in_boundry = where;
  return TRUE;
}

static bool_t                   /* knows nothing about records!  Only about input buffers */
get_input_bytes (RECSTREAM * rstrm, char *addr, size_t len)
{
  size_t current;

  if (rstrm->nonblock)
    {
      if ((rstrm->in_boundry < rstrm->in_finger) ||               /* <-- should never happen, but avoids... */
         (len > (size_t) (rstrm->in_boundry - rstrm->in_finger))) /* <-- signed/unsigned comparison */
        return FALSE;
      memcpy (addr, rstrm->in_finger, (size_t) len);
      rstrm->in_finger += len;
      return TRUE;
    }

  while (len > 0)
    {
      current = (size_t) ((long) rstrm->in_boundry - (long) rstrm->in_finger);
      if (current == 0)
        {
          if (!fill_input_buf (rstrm))
            return FALSE;
          continue;
        }
      current = (len < current) ? len : current;
      memmove (addr, rstrm->in_finger, current);
      rstrm->in_finger += current;
      addr += current;
      len -= current;
    }
  return TRUE;
}

static bool_t                   /* next two bytes of the input stream are treated as a header */
set_input_fragment (RECSTREAM * rstrm)
{
  u_int32_t header;

  if (rstrm->nonblock)
    return FALSE;
  if (!get_input_bytes (rstrm, (char *) (void *) &header, sizeof (header)))
    return FALSE;
  header = ntohl (header);
  rstrm->last_frag = ((header & LAST_FRAG) == 0) ? FALSE : TRUE;
  /*
   * Sanity check. Try not to accept wildly incorrect
   * record sizes. Unfortunately, the only record size
   * we can positively identify as being 'wildly incorrect'
   * is zero. Ridiculously large record sizes may look wrong,
   * but we don't have any way to be certain that they aren't
   * what the client actually intended to send us.
   */
  if (header == 0)
    return FALSE;
  rstrm->fbtbc = header & (~LAST_FRAG);
  return TRUE;
}

static bool_t                   /* consumes input bytes; knows nothing about records! */
skip_input_bytes (RECSTREAM * rstrm, long cnt)
{
  size_t current;

  while (cnt > 0)
    {
      current = (size_t) ((long) rstrm->in_boundry - (long) rstrm->in_finger);
      if (current == 0)
        {
          if (!fill_input_buf (rstrm))
            return FALSE;
          continue;
        }
      /* in this loop (prior to last line), cnt > 0 so size_t cast is safe*/
      current = (size_t) (((size_t)cnt < current) ? (size_t)cnt : current);
      rstrm->in_finger += current;
      cnt -= current;
    }
  return TRUE;
}

static u_int
fix_buf_size (u_int s)
{

  if (s < 100)
    s = 4000;
  return (RNDUP (s));
}

/*
 * Reallocate the input buffer for a non-block stream.
 */
static bool_t
realloc_stream (RECSTREAM * rstrm, int size)
{
  ptrdiff_t diff;
  char *buf;
  char *buf_algn;

  if (size > (int)rstrm->recvsize) /* recvsize guaranteed < INT_MAX */
    {
      buf = realloc (rstrm->in_buffer, (size_t) (size + BYTES_PER_XDR_UNIT));
      if (buf == NULL)
        return FALSE;
      for (buf_algn = buf;
           (long) buf_algn % BYTES_PER_XDR_UNIT != 0; buf_algn++)
        ;
      diff = buf_algn - rstrm->in_base;
      rstrm->in_finger += diff;
      rstrm->in_base = buf_algn;
      rstrm->in_buffer = buf;
      rstrm->in_boundry = buf_algn + size;
      rstrm->recvsize = size;
      rstrm->in_size = size;
    }

  return TRUE;
}

