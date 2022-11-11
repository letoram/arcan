/*
 * libtsm - Unicode Handling
 *
 * Copyright (c) 2011-2013 David Herrmann <dh.herrmann@gmail.com>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files
 * (the "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

/*
 * The tsm-utf8-state-machine is based on the wayland-compositor demos:
 *
 * Copyright © 2008 Kristian Høgsberg
 *
 * Permission to use, copy, modify, distribute, and sell this software and
 * its documentation for any purpose is hereby granted without fee, provided
 * that the above copyright notice appear in all copies and that both that
 * copyright notice and this permission notice appear in supporting
 * documentation, and that the name of the copyright holders not be used in
 * advertising or publicity pertaining to distribution of the software
 * without specific, written prior permission.  The copyright holders make
 * no representations about the suitability of this software for any
 * purpose.  It is provided "as is" without express or implied warranty.
 *
 * THE COPYRIGHT HOLDERS DISCLAIM ALL WARRANTIES WITH REGARD TO THIS
 * SOFTWARE, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
 * FITNESS, IN NO EVENT SHALL THE COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * SPECIAL, INDIRECT OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER
 * RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF
 * CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
 * CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

/*
 * Unicode Helpers
 * This implements several helpers for Unicode/UTF8/UCS4 input and output. See
 * below for comments on each helper.
 */

#include <errno.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include "wcwidth.h"
#include "arcan_shmif.h"
#include "arcan_tui.h"
#include "arcan_tuisym.h"
#include "libtsm.h"
#include "libtsm_int.h"
#include "shl_array.h"
#include "shl_htable.h"

/*
 * Unicode Symbol Handling
 * The main goal of the tsm_symbol_* functions is to provide a datatype which
 * can contain the representation of any printable character. This includes all
 * basic Unicode characters but also combined characters.
 * To avoid all the memory management we still represent a character as a single
 * integer value (tsm_symbol_t) but internally we allocate a string which is
 * represented by this value.
 *
 * A tsm_symbol_t is an integer which represents a single character point.
 * For most Unicode characters this is simply the UCS4 representation. In fact,
 * every UCS4 characters is a valid tsm_symbol_t object.
 * However, Unicode standard allows combining marks. Therefore, some characters
 * consists of more than one Unicode character.
 * A global symbol-table provides all those combined characters as single
 * integers. You simply create a valid base character and append your combining
 * marks and the table will return a new valid tsm_symbol_t. It is no longer
 * a valid UCS4 value, though. But no memory management is needed as all
 * tsm_symbol_t objects are simple integers.
 *
 * The symbol table contains two-way
 * references. The Hash Table contains all the symbols with the symbol ucs4
 * string as key and the symbol ID as value.
 * The index array contains the symbol ID as key and a pointer to the ucs4
 * string as value. But the hash table owns the ucs4 string.
 * This allows fast implementations of *_get() and *_append() without long
 * search intervals.
 *
 * When creating a new symbol, we simply return the UCS4 value as new symbol. We
 * do not add it to our symbol table as it is only one character. However, if a
 * character is appended to an existing symbol, we create a new ucs4 string and
 * push the new symbol into the symbol table.
 */

const tsm_symbol_t tsm_symbol_default = 0;

struct tsm_symbol_table {
	unsigned long ref;
	uint32_t next_id;
	struct shl_array *index;
	struct shl_htable symbols;
};

static size_t hash_ucs4(const void *key, void *priv)
{
	size_t i, val = 5381;
	const uint32_t *ucs4 = key;

	for (i = 0; ucs4[i] <= TSM_UCS4_MAX; ++i)
		val = val * 33 + ucs4[i];

	return val;
}

static bool cmp_ucs4(const void *a, const void *b)
{
	size_t i;
	const uint32_t *v1, *v2;

	v1 = a;
	v2 = b;

	for (i = 0; ; ++i) {
		if (v1[i] > TSM_UCS4_MAX && v2[i] > TSM_UCS4_MAX)
			return true;
		if (v1[i] != v2[i])
			return false;
	}
}

static void free_ucs4(void *elem, void *priv)
{
	uint32_t *v = elem;

	/* key is prefix with actual value so pass correct pointer */
	free(--v);
}

int tsm_symbol_table_new(struct tsm_symbol_table **out)
{
	struct tsm_symbol_table *tbl;
	int ret;
	static const uint32_t *val = NULL; /* we need a valid lvalue */

	if (!out)
		return -EINVAL;

	tbl = malloc(sizeof(*tbl));
	if (!tbl)
		return -ENOMEM;
	memset(tbl, 0, sizeof(*tbl));
	tbl->ref = 1;
	tbl->next_id = TSM_UCS4_MAX + 2;
	shl_htable_init(&tbl->symbols, cmp_ucs4, hash_ucs4, NULL);

	ret = shl_array_new(&tbl->index, sizeof(uint32_t*), 4);
	if (ret)
		goto err_free;

	/* first entry is not used so add dummy */
	shl_array_push(tbl->index, &val);

	*out = tbl;
	return 0;

err_free:
	free(tbl);
	return ret;
}

