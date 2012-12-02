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

#ifndef _HAVE_ARCAN_TARGET_CONST
#define _HAVE_ARCAN_TARGET_CONST

/* different supported intercept mechanisms,
 * with the shared goal of getting control of the
 * IO Event, Audio / Video processing of the subject in order to make IT a hidden / background
 * processing, piping all the relevant rendering data back to the frontend.

 * PRELOAD means using a PRELOAD facility (LD_PRELOAD, DYLD_INSERT_LIBRARIES, ...) to achieve control
 * over key functions of the rendering process of the target.
 *
 * PTRACE_TRAMPOLINE uses the Ptrace facility of the OS to inject code into the process space of
 * the target.
 *
 * COOPERATIVE means that the target is already ready (from plugins, patched target, whatever) to
 * treat data in the way required */
enum intercept_mechanism {
	INTERCEPT_PRELOAD = 0,
	INTERCEPT_PTRACE_TRAMPOLINE = 1,
	INTERCEPT_COOPERATIVE = 2
};

enum intercept_mode {
	INTERCEPT_VIDEO = 1,
	INTERCEPT_AUDIO = 2,
	INTERCEPT_INPUT = 4
};

enum communication_mode {
	COM_PIPE   = 0,
	COM_SOCKET = 1,
	COM_SHM    = 2
};

enum command_subtypes {
	TYPE_KEYBOARD = 0,
	TYPE_MOUSE = 1,
	TYPE_JOYSTICK = 2
};

/* Default file-descriptor IDs
 * for communicating to/from hijacked target */
#define VID_FD 3
#define AUD_FD 4
#define CTRL_FD 5
#define COMM_FD 6

enum target_commands {
	TF_GFLAGS = 0,
	TF_AGAIN,
	TF_EVENT,
	TF_READY,
	TF_SLEEP,
	TF_WAKE
};

#endif
