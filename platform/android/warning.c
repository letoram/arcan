/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#include <stdlib.h>
#include <stdint.h>
#include <stdio.h>
#include <stdarg.h>

#include <android/log.h>

void arcan_fatal(const char* msg, ...)
{
	char buf[256] = {0};

	va_list args;
	va_start(args, msg );
	vsnprintf(buf, 255, msg, args);
	va_end(args);

	__android_log_print(ANDROID_LOG_DEBUG, "ALE", "%s", buf);
#ifdef DEBUG
	abort();
#else
	exit(0);
#endif
}

void arcan_warning(const char* msg, ...)
{
	char buf[256] = {0};

	va_list args;
	va_start(args, msg );
	vsnprintf(buf, 255, msg, args);
	va_end(args);

	__android_log_print(ANDROID_LOG_DEBUG, "ALE", "%s", buf); 
}