void tsm_symbol_table_ref(struct tsm_symbol_table *tbl)
{
	if (!tbl || !tbl->ref)
		return;

	++tbl->ref;
}

void tsm_symbol_table_unref(struct tsm_symbol_table *tbl)
{
	if (!tbl || !tbl->ref || --tbl->ref)
		return;

	shl_htable_clear(&tbl->symbols, free_ucs4, NULL);
	shl_array_free(tbl->index);
	free(tbl);
}

tsm_symbol_t tsm_symbol_make(uint32_t ucs4)
{
	if (ucs4 > TSM_UCS4_MAX)
		return 0;
	else
		return ucs4;
}

/*
 * This decomposes a symbol into a ucs4 string and a size value. If \sym is a
 * valid UCS4 character, this returns a pointer to \sym and writes 1 into \size.
 * Therefore, the returned value may get destroyed if your \sym argument gets
 * destroyed.
 * If \sym is a composed ucs4 string, then the returned value points into the
 * hash table of the symbol table and lives as long as the symbol table does.
 *
 * This always returns a valid value. If an error happens, the default character
 * is returned. If \size is NULL, then the size value is omitted.
 */
const uint32_t *tsm_symbol_get(struct tsm_symbol_table *tbl,
			       tsm_symbol_t *sym, size_t *size)
{
	uint32_t *ucs4, idx;

	if (*sym <= TSM_UCS4_MAX) {
		if (size)
			*size = 1;
		return sym;
	}

	if (!tbl)
		return sym;

	idx = *sym - (TSM_UCS4_MAX + 1);
	if (idx >= shl_array_get_length(tbl->index))
		ucs4 = NULL;
	else
		ucs4 = *SHL_ARRAY_AT(tbl->index, uint32_t*, idx);

	if (!ucs4) {
		if (size)
			*size = 1;
		return &tsm_symbol_default;
	}

	if (size) {
		*size = 0;
		while (ucs4[*size] <= TSM_UCS4_MAX)
			++*size;
	}

	return ucs4;
}

tsm_symbol_t tsm_symbol_append(struct tsm_symbol_table *tbl,
			       tsm_symbol_t sym, uint32_t ucs4)
{
	uint32_t buf[TSM_UCS4_MAXLEN + 1], nsym, *nval;
	const uint32_t *ptr;
	size_t s;
	bool res;
	int ret;

	if (!tbl)
		return sym;

	if (ucs4 > TSM_UCS4_MAX)
		return sym;

	ptr = tsm_symbol_get(tbl, &sym, &s);
	if (s >= TSM_UCS4_MAXLEN)
		return sym;

	memcpy(buf, ptr, s * sizeof(uint32_t));
	buf[s++] = ucs4;
	buf[s++] = TSM_UCS4_MAX + 1;

	res = shl_htable_lookup(&tbl->symbols, buf, hash_ucs4(buf, NULL),
				(void**)&nval);
	if (res) {
		/* key is prefixed with actual value */
		return *--nval;
	}

	/* We save the key in nval and prefix it with the new ID. Note that
	 * the prefix is hidden, we actually store "++nval" in the htable. */
	nval = malloc(sizeof(uint32_t) * (s + 1));
	if (!nval)
		return sym;

	++nval;
	memcpy(nval, buf, s * sizeof(uint32_t));

	nsym = tbl->next_id + 1;
	/* Out of IDs; we actually have 2 Billion IDs so this seems
	 * very unlikely but lets be safe here */
	if (nsym <= tbl->next_id++)
		goto err_id;

	/* store ID hidden before the key */
	*(nval - 1) = nsym;

	ret = shl_htable_insert(&tbl->symbols, nval, hash_ucs4(nval, NULL));
	if (ret)
		goto err_id;

	ret = shl_array_push(tbl->index, &nval);
	if (ret)
		goto err_symbol;

	return nsym;

err_symbol:
	shl_htable_remove(&tbl->symbols, nval, hash_ucs4(nval, NULL), NULL);
err_id:
	--tbl->next_id;
	free(nval);
	return sym;
}

