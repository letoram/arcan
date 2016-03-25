/*
 * Copyright (c) 2016, NVIDIA CORPORATION. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

#include "utils.h"

#include <stdio.h>
#include <stdarg.h>
#include <unistd.h>
#include <string.h>
#include <stdlib.h>
#include <ctype.h>
#include <sys/time.h>


void Fatal(const char *format, ...)
{
    va_list ap;

    fprintf(stderr, "ERROR: ");

    va_start(ap, format);
    vfprintf(stderr, format, ap);
    va_end(ap);

    exit(1);
}


double GetTime(void)
{
    struct timeval tv;
    struct timezone tz;

    gettimeofday(&tv, &tz);
    return (tv.tv_sec) + (tv.tv_usec / 1000000.0);
}


void PrintFps(void)
{
    static int frames = 0;
    static double startTime = -1;
    double seconds, currentTime = GetTime();

    if (startTime < 0) {
        startTime = currentTime;
    }

    frames++;

    seconds = currentTime - startTime;

    if (seconds > 5.0) {
        double fps = frames / seconds;
        printf("%d frames in %3.1f seconds = %6.3f FPS\n",
               frames, seconds, fps);
        fflush(stdout);
        startTime = currentTime;
        frames = 0;
    }
}


/*
 * Check if 'extension' is present in 'extensionString'.  Note that
 * strstr(3) by itself is not sufficient; see:
 *
 * http://www.opengl.org/registry/doc/rules.html#using
 */
EGLBoolean ExtensionIsSupported(const char *extensionString,
                                const char *extension)
{
    const char *endOfExtensionString;
    const char *currentExtension = extensionString;
    size_t extensionLength;

    if ((extensionString == NULL) || (extension == NULL)) {
        return EGL_FALSE;
    }

    extensionLength = strlen(extension);

    endOfExtensionString = extensionString + strlen(extensionString);

    while (currentExtension < endOfExtensionString) {
        const size_t currentExtensionLength = strcspn(currentExtension, " ");
        if ((extensionLength == currentExtensionLength) &&
            (strncmp(extension, currentExtension,
                     extensionLength) == 0)) {
            return EGL_TRUE;
        }
        currentExtension += (currentExtensionLength + 1);
    }
    return EGL_FALSE;
}


static void *GetProcAddress(const char *functionName)
{
    void *ptr = (void *) eglGetProcAddress(functionName);

    if (ptr == NULL) {
        Fatal("eglGetProcAddress(%s) failed.\n", functionName);
    }

    return ptr;
}


PFNEGLQUERYDEVICESEXTPROC pEglQueryDevicesEXT = NULL;
PFNEGLQUERYDEVICESTRINGEXTPROC pEglQueryDeviceStringEXT = NULL;
PFNEGLGETPLATFORMDISPLAYEXTPROC pEglGetPlatformDisplayEXT = NULL;
PFNEGLGETOUTPUTLAYERSEXTPROC pEglGetOutputLayersEXT = NULL;
PFNEGLCREATESTREAMKHRPROC pEglCreateStreamKHR = NULL;
PFNEGLSTREAMCONSUMEROUTPUTEXTPROC pEglStreamConsumerOutputEXT = NULL;
PFNEGLCREATESTREAMPRODUCERSURFACEKHRPROC pEglCreateStreamProducerSurfaceKHR = NULL;

void GetEglExtensionFunctionPointers(void)
{
    pEglQueryDevicesEXT = (PFNEGLQUERYDEVICESEXTPROC)
        GetProcAddress("eglQueryDevicesEXT");

    pEglQueryDeviceStringEXT = (PFNEGLQUERYDEVICESTRINGEXTPROC)
        GetProcAddress("eglQueryDeviceStringEXT");

    pEglGetPlatformDisplayEXT = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
        GetProcAddress("eglGetPlatformDisplayEXT");

    pEglGetOutputLayersEXT = (PFNEGLGETOUTPUTLAYERSEXTPROC)
        GetProcAddress("eglGetOutputLayersEXT");

    pEglCreateStreamKHR = (PFNEGLCREATESTREAMKHRPROC)
        GetProcAddress("eglCreateStreamKHR");

    pEglStreamConsumerOutputEXT = (PFNEGLSTREAMCONSUMEROUTPUTEXTPROC)
        GetProcAddress("eglStreamConsumerOutputEXT");

    pEglCreateStreamProducerSurfaceKHR = (PFNEGLCREATESTREAMPRODUCERSURFACEKHRPROC)
        GetProcAddress("eglCreateStreamProducerSurfaceKHR");
}
