/*
 Arcan Shared Memory Interface, Extended Mapping

 Friendly Warning:
 These are extended internal sub-protocols only used for segmenting the
 engine into multiple processes. It relies on data-types not defined in
 the rest of shmif and is therefore wholly unsuitable for inclusion or
 use in code elsewhere.
 */

/*
 Copyright (c) 2016, Bjorn Stahl
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

#ifndef HAVE_ARCAN_SHMIF_SUBPROTO
#define HAVE_ARCAN_SHMIF_SUBPROTO

/*
 * BSD checksum, from BSD sum. We calculate this to get lock-free updates which
 * staying away from atomic/reordering (since there's no atomic 64- byte type
 * anyhow). The added gain is that when metadata is synched and we're in a
 * partial update, the failed checksum means there is new data on the way
 * anyhow.
 */
static inline uint16_t subp_checksum(uint8_t* buf, size_t len)
{
	uint16_t res = 0;
	for (size_t i = 0; i < len; i++){
		if (res & 1)
			res |= 0x10000;
		res = ((res >> 1) + buf[i]) & 0xffff;
	}
	return res;
}

struct arcan_shmif_hdr16f;
struct arcan_shmif_vector;

struct ramp_block {
	bool output;
	uint8_t format;
	size_t plane_size;

	union {
		uint16_t* rplane;
		uint16_t* gplane;
		uint16_t* bplane;
	} fmt_a;

	uint8_t edid[128];
	uint16_t checksum;
};

struct arcan_shmif_ramp {
/* BITMASK, PRODUCER SET, CONSUMER CLEAR */
	_Atomic uint_least8_t dirty_in;

/* BITMASK, CONSUMER SET, PRODUCER CLEAR */
	_Atomic uint_least8_t dirty_out;

/* PRODUCER INIT */
	uint8_t n_blocks;

/* PRODUCER INIT, CONSUMER_UPDATE */
	struct ramp_block **ramp_in;
	struct ramp_block **ramp_out;
};

/*
 * To avoid namespace collisions, the detailed HMD structure relies
 * on having access to the definitions in arcan_math.h from the core
 * engine code.
 */
#ifdef HAVE_ARCAN_MATH
#define HMD_VERSION 0x1000

/*
 * This structure is mapped into the adata area. It can be verified
 * if the apad value match the size and the apad_type matches the
 * SHMIF_APAD_HMD constant.
 */
enum avatar_limbs {
	PERSON = 0, /* abstract for global positioning */
	NECK,
	L_EYE,
	R_EYE,
	L_SHOULDER,
	R_SHOULDER,
	L_ELBOW,
	R_ELBOW,
	L_WRIST,
	R_WRIST,
/* might seem overly detailed but with glove- devices some points
 * can be sampled and others can be inferred through kinematics */
	L_THUMB_PROXIMAL,
	L_THUMB_MIDDLE,
	L_THUMB_DISTAL,
	L_POINTER_PROXIMAL,
	L_POINTER_MIDDLE,
	L_POINTER_DISTAL,
	L_MIDDLE_PROXIMAL,
	L_MIDDLE_MIDDLE,
	L_MIDDLE_DISTAL,
	L_RING_PROXIMAL,
	L_RING_MIDDLE,
	L_RING_DISTAL,
	L_PINKY_PROXIMAL,
	L_PINKY_MIDDLE,
	L_PINKY_DISTAL,
	R_THUMB_PROXIMAL,
	R_THUMB_MIDDLE,
	R_THUMB_DISTAL,
	R_POINTER_PROXIMAL,
	R_POINTER_MIDDLE,
	R_POINTER_DISTAL,
	R_MIDDLE_PROXIMAL,
	R_MIDDLE_MIDDLE,
	R_MIDDLE_DISTAL,
	R_RING_PROXIMAL,
	R_RING_MIDDLE,
	R_RING_DISTAL,
	R_PINKY_PROXIMAL,
	R_PINKY_MIDDLE,
	R_PINKY_DISTAL,
	L_HIP,
	R_HIP,
	L_KNEE,
	R_KNEE,
	L_ANKLE,
	R_ANKLE,
	LIMB_LIM
};

/*
 * Special TARGET_COMMAND... handling:
 * BCHUNKSTATE:
 *  extension 'arcan_hmd_distort' for distortion mesh packed as native
 *  floats with a header indicating elements then elements*[X,Y,Z],elements*[S,T]
 *
 * IO- events are used to activate haptics
 */

/*
 * The standard lens parameters
 */
struct hmd_meta {
/* pixels */
	unsigned hres;
	unsigned vres;

/* values in meters to keep < 1.0 */
	float h_size;
	float v_size;
	float h_center;
	float eye_display;
	float lens_distance;
	float ipd;

/* correction constants */
	float distortion[4];
	float abberation[4];
};

struct hmd_limb {
/* CONSUMER-SET: don't bother updating, won't be used. */
	bool ignored;

/* PRODUCER_SET (activation) */
	enum avatar_limbs limb_type;

/* PRODUCER_SET (activation, or 0 if no haptics) */
	uint32_t haptic_id;
	uint32_t haptic_capabilities;

/* PRODUCER_UPDATE */
	_Atomic uint_least32_t timestamp;

/* PRODUCER UPDATE */
	union {
		uint8_t data[64];
		struct {
			vector position;
			vector forward;
			quat orientation;
			uint16_t checksum;
		};
	};
};

/*
 * 0 <= (page_sz) - offset_of(limb) - limb_lim*sizeof(struct) limb
 */
struct arcan_shmif_hmd {
/* CONSUMER SET (activation) */
	size_t page_sz;
	uint8_t version;
	uint8_t limb_lim;

/* PRODUCER MODIFY */
	_Atomic uint_least64_t limb_mask;

/* PRODUCER SET */
	_Atomic uint_least8_t ready;

/* PRODUCER INIT */
	struct hmd_meta meta;

/* PRODUCER UPDATE (see struct definition) */
	struct hmd_limb limbs[];
};
#endif
#endif