unsigned int tsm_symbol_get_width(struct tsm_symbol_table *tbl,
				  tsm_symbol_t sym)
{
	const uint32_t *ch;
	size_t len;

	if (!tbl)
		return 0;

	ch = tsm_symbol_get(tbl, &sym, &len);
	if (len == 0)
		return 0;

	return tsm_ucs4_get_width(*ch);
}

/*
 * Convert UCS4 character to UTF-8. This creates one of:
 *   0xxxxxxx
 *   110xxxxx 10xxxxxx
 *   1110xxxx 10xxxxxx 10xxxxxx
 *   11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
 * This is based on the same function from "terminology" from the Enlightenment
 * project. See COPYING for more information.
 *
 * @txt must point to a 4 byte-buffer. A number between 0 and 4 is returned and
 * indicates how long the written UTF8 string is.
 *
 * Please note @g is a real UCS4 code and not a tsm_symbol_t object!
 *
 * Unicode symbols between 0xD800 and 0xDFFF are not assigned and reserved for
 * UTF16 compatibility. It is an error to encode them. Same applies to numbers
 * greater than 0x10FFFF, the range 0xFDD0-0xFDEF and codepoints ending with
 * 0xFFFF or 0xFFFE.
 */

SHL_EXPORT
unsigned int tsm_ucs4_get_width(uint32_t ucs4)
{
	int ret;

	ret = mk_wcwidth(ucs4);
	if (ret <= 0)
		return 0;

	return ret;
}

SHL_EXPORT
size_t tsm_ucs4_to_utf8(uint32_t g, char *txt)
{
	if (g >= 0xd800 && g <= 0xdfff)
		return 0;
	if (g > 0x10ffff || (g & 0xffff) == 0xffff || (g & 0xffff) == 0xfffe)
		return 0;
	if (g >= 0xfdd0 && g <= 0xfdef)
		return 0;

	if (g < (1 << 7)) {
		txt[0] = g & 0x7f;
		return 1;
	} else if (g < (1 << (5 + 6))) {
		txt[0] = 0xc0 | ((g >> 6) & 0x1f);
		txt[1] = 0x80 | ((g     ) & 0x3f);
		return 2;
	} else if (g < (1 << (4 + 6 + 6))) {
		txt[0] = 0xe0 | ((g >> 12) & 0x0f);
		txt[1] = 0x80 | ((g >>  6) & 0x3f);
		txt[2] = 0x80 | ((g      ) & 0x3f);
		return 3;
	} else if (g < (1 << (3 + 6 + 6 + 6))) {
		txt[0] = 0xf0 | ((g >> 18) & 0x07);
		txt[1] = 0x80 | ((g >> 12) & 0x3f);
		txt[2] = 0x80 | ((g >>  6) & 0x3f);
		txt[3] = 0x80 | ((g      ) & 0x3f);
		return 4;
	} else {
		return 0;
	}
}

SHL_EXPORT
char *tsm_ucs4_to_utf8_alloc(const uint32_t *ucs4, size_t len, size_t *len_out)
{
	char *val;
	size_t i, pos;

	val = malloc(4 * len);
	if (!val)
		return NULL;

	pos = 0;
	for (i = 0; i < len; ++i)
		pos += tsm_ucs4_to_utf8(ucs4[i], &val[pos]);

	if (!pos) {
		free(val);
		return NULL;
	}

	if (len_out)
		*len_out = pos;
	return val;
}

/*
 * UTF8 State Machine
 * This state machine parses UTF8 and converts it into a stream of Unicode
 * characters (UCS4 values). A state-machine is represented by a
 * "struct tsm_utf8_mach" object. It has no global state and all functions are
 * re-entrant if called with different state-machine objects.
 *
 * tsm_utf8_mach_new(): This creates a new state-machine and resets it to its
 * initial state. Returns 0 on success.
 *
 * tsm_uft8_mach_free(): This destroys a state-machine and frees all internally
 * allocated memory.
 *
 * tsm_utf8_mach_reset(): Reset a given state-machine to its initial state. This
 * is the same state the machine is in after it got created.
 *
 * tsm_uft8_mach_feed(): Feed one byte of the UTF8 input stream into the
 * state-machine. This function returns the new state of the state-machine after
 * this character has been parsed. If it is TSM_UTF8_ACCEPT or TSM_UTF8_REJECT,
 * then there is a pending UCS4 character that you should retrieve via
 * tsm_utf8_mach_get(). If it is TSM_UTF8_ACCEPT, then a character was
 * successfully parsed. If it is TSM_UTF8_REJECT, the input was invalid UTF8 and
 * some error recovery was tried or a replacement character was choosen. All
 * other states mean that the machine needs more input to parse the stream.
 *
 * tsm_utf8_mach_get(): Returns the last parsed character. It has no effect on
 * the state machine so you can call it multiple times.
 *
 * Internally, we use TSM_UTF8_START whenever the state-machine is reset. This
 * can be used to ignore the last read input or to simply reset the machine.
 * TSM_UTF8_EXPECT* is used to remember how many bytes are still to be read to
 * get a full UTF8 sequence.
 * If an error occurs during reading, we go to state TSM_UTF8_REJECT and the
 * user will read a replacement character. If further errors occur, we go to
 * state TSM_UTF8_START to avoid printing multiple replacement characters for a
 * single misinterpreted UTF8 sequence. However, under some circumstances it may
 * happen that we stay in TSM_UTF8_REJECT and a next replacement character is
 * returned.
 * It is difficult to decide how to interpret wrong input but this machine seems
 * to be quite good at deciding what to do. Generally, we prefer discarding or
 * replacing input instead of trying to decipher ASCII values from the invalid
 * data. This guarantees that we do not send wrong values to the terminal
 * emulator. Some might argue that an ASCII fallback would be better. However,
 * this means that we might send very weird escape-sequences to the VTE layer.
 * Especially with C1 codes applications can really break many terminal features
 * so we avoid any non-ASCII+non-UTF8 input to prevent this.
 */

