/*
 Arcan Shared Memory Interface

 Copyright (c) 2014-2017, Bjorn Stahl
 All rights reserved.

 Redistribution and use in source and binary forms,
 with or without modification, are permitted provided that the
 following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
 this list of conditions and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright notice,
 this list of conditions and the following disclaimer in the documentation
 and/or other materials provided with the distribution.

 3. Neither the name of the copyright holder nor the names of its contributors
 may be used to endorse or promote products derived from this software without
 specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 THE POSSIBILITY OF SUCH DAMAGE.
*/

#ifndef HAVE_ARCAN_SHMIF
#define HAVE_ARCAN_SHMIF

/*
 * This header pulls in all needed standard library headers, if that is
 * undesired, hand-pick the individual ones that are needed or disable
 * this toggle
 */

#if !defined(ARCAN_SHMIF_NO_STDHDR) && !defined(__cplusplus)
#include <limits.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <unistd.h>
#include <string.h>
#endif

/*
 * Hide the memory page automatically for C++, this should be set for C
 * as well when we ween all programs away from accessing the structure
 * directly.
 */
#ifdef __cplusplus
#define ARCAN_SHMIF_HIDEPAGE
#endif

#include "arcan_shmif_interop.h"
#include "arcan_shmif_event.h"
#include "arcan_shmif_control.h"
#include "arcan_shmif_defs.h"

#ifndef __cplusplus
#include "arcan_shmif_sub.h"
#endif

#endif
