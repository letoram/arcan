#include <stdint.h>
#include <stdbool.h>
#include <limits.h>
#include "arcan_math.h"
#include "../a12/pack.h"
#include <arcan_shmif.h>
#include <arcan_shmif_sub.h>
#include <hidapi.h>
#include <pthread.h>
#include <openhmd.h>
#include <inttypes.h>
#include "vrbridge.h"
#include "avr_nreal.h"
#include "ahrs.h"

/* #define DUMP */
#define ID_NECK 0
#define HID_REPORT_SIZE 64
#define NREAL_VID 0x3318
#define NREAL_PID 0x0424
#define FACT_GYRO (1.0f / 8388608.0f * 2000.0f)
#define FACT_ACCEL (1.0f / 8388608.0f * 16.0f)

struct driver_state {
	hid_device* dev;
	struct ahrs_context fusion;
	pthread_mutex_t lock;
	uint64_t last_ts;
#ifdef DUMP
	FILE* fout;
#endif
};

struct handler {
	uint8_t cmd[HID_REPORT_SIZE];
	size_t len;
	void (*action)(
		struct driver_state*, struct vr_limb*, uint8_t* buf, size_t buf_sz);
};

static float unpack_sample(uint8_t* buf, float fact)
{
/* 3 bytes signed 2s complement */
	union {
		uint8_t b[4];
		int32_t res;
	} s24;

	s24.b[0] = buf[0];
	s24.b[1] = buf[1];
	s24.b[2] = buf[2];
	s24.b[3] = buf[2] & 0x80 ? 0xff : 0;

	return (float) s24.res * fact;
}

static void motion_sample(
	struct driver_state* C, struct vr_limb* L, uint8_t* buf, size_t buf_sz)
{
	if (buf_sz != 64){
		fprintf(stderr, "nreal: bad report packet (%zu)\n", buf_sz);
		return;
	}
/* 01, 02, ?? ?? */
	static const uint8_t ofs_ts  = 5;
	static const uint8_t ofs_avx = 18;
	static const uint8_t ofs_avy = 21;
	static const uint8_t ofs_avz = 24;
	static const uint8_t ofs_acx = 33;
	static const uint8_t ofs_acy = 36;
	static const uint8_t ofs_acz = 39;

#ifdef DUMP
	fwrite(buf, buf_sz, 1, C->fout);
	fprintf(C->fout, "\n[AAA]\n");
#endif

	float gyro[3], accel[3];
	uint64_t ts;
	unpack_u64(&ts, &buf[ofs_ts]);
	gyro[0] = unpack_sample(&buf[ofs_avx], -FACT_GYRO);
	gyro[1] = unpack_sample(&buf[ofs_avy], FACT_GYRO);
	gyro[2] = unpack_sample(&buf[ofs_avz], FACT_GYRO);
	accel[0] = unpack_sample(&buf[ofs_acx], FACT_ACCEL);
	accel[1] = unpack_sample(&buf[ofs_acy], FACT_ACCEL);
	accel[2] = unpack_sample(&buf[ofs_acz], FACT_ACCEL);

	if (C->last_ts){
		float nv[3] = {0};
/*		printf("@%"PRIu64" g: %f, %f, %f - a: %f %f %f\n",
			ts,
			gyro[0], gyro[1], gyro[2],
			accel[0], accel[1], accel[2]
		);*/
		AHRS_update(&C->fusion, gyro, accel, nv);
		quat q = {
			.x = C->fusion.q0,
			.y = C->fusion.q1,
			.z = C->fusion.q2,
			.w = C->fusion.q3
		};
		L->data.orientation = q;
	}
	C->last_ts = ts;
}

struct handler handlers[] =
{
	{.cmd = {0x01, 0x02}, .len = 2, motion_sample},
};

void nreal_sample(struct dev_ent* dev, struct vr_limb* limb, unsigned id)
{
	uint8_t report[HID_REPORT_SIZE];

	while (1){
		switch(id){
		case ID_NECK:{
			ssize_t nr = hid_read(dev->state->dev, report, HID_REPORT_SIZE);
			bool match = false;

			if (nr < 0){
				return;
			}
			for (size_t i = 0; i < sizeof(handlers) / sizeof(handlers[0]); i++){
				if (memcmp(handlers[i].cmd, report, handlers[i].len) == 0){
					handlers[i].action(dev->state, limb, report, nr);
					match = true;
					continue;
				}
			}
			if (!match){
#ifdef DUMP
			if (dev->state->fout){
				fprintf(dev->state->fout, "unknown report: ");
				for (size_t i = 0; i < nr; i++){
					fprintf(dev->state->fout, "%02X%s", report[i], i == nr - 1 ? "\n" : " ");
				}
			}
#endif
			}
			else
				return;
			break;
		}
		}
	}
}

void nreal_control(struct dev_ent* dev, enum ctrl_cmd cmd)
{
	if (cmd == RESET_REFERENCE){
/* set ref-quat to last */
	}
}

bool nreal_init(struct dev_ent* ent,
	struct arcan_shmif_vr* vr, struct arg_arr* arg)
{
	hid_device* dev = hid_open(NREAL_VID, NREAL_PID, NULL);
	if (!dev){
		debug_print(1, "device=nreal:status=not_found");
		return false;
	}

	debug_print(1, "device=nreal:status=found");
	uint8_t enable[] = {0xaa, 0xc5, 0xd1, 0x21, 0x42, 0x04, 0x00, 0x19, 0x01 };

	struct driver_state* state = malloc(sizeof(struct driver_state));
	if (!state){
		debug_print(1, "device=nreal:status=error:value=enomem");
		hid_close(dev);
		return false;
	}

	*state = (struct driver_state){
		.dev = dev,
		.lock = PTHREAD_MUTEX_INITIALIZER,
#ifdef DUMP
		.fout = fopen("dump.raw", "w+"),
#endif
	};

	vr->meta = (struct vr_meta){
		.hres = 1920,
		.vres = 1080,
		.left_fov = 45.0,
		.right_fov = 45.0,
		.left_ar = 0.888885,
		.right_ar = 0.888885,
	};

	ent->state = state;
	AHRS_init(&state->fusion, 1000.0f);
	hid_write(dev, enable, sizeof(enable));
	vrbridge_alloc_limb(ent, NECK, 0);

	return true;
}
