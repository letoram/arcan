/*		 
 * Copyright (C) 2014 Sebastiano Vigna 
 *
 *  This program is free software; you can redistribute it and/or modify it
 *  under the terms of the GNU General Public License as published by the Free
 *  Software Foundation; either version 3 of the License, or (at your option)
 *  any later version.
 *
 *  This program is distributed in the hope that it will be useful, but
 *  WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 *  or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 *  for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, see <http://www.gnu.org/licenses/>.
 *
 *  Found at https://prng.di.unimi.it/harness.c 
 */

#include <stdio.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdlib.h>
#include <assert.h>
#include <stdbool.h>
#include <sys/time.h>
#include <sys/resource.h>

#include <arcan_shmif.h>

#ifdef PAPI
#include <papi.h>
#endif

// This statement is executed, if necessary, to initialize the generator
#ifndef INIT
#define INIT
#endif

// This statement is executed at the end of the test
#ifndef TAIL
#define TAIL ;
#endif

// We measure this function
#ifndef NEXT
#define NEXT next()
#endif

extern void arcan_random(uint8_t* buf, size_t buf_sz);

#define buf_sz 8
union { uint64_t i; uint8_t buf[buf_sz]; } bytebuf; 

uint64_t next() {
	arcan_random(bytebuf.buf, buf_sz);
	return bytebuf.i;
}

uint64_t get_user_time(void) {
	struct rusage rusage;
	getrusage(0, &rusage);
	return rusage.ru_utime.tv_sec * 1000000000ULL + rusage.ru_utime.tv_usec * 1000ULL;
}

int main(int argc, char* argv[]) {
	if (argc != 2) {
		fprintf(stderr, "USAGE: %s ITERATIONS\n", argv[0]);
		exit(1);
	}
	const long long int n = strtoll(argv[1], NULL, 0);

	INIT // Here you can optionally inject initialization code

#ifdef BLOCK
	HEAD

	const uint64_t start_time = get_user_time();

	for(int64_t i = n; i-- != 0;) {
		NEXT; // Measurement + XOR
	}

	const uint64_t time_delta = (get_user_time() - start_time);
	printf("%s: %.03f s, %.03f GB/s, %.03f words/ns, %.03f ns/word\n", argv[0], time_delta / 1E9, (n * BLOCK * 8.) / time_delta, (n * BLOCK) / (double)time_delta, time_delta / (double)(n * BLOCK));
#else

#ifdef PAPI
	const uint64_t start_cycle = PAPI_get_real_cyc();
#else
	const uint64_t start_time = get_user_time();
#endif

	uint64_t e = -1;
#ifdef HARNESS_DOUBLE
	union { double d; uint64_t i; } uu;

	// next() returns a double
	for(int64_t i = n; i-- != 0;) {
		uu.d = NEXT; // Measurement
		// printf("%f\n", uu.d);
		e ^= uu.i;
	}
#else
	// next() returns a 64-bit integer
	for(int64_t i = n; i-- != 0;)
#ifdef HARNESS_ADD
		e += NEXT; // Measurement
#else
		e ^= NEXT; // Measurement
#endif
#endif

#ifdef PAPI
	const uint64_t cycles = (PAPI_get_real_cyc() - start_cycle);
	printf("%s: %" PRId64 " cycles, %.03f B/cycle,  %.03f cycles/B, %.03f words/cycle, %.03f cycles/word\n", argv[0], cycles, (n * 8.) / cycles, cycles / (n * 8.), n / (double)cycles, cycles / (double)n);
#else
	const uint64_t time_delta = (get_user_time() - start_time);
	printf("%s: %.03f s, %.03f GB/s, %.03f words/ns, %.03f ns/word\n", argv[0], time_delta / 1E9, (n * 8.) / time_delta, n / (double)time_delta, time_delta / (double)n);
#endif

	// const volatile uint64_t unused = e;
#endif

	TAIL // Here you can add instructions that must be executed at the end, usually to avoid dead-code elimination

	return 0;
}
