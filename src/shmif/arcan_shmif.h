/*
 Arcan Shared Memory Interface

 Copyright (c) 2014-2015, Bjorn Stahl
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

#ifndef _HAVE_ARCAN_SHMIF
#define _HAVE_ARCAN_SHMIF

/*
 * plucked from platform.h in arcan platform tree in order to
 * provide the defines for external projects that just uses the
 * installed shmif- library
 */

#ifndef PLATFORM_HEADER
#include <stdint.h>
#include <stdbool.h>
#ifdef WIN32
	typedef HANDLE file_handle;
	typedef HANDLE sem_handle;
	typedef void* process_handle;
#else
#include <sys/types.h>
#include <sys/stat.h>
#include <semaphore.h>
	typedef int file_handle;
	typedef pid_t process_handle;
	typedef sem_t* sem_handle;
#endif
#endif

#include "arcan_shmif_interop.h"
#include "arcan_shmif_event.h"
#include "arcan_shmif_control.h"

#endif
