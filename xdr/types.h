
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
 *
 *        from: @(#)types.h 1.18 87/07/24 SMI
 *        from: @(#)types.h        2.3 88/08/15 4.0 RPCSRC
 *        $FreeBSD: src/include/rpc/types.h,v 1.10.6.1 2003/12/18 00:59:50 peter Exp $
 *        $NetBSD: types.h,v 1.13 2000/06/13 01:02:44 thorpej Exp $
 */

/*
 * Rpc additions to <sys/types.h>
 */
#ifndef _RPC_TYPES_H
#define _RPC_TYPES_H

#include <stdint.h>
#include <sys/types.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__MINGW32__)
/* mingw does not define these types anywhere */
typedef uint8_t   u_int8_t;
typedef uint16_t  u_int16_t;
typedef uint32_t  u_int32_t;
typedef uint64_t  u_int64_t;
typedef char     *caddr_t;
#endif /* __MINGW32__ */

#ifdef _MSC_VER
/* MSVC does not define these types anywhere */
typedef __int8            int8_t;
typedef __int16           int16_t;
typedef __int32           int32_t;
typedef __int64           int64_t;
typedef unsigned __int8   u_int8_t;
typedef unsigned __int16  u_int16_t;
typedef unsigned __int32  u_int32_t;
typedef unsigned __int64  u_int64_t;
typedef char             *caddr_t;
typedef long              ssize_t;
#endif /* _MSC_VER */

#ifndef _BSDTYPES_DEFINED
typedef unsigned char  u_char;
typedef unsigned short u_short;
typedef unsigned int   u_int;
typedef unsigned long  u_long;
# define _BSDTYPES_DEFINED
#endif /* not _BSDTYPES_DEFINED */

typedef u_int64_t u_quad_t;
typedef int64_t   quad_t;
typedef int32_t   bool_t;
typedef int32_t   enum_t;


#ifndef NULL
# define NULL 0
#endif
#define __dontcare__ -1

#ifndef FALSE
# define FALSE 0
#endif
#ifndef TRUE
# define TRUE 1
#endif

#define mem_alloc(bsize)        calloc(1, bsize)
#define mem_free(ptr, bsize)    free(ptr)

#ifdef __cplusplus
}
#endif

/* byteswap and ntohl stuff */
#if defined(__MINGW32__)
/* Fortunately, the ntohl/htonl/ntohs/htons functions do NOT
   require that the winsock DLL is initialized with the WSAStartup
   functon, so they are safe to use by any caller. However, we
   declare (slow) versions of the bswap functions just in case. */
# include <winsock2.h>
# define bswap_16(x) ((((x) & 0x00FF) << 8) | \
                      (((x) & 0xFF00) >> 8))
# define bswap_32(x) ((((x) & 0x000000FF) << 24) | \
                      (((x) & 0x0000FF00) << 8) | \
                      (((x) & 0x00FF0000) << 8) | \
                      (((x) & 0xFF000000) >> 24))
# define bswap_64(x) ((((x) & 0x00000000000000FFULL) << 56) | \
                      (((x) & 0x000000000000FF00ULL) << 40) | \
                      (((x) & 0x0000000000FF0000ULL) << 24) | \
                      (((x) & 0x00000000FF000000ULL) << 8) | \
                      (((x) & 0x000000FF00000000ULL) >> 8) | \
                      (((x) & 0x0000FF0000000000ULL) >> 24) | \
                      (((x) & 0x00FF000000000000ULL) >> 40) | \
                      (((x) & 0xFF00000000000000ULL) >> 56))
#elif defined(_MSC_VER)
/* Fortunately, the ntohl/htonl/ntohs/htons functions do NOT
   require that the winsock DLL is initialized with the WSAStartup
   functon, so they are safe to use by any caller. However, we
   declare (slow) versions of the bswap functions just in case. */
# include <winsock2.h>
# define bswap_16(x) ((((x) & 0x00FFui16) << 8) | \
                      (((x) & 0xFF00ui16) >> 8))
# define bswap_32(x) ((((x) & 0x000000FFui32) << 24) | \
                      (((x) & 0x0000FF00ui32) << 8) | \
                      (((x) & 0x00FF0000ui32) << 8) | \
                      (((x) & 0xFF000000ui32) >> 24))
# define bswap_64(x) ((((x) & 0x00000000000000FFui64) << 56) | \
                      (((x) & 0x000000000000FF00ui64) << 40) | \
                      (((x) & 0x0000000000FF0000ui64) << 24) | \
                      (((x) & 0x00000000FF000000ui64) << 8) | \
                      (((x) & 0x000000FF00000000ui64) >> 8) | \
                      (((x) & 0x0000FF0000000000ui64) >> 24) | \
                      (((x) & 0x00FF000000000000ui64) >> 40) | \
                      (((x) & 0xFF00000000000000ui64) >> 56))
#else /* not __MINGW32__ and not _MSC_VER */
# include <byteswap.h>
# include <arpa/inet.h>
#endif /* not __MINGW32__ and not _MSC_VER */

#endif /* !_RPC_TYPES_H */
