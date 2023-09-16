/*
 Arcan Shared Memory Interface, Extended Mapping

 Friendly Warning:
 These are extended internal sub-protocols only used for segmenting the
 engine into multiple processes. It relies on data-types not defined in
 the rest of shmif and is therefore wholly unsuitable for inclusion or
 use in code elsewhere.
 */

/*
 Copyright (c) 2016-2020, Bjorn Stahl
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
 * BSD checksum, from BSD sum. We calculate this to get lock-free updates while
 * staying away from atomic/reordering (since there's no atomic 64- byte type
 * anyhow). The added gain is that when metadata is synched and we're in a
 * partial update, the failed checksum means there is new data on the way
 * anyhow or something more sinister is afoot.
 */
static inline uint16_t subp_checksum(const uint8_t* const buf, size_t len)
{
	uint16_t res = 0;
	for (size_t i = 0; i < len; i++){
		if (res & 1)
			res |= 0x10000;
		res = ((res >> 1) + buf[i]) & 0xffff;
	}
	return res;
}

/*
 * Forward declarations of the current sub- structures, and a union of
 * the safe / known return pointers in order to avoid explicit casting
 */
struct arcan_shmif_vr;
struct arcan_shmif_ramp;
struct arcan_shmif_hdr;
struct arcan_shmif_vector;
struct arcan_shmif_venc;

union shmif_ext_substruct {
	struct arcan_shmif_vr* vr;
	struct arcan_shmif_ramp* cramp;
	struct arcan_shmif_hdr* hdr;
	struct arcan_shmif_vector* vector;
	struct arcan_shmif_venc* venc;
};

/*
 * Extract a valid sub-structure from the context. This should have been
 * negotiated with an extended resize request in advance, and need to be
 * re- extracted in the event of an extended meta renegotiation, a reset
 * or a migration. The safest pattern is to simply call when the data is
 * needed and never cache.
 */
union shmif_ext_substruct arcan_shmif_substruct(
	struct arcan_shmif_cont* ctx, enum shmif_ext_meta meta);

/*
 * Marks the beginning of the offset table that is set if subprotocols
 * have been activated. Used internally by the resize- function. The
 * strict copy is kept server-side.
 */
struct arcan_shmif_ofstbl {
	union {
	struct {
		uint32_t ofs_ramp, sz_ramp;
		uint32_t ofs_vr, sz_vr;
		uint32_t ofs_hdr, sz_hdr;
		uint32_t ofs_vector, sz_vector;
		uint32_t ofs_venc, sz_venc;
	};
	uint32_t offsets[32];
	};
};

/* HDR is something of a misnomer here, it can also refer to SDR contents with
 * higher precision (e.g. 10-bit). In that case the SDR eotf mode is specified.
 * The values here match what libdrm metadata takes. */
enum shmif_hdr_eotf {
	SHMIF_EOTF_SDR = 0,
	SHMIF_EOTF_HDR = 1,
	SHMIF_EOTF_ST2084 = 2,
	SHMIF_EOTF_HLG = 3
};

struct arcan_shmif_hdr {
	uint8_t model; /* match eotf */

	struct {
		int eotf;
		uint16_t rx, ry, gx, gy, bx, by;
		uint16_t wpx, wpy;
		uint16_t master_min, master_max;
		uint16_t cll_max;
		uint16_t fll_max;
	} drm;
};

/* verified during _signal, framesize <= w * h * sizeof(shmif_pixel) */
struct arcan_shmif_venc {
	uint8_t fourcc[4];
	size_t framesize;
};

/*
 * similar to how agp_mesh_store accepts data, the reordering would
 * happen in the copy+validation stage. negative offset fields mean
 * the data isn't present.
 */
struct shmif_vector_mesh {
	int32_t ofs_verts; /* float */
	int32_t ofs_txcos; /* float */
	int32_t ofs_txcos2; /* float */
	int32_t ofs_normals; /* float */
	int32_t ofs_colors; /* float */
	int32_t ofs_tangents; /* float */
	int32_t ofs_bitangents; /* float */
	int32_t ofs_weights; /* float */
	int32_t ofs_joints; /* uint16 */
	int32_t ofs_indices; /* uint32 */

	size_t vertex_size;
	size_t n_vertices;
	size_t n_indices;
	int primitive;

	size_t buffer_sz;
	uint8_t* buffer;
};

struct arcan_shmif_vector {
/* PRODUCER set */
	size_t data_sz;
	uint8_t mesh_groups;
	struct shmif_vector_mesh meshes[];
};

