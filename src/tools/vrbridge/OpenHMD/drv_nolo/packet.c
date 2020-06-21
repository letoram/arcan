// Copyright 2017, Joey Ferwerda.
// SPDX-License-Identifier: BSL-1.0
/*
 * OpenHMD - Free and Open Source API and drivers for immersive technology.
 * Original implementation by: Yann Vernier.
 */

/* NOLO VR - Packet Decoding and Utilities */


#include <stdio.h>
#include "nolo.h"

#define DELTA 0x9e3779b9
#define MX (((z>>5^y<<2) + (y>>3^z<<4)) ^ ((sum^y) + (key[(p&3)^e] ^ z)))

#define CRYPT_WORDS (64-4)/4
#define CRYPT_OFFSET 1

inline static uint8_t read8(const unsigned char** buffer)
{
	uint8_t ret = **buffer;
	*buffer += 1;
	return ret;
}

inline static int16_t read16(const unsigned char** buffer)
{
	int16_t ret = **buffer | (*(*buffer + 1) << 8);
	*buffer += 2;
	return ret;
}

inline static uint32_t read32(const unsigned char** buffer)
{
	uint32_t ret = **buffer | (*(*buffer + 1) << 8) | (*(*buffer + 2) << 16) | (*(*buffer + 3) << 24);
	*buffer += 4;
	return ret;
}

void btea_decrypt(uint32_t *v, int n, int base_rounds, uint32_t const key[4])
{
	uint32_t y, z, sum;
	unsigned p, rounds, e;

	/* Decoding Part */
	rounds = base_rounds + 52/n;
	sum = rounds*DELTA;
	y = v[0];

	do {
		e = (sum >> 2) & 3;
		for (p=n-1; p>0; p--) {
			z = v[p-1];
			y = v[p] -= MX;
		}

		z = v[n-1];
		y = v[0] -= MX;
		sum -= DELTA;
	} while (--rounds);
}

void nolo_decrypt_data(unsigned char* buf)
{
	static const uint32_t key[4] = {0x875bcc51, 0xa7637a66, 0x50960967, 0xf8536c51};
	uint32_t cryptpart[CRYPT_WORDS];

	// Decrypt encrypted portion
	for (int i = 0; i < CRYPT_WORDS; i++) {
	cryptpart[i] =
		((uint32_t)buf[CRYPT_OFFSET+4*i  ]) << 0  |
		((uint32_t)buf[CRYPT_OFFSET+4*i+1]) << 8  |
		((uint32_t)buf[CRYPT_OFFSET+4*i+2]) << 16 |
		((uint32_t)buf[CRYPT_OFFSET+4*i+3]) << 24;
	}

	btea_decrypt(cryptpart, CRYPT_WORDS, 1, key);

	for (int i = 0; i < CRYPT_WORDS; i++) {
		buf[CRYPT_OFFSET+4*i  ] = cryptpart[i] >> 0;
		buf[CRYPT_OFFSET+4*i+1] = cryptpart[i] >> 8;
		buf[CRYPT_OFFSET+4*i+2] = cryptpart[i] >> 16;
		buf[CRYPT_OFFSET+4*i+3] = cryptpart[i] >> 24;
	}
}

void nolo_decode_position(const unsigned char* data, vec3f* pos)
{
	const double scale = 0.0001f;

	pos->x = scale*read16(&data);
	pos->y = scale*read16(&data);
	pos->z = scale*read16(&data);
}

void nolo_decode_orientation(const unsigned char* data, nolo_sample* smp)
{	
	// acceleration
	for(int i = 0; i < 3; i++){
		smp->accel[i] = read16(&data);
	}

	data += 6;

	// gyro
	for(int i = 0; i < 3; i++){
		smp->gyro[i] = read16(&data);
	}
}

void nolo_decode_controller_orientation(const unsigned char* data, nolo_sample* smp)
{	
	// gyro
	for(int i = 0; i < 3; i++){
		smp->gyro[i] = read16(&data);
	}

	// acceleration
	for(int i = 0; i < 3; i++){
		smp->accel[i] = read16(&data);
	}
}

// Orientation for Firmware <2,0
void nolo_decode_quat_orientation(const unsigned char* data, quatf* quat)
{
	double w,i,j,k, scale;
	// CV1 order
	w = (int16_t)(data[0]<<8 | data[1]);
	i = (int16_t)(data[2]<<8 | data[3]);
	j = (int16_t)(data[4]<<8 | data[5]);
	k = (int16_t)(data[6]<<8 | data[7]);
	// Normalize (unknown if scale is constant)
	//scale = 1.0/sqrt(i*i+j*j+k*k+w*w);
	// Turns out it is fixed point. But the android driver author
	// either didn't know, or didn't trust it.
	// Unknown if normalizing it helps
	scale = 1.0 / 16384;
	//std::cout << "Scale: " << scale << std::endl;
	w *= scale;
	i *= scale;
	j *= scale;
	k *= scale;

	// Reorder
	quat->w = w;
	quat->x = i;
	quat->y = k;
	quat->z = -j;
}

void nolo_decode_controller(drv_priv* priv, const unsigned char* data)
{
	uint8_t bit, buttonstate;

	vec3f position;
	quatf orientation;
	nolo_sample smp;

	if (priv->rev == 1) //old firmware
	{
		nolo_decode_position(data+3, &position);
		nolo_decode_quat_orientation(data+9, &orientation);

		//Change button state
		buttonstate = data[17];
		for (bit=0; bit<6; bit++)
			priv->controller_values[bit] = (buttonstate & 1<<bit ? 1 : 0);

		priv->controller_values[6] = data[19]; //X Pad
		priv->controller_values[7] = data[20]; //Y Pad
		priv->base.rotation = orientation;
	}
	else // Firmware >2.0
	{
		data += 1; //skip header
		nolo_decode_position(data, &position);
		data += 6;
		nolo_decode_controller_orientation(data, &smp);

		//Change button state
		data += 12;
		buttonstate = read8(&data);
		for (bit=0; bit<6; bit++)
			priv->controller_values[bit] = (buttonstate & 1<<bit ? 1 : 0);

		priv->controller_values[6] = read8(&data); //X Pad
		priv->controller_values[7] = read8(&data); //Y Pad

		priv->sample = smp; //Set sample for fusion
	}

	priv->base.position = position;
}

void nolo_decode_hmd_marker(drv_priv* priv, const unsigned char* data)
{
	vec3f homepos;
	vec3f position;
	quatf orientation;
	nolo_sample smp;

	if (priv->rev == 1)
	{
		nolo_decode_position(data+3, &position);
		nolo_decode_position(data+9, &homepos);
		nolo_decode_quat_orientation(data+16, &orientation);
		priv->base.rotation = orientation;
	}
	else
	{
		data += 25; //Skip controller data

		nolo_decode_position(data, &position);
		data += 6;
		data += 6;
		nolo_decode_orientation(data, &smp);

		priv->sample = smp; //Set sample for fusion
	}

	priv->base.position = position;
}

void nolo_decode_base_station(drv_priv* priv, const unsigned char* data)
{
	// Unknown version
	if (data[0] != 2 || data[1] != 1)
		return;
}
