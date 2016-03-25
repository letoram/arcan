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

#if !defined(UTILS_H)
#define UTILS_H

#include <EGL/egl.h>
#include <EGL/eglext.h>

#define ARRAY_LEN(_arr) (sizeof(_arr) / sizeof(_arr[0]))

void Fatal(const char *format, ...);

double GetTime(void);
void PrintFps(void);

EGLBoolean ExtensionIsSupported(
    const char *extensionString,
    const char *extension);

void GetEglExtensionFunctionPointers(void);

extern PFNEGLQUERYDEVICESEXTPROC pEglQueryDevicesEXT;
extern PFNEGLQUERYDEVICESTRINGEXTPROC pEglQueryDeviceStringEXT;
extern PFNEGLGETPLATFORMDISPLAYEXTPROC pEglGetPlatformDisplayEXT;
extern PFNEGLGETOUTPUTLAYERSEXTPROC pEglGetOutputLayersEXT;
extern PFNEGLCREATESTREAMKHRPROC pEglCreateStreamKHR;
extern PFNEGLSTREAMCONSUMEROUTPUTEXTPROC pEglStreamConsumerOutputEXT;
extern PFNEGLCREATESTREAMPRODUCERSURFACEKHRPROC pEglCreateStreamProducerSurfaceKHR;

#endif /* UTILS_H */