/*
 * Though it might seem that this information gets lost on a resize request,
 * that is only true if the substructure set changes. Otherwise it's part of
 * the base that gets copied over.
 */

/*
 * the number of maximum crtcs/planes with support for lut- tables
 */
#define SHMIF_CMRAMP_PLIM 4
#define SHMIF_CMRAMP_UPLIM 4095 /* % 3 == 0 */

struct ramp_block {
	uint8_t format;

/* checksum covers edid + plane-data */
	uint16_t checksum;

	size_t plane_sizes[SHMIF_CMRAMP_PLIM];

	uint8_t edid[128];

/* set to indicate nominal resolution and refresh rate */
	size_t width, height;
	uint8_t vrate_int, vrate_fract;

/* plane_sizes determines consumed size and mapping, color information
 * can be retrieved from edid (assume RGB and let plane_sizes determine
 * planar or interleaved if no edid). */
	float planes[SHMIF_CMRAMP_UPLIM];
};

#define ARCAN_SHMIF_RAMPMAGIC 0xfafafa10
struct arcan_shmif_ramp {
	uint32_t magic;

/* BITMASK, PRODUCER SET, CONSUMER CLEAR */
	_Atomic uint_least8_t dirty_in;

/* BITMASK, CONSUMER SET, PRODUCER CLEAR */
	_Atomic uint_least8_t dirty_out;

/* PRODUCER INIT, will be %2, first _in the _out */
	uint8_t n_blocks;

/* PRODUCER INIT, CONSUMER_UPDATE */
	struct ramp_block ramps[];
};

#define SHMIF_CMRAMP_RVA(X)(sizeof(struct ramp_block) * (X) *\
	SHMIF_CMRAMP_PLIM * SHMIF_CMRAMP_UPLIM)

/*
 * retrieve/flag-read the ramp at index [ind], and store a copy of
 * its contents into [out] (if !NULL).
 * Returns false if the index is out of bounds (SHMIF_CMRAMP_PLANE)
 * or the contents failed checksum test.
 */
bool arcan_shmifsub_getramp(
	struct arcan_shmif_cont* cont, size_t ind, struct ramp_block* out);

/*
 * update the ramp at index [ind] and mark as updated.
 * returns false if the ramp couldn't be set (missing permissions or
 * index out of bounds), true if it was successfully updated.
 */
bool arcan_shmifsub_setramp(
	struct arcan_shmif_cont* cont, size_t ind, struct ramp_block* in);

/*
 * To avoid namespace collisions, the detailed VR structure relies
 * on having access to the definitions in arcan_math.h from the core
 * engine code.
 */
#ifdef HAVE_ARCAN_MATH
#define VR_VERSION 0x1

/*
 * This structure is mapped into the adata area. It can be verified
 * if the apad value match the size and the apad_type matches the
 * SHMIF_APAD_VR constant.
 */
enum avatar_limbs {
	PERSON = 1, /* abstract for global positioning */
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
	L_TOOL,
	R_TOOL,
	LIMB_LIM
};

/*
 * The standard lens parameters
 */
struct vr_meta {
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
	float left_fov;
	float right_fov;
	float left_ar;
	float right_ar;
	float hsep;
	float vpos;

/* correction constants */
	float distortion[4];
	float abberation[4];

	float projection_left[16];
	float projection_right[16];
};

union vr_data {
	uint8_t data[64];
	struct {
		vector position;
		vector forward;
		quat orientation;
		_Atomic uint16_t checksum;
	};
};

struct vr_limb {
/* PRODUCER_SET (activation, or 0 if no haptics) */
	uint8_t haptic_id;
	uint8_t haptic_capabilities;

/* CONSUMER-SET: don't bother updating, won't be used. */
	uint8_t ignored;

/* PRODUCER_SET (activation) */
	uint8_t limb_type;

/* PRODUCER_UPDATE */
	_Atomic uint_least32_t timestamp;

/* PRODUCER UPDATE */
	union vr_data data;
};

/*
 * 0 <= (page_sz) - offset_of(limb) - limb_lim*sizeof(struct) limb
 */
struct arcan_shmif_vr {
/* CONSUMER SET (activation) */
	uint8_t version;
	uint8_t limb_lim;

/* PRODUCER MODIFY */
	_Atomic uint_least64_t limb_mask;

/* PRODUCER SET/CONSUMER CLEAR */
	_Atomic uint_least8_t ready;

/* PRODUCER INIT */
	struct vr_meta meta;

/* PRODUCER UPDATE (see struct definition) */
	struct vr_limb limbs[];
};
#endif
#endif