struct tsm_utf8_mach {
	int state;
	uint32_t ch;
};

int tsm_utf8_mach_new(struct tsm_utf8_mach **out)
{
	struct tsm_utf8_mach *mach;

	if (!out)
		return -EINVAL;

	mach = malloc(sizeof(*mach));
	if (!mach)
		return -ENOMEM;

	memset(mach, 0, sizeof(*mach));
	mach->state = TSM_UTF8_START;

	*out = mach;
	return 0;
}

void tsm_utf8_mach_free(struct tsm_utf8_mach *mach)
{
	if (!mach)
		return;

	free(mach);
}

int tsm_utf8_mach_feed(struct tsm_utf8_mach *mach, char ci)
{
	uint32_t c;

	if (!mach)
		return TSM_UTF8_START;

	c = ci;

	switch (mach->state) {
	case TSM_UTF8_START:
	case TSM_UTF8_ACCEPT:
	case TSM_UTF8_REJECT:
		if (c == 0xC0 || c == 0xC1) {
			/* overlong encoding for ASCII, reject */
			mach->state = TSM_UTF8_REJECT;
		} else if ((c & 0x80) == 0) {
			/* single byte, accept */
			mach->ch = c;
			mach->state = TSM_UTF8_ACCEPT;
		} else if ((c & 0xC0) == 0x80) {
			/* parser out of sync, ignore byte */
			mach->state = TSM_UTF8_START;
		} else if ((c & 0xE0) == 0xC0) {
			/* start of two byte sequence */
			mach->ch = (c & 0x1F) << 6;
			mach->state = TSM_UTF8_EXPECT1;
		} else if ((c & 0xF0) == 0xE0) {
			/* start of three byte sequence */
			mach->ch = (c & 0x0F) << 12;
			mach->state = TSM_UTF8_EXPECT2;
		} else if ((c & 0xF8) == 0xF0) {
			/* start of four byte sequence */
			mach->ch = (c & 0x07) << 18;
			mach->state = TSM_UTF8_EXPECT3;
		} else {
			/* overlong encoding, reject */
			mach->state = TSM_UTF8_REJECT;
		}
		break;
	case TSM_UTF8_EXPECT3:
		mach->ch |= (c & 0x3F) << 12;
		if ((c & 0xC0) == 0x80)
			mach->state = TSM_UTF8_EXPECT2;
		else
			mach->state = TSM_UTF8_REJECT;
		break;
	case TSM_UTF8_EXPECT2:
		mach->ch |= (c & 0x3F) << 6;
		if ((c & 0xC0) == 0x80)
			mach->state = TSM_UTF8_EXPECT1;
		else
			mach->state = TSM_UTF8_REJECT;
		break;
	case TSM_UTF8_EXPECT1:
		mach->ch |= c & 0x3F;
		if ((c & 0xC0) == 0x80)
			mach->state = TSM_UTF8_ACCEPT;
		else
			mach->state = TSM_UTF8_REJECT;
		break;
	default:
		mach->state = TSM_UTF8_REJECT;
		break;
	}

	return mach->state;
}

uint32_t tsm_utf8_mach_get(struct tsm_utf8_mach *mach)
{
	if (!mach || mach->state != TSM_UTF8_ACCEPT)
		return TSM_UCS4_REPLACEMENT;

	return mach->ch;
}

void tsm_utf8_mach_reset(struct tsm_utf8_mach *mach)
{
	if (!mach)
		return;

	mach->state = TSM_UTF8_START;
}
