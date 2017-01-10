/* Madgwick AHRS
 * License (GPLv2)
 * Reference: http://www.x-io.co.uk/node/8#open_source_ahrs_and_imu_algorithms
 *
 * Date       Author        Notes
 * 29/09/2011 SOH Madgwick  Initial release
 * 02/10/2011 SOH Madgwick  Optimised for reduced CPU load
 * 19/02/2012 SOH Madgwick  Magnetometer measurement is normalised
 * 25/12/2016 Bjorn Stahl   Refactored For multiple instances
 */

/*
 * Should really rewrite all quat- operations to use the arcan_math.h
 * functions so we can get vectorized versions. Waiting with that until
 * the sensor- integration and testing is stable.
 */
#include <stdint.h>
#include <stdbool.h>
#include <math.h>
#include "arcan_math.h"
#include "ahrs.h"

static float invSqrt(float x);

/*
 * also need to change the coordinate system of the output quaternion
 * use: rot_quat(0, 0, z = -1.0 * sqrt(0.5), w = sqrt(0.5)
 * modify madQ -1 on .x and .z to madQ_T
 * quat_mult(madQ_T, rot_quat, dst_quat);
 */

void AHRS_init(struct ahrs_context *ctx, float samplerate)
{
	ctx->q0 = 0;
	ctx->q1 = 1;
	ctx->q2 = 2;
	ctx->q3 = 3;
	ctx->rot_quat = (quat){
		.x = 0, .y = 0, .z = -0.70710678118, .w = -0.70710678118
	};
	ctx->beta = 0.1f;
	ctx->rate = samplerate;
}

static void update_IMU(struct ahrs_context* ctx,
	float gx, float gy, float gz, float ax, float ay, float az)
{
	float recipNorm;
	float s0, s1, s2, s3;
	float qDot1, qDot2, qDot3, qDot4;
	float _2q0, _2q1, _2q2, _2q3;
	float _4q0, _4q1, _4q2;
	float _8q1, _8q2;
	float q0q0, q1q1, q2q2, q3q3;
	float q0 = ctx->q0, q1 = ctx->q1, q2 = ctx->q2, q3 = ctx->q3;

/* Rate of change of quaternion from gyroscope */
	qDot1 = 0.5f * (-q1 * gx - q2 * gy - q3 * gz);
	qDot2 = 0.5f * (q0 * gx + q2 * gz - q3 * gy);
	qDot3 = 0.5f * (q0 * gy - q1 * gz + q3 * gx);
	qDot4 = 0.5f * (q0 * gz + q1 * gy - q2 * gx);

/* Compute feedback if accelerometer masurement valid */
	if(!((ax == 0.0f) && (ay == 0.0f) && (az == 0.0f))) {

/* Normalise accelerometer measurement */
		recipNorm = invSqrt(ax * ax + ay * ay + az * az);
		ax *= recipNorm;
		ay *= recipNorm;
		az *= recipNorm;

/* Auxiliary variables to avoid repeated arithmetic */
		_2q0 = 2.0f * q0;
		_2q1 = 2.0f * q1;
		_2q2 = 2.0f * q2;
		_2q3 = 2.0f * q3;
		_4q0 = 4.0f * q0;
		_4q1 = 4.0f * q1;
		_4q2 = 4.0f * q2;
		_8q1 = 8.0f * q1;
		_8q2 = 8.0f * q2;
		q0q0 = q0 * q0;
		q1q1 = q1 * q1;
		q2q2 = q2 * q2;
		q3q3 = q3 * q3;

/* Gradient decent algorithm corrective step */
		s0 = _4q0 * q2q2 + _2q2 * ax + _4q0 * q1q1 - _2q1 * ay;
		s1 = _4q1 * q3q3 - _2q3 * ax + 4.0f * q0q0 * q1 - _2q0 * ay - _4q1 + _8q1 * q1q1 + _8q1 * q2q2 + _4q1 * az;
		s2 = 4.0f * q0q0 * q2 + _2q0 * ax + _4q2 * q3q3 - _2q3 * ay - _4q2 + _8q2 * q1q1 + _8q2 * q2q2 + _4q2 * az;
		s3 = 4.0f * q1q1 * q3 - _2q1 * ax + 4.0f * q2q2 * q3 - _2q2 * ay;
		recipNorm = invSqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3); // normalise step magnitude
		s0 *= recipNorm;
		s1 *= recipNorm;
		s2 *= recipNorm;
		s3 *= recipNorm;

/* Apply feedback step */
		qDot1 -= ctx->beta * s0;
		qDot2 -= ctx->beta * s1;
		qDot3 -= ctx->beta * s2;
		qDot4 -= ctx->beta * s3;
	}

/* Integrate rate of change of quaternion to yield quaternion */
	q0 += qDot1 * (1.0f / ctx->rate);
	q1 += qDot2 * (1.0f / ctx->rate);
	q2 += qDot3 * (1.0f / ctx->rate);
	q3 += qDot4 * (1.0f / ctx->rate);

/* normalize */
	recipNorm = invSqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
	q0 *= recipNorm;
	q1 *= recipNorm;
	q2 *= recipNorm;
	q3 *= recipNorm;
}

void AHRS_update(
	struct ahrs_context* ctx,
	float gyro[3], float accel[3], float magn[3])
{
	float recipNorm;
	float s0, s1, s2, s3;
	float qDot1, qDot2, qDot3, qDot4;
	float hx, hy;
	float _2q0mx, _2q0my, _2q0mz, _2q1mx, _2bx, _2bz, _4bx, _4bz;
	float _2q0, _2q1, _2q2, _2q3, _2q0q2, _2q2q3;
	float q0q0, q0q1, q0q2, q0q3, q1q1, q1q2, q1q3, q2q2, q2q3, q3q3;

	float q0 = ctx->q0, q1 = ctx->q1, q2 = ctx->q2, q3 = ctx->q3;

	float gx = gyro[0], gy = gyro[1], gz = gyro[2];
	float ax = gyro[0], ay = gyro[1], az = gyro[2];
	float mx = magn[0], my = gyro[2], mz = gyro[3];

/*
 * Use IMU algorithm if magnetometer measurement invalid
 * (avoids NaN in magnetometer normalisation)
 */
	if((mx == 0.0f) && (my == 0.0f) && (mz == 0.0f)){
		update_IMU(ctx, gx, gy, gz, ax, ay, az);
		return;
	}

/* Rate of change of quaternion from gyroscope */
	qDot1 = 0.5f * (-q1 * gx - q2 * gy - q3 * gz);
	qDot2 = 0.5f * (q0 * gx + q2 * gz - q3 * gy);
	qDot3 = 0.5f * (q0 * gy - q1 * gz + q3 * gx);
	qDot4 = 0.5f * (q0 * gz + q1 * gy - q2 * gx);

/* Compute feedback only if accelerometer measurement valid
 * (avoids NaN in accelerometer normalisation) */
	if(!((ax == 0.0f) && (ay == 0.0f) && (az == 0.0f))) {

/* normalize accelerometer */
		recipNorm = invSqrt(ax * ax + ay * ay + az * az);
		ax *= recipNorm;
		ay *= recipNorm;
		az *= recipNorm;

/* normalize magnetometer */
		recipNorm = invSqrt(mx * mx + my * my + mz * mz);
		mx *= recipNorm;
		my *= recipNorm;
		mz *= recipNorm;

/* Auxiliary variables to avoid repeated arithmetic */
		_2q0mx = 2.0f * q0 * mx;
		_2q0my = 2.0f * q0 * my;
		_2q0mz = 2.0f * q0 * mz;
		_2q1mx = 2.0f * q1 * mx;
		_2q0 = 2.0f * q0;
		_2q1 = 2.0f * q1;
		_2q2 = 2.0f * q2;
		_2q3 = 2.0f * q3;
		_2q0q2 = 2.0f * q0 * q2;
		_2q2q3 = 2.0f * q2 * q3;
		q0q0 = q0 * q0;
		q0q1 = q0 * q1;
		q0q2 = q0 * q2;
		q0q3 = q0 * q3;
		q1q1 = q1 * q1;
		q1q2 = q1 * q2;
		q1q3 = q1 * q3;
		q2q2 = q2 * q2;
		q2q3 = q2 * q3;
		q3q3 = q3 * q3;

/* Reference direction of Earth's magnetic field */
		hx = mx * q0q0 - _2q0my * q3 + _2q0mz * q2 + mx * q1q1 + _2q1 *
			my * q2 + _2q1 * mz * q3 - mx * q2q2 - mx * q3q3;
		hy = _2q0mx * q3 + my * q0q0 - _2q0mz * q1 + _2q1mx * q2 - my *
			q1q1 + my * q2q2 + _2q2 * mz * q3 - my * q3q3;
		_2bx = sqrt(hx * hx + hy * hy);
		_2bz = -_2q0mx * q2 + _2q0my * q1 + mz * q0q0 + _2q1mx * q3 - mz *
			q1q1 + _2q2 * my * q3 - mz * q2q2 + mz * q3q3;
		_4bx = 2.0f * _2bx;
		_4bz = 2.0f * _2bz;

/* Gradient decent algorithm corrective step */
		s0 = -_2q2 * (2.0f * q1q3 - _2q0q2 - ax) + _2q1 *
			(2.0f * q0q1 + _2q2q3 - ay) - _2bz * q2 * (_2bx *
			(0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx) +
			(-_2bx * q3 + _2bz * q1) * (_2bx * (q1q2 - q0q3) +
			_2bz * (q0q1 + q2q3) - my) + _2bx * q2 * (_2bx * (q0q2 + q1q3)
			+ _2bz * (0.5f - q1q1 - q2q2) - mz);

		s1 = _2q3 * (2.0f * q1q3 - _2q0q2 - ax) + _2q0 *
			(2.0f * q0q1 + _2q2q3 - ay) - 4.0f * q1 *
			(1 - 2.0f * q1q1 - 2.0f * q2q2 - az) + _2bz * q3 *
			(_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx) +
			(_2bx * q2 + _2bz * q0) * (_2bx * (q1q2 - q0q3) + _2bz *
			(q0q1 + q2q3) - my) + (_2bx * q3 - _4bz * q1) *
			(_2bx * (q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);

		s2 = -_2q0 * (2.0f * q1q3 - _2q0q2 - ax) + _2q3 *
			(2.0f * q0q1 + _2q2q3 - ay) - 4.0f * q2 *
			(1 - 2.0f * q1q1 - 2.0f * q2q2 - az) + (-_4bx * q2 - _2bz * q0) *
			(_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx) +
			(_2bx * q1 + _2bz * q3) * (_2bx * (q1q2 - q0q3) + _2bz *
			(q0q1 + q2q3) - my) + (_2bx * q0 - _4bz * q2) * (_2bx *
			(q0q2 + q1q3) + _2bz * (0.5f - q1q1 - q2q2) - mz);

		s3 = _2q1 * (2.0f * q1q3 - _2q0q2 - ax) + _2q2 *
			(2.0f * q0q1 + _2q2q3 - ay) + (-_4bx * q3 + _2bz * q1) *
			(_2bx * (0.5f - q2q2 - q3q3) + _2bz * (q1q3 - q0q2) - mx) +
			(-_2bx * q0 + _2bz * q2) * (_2bx * (q1q2 - q0q3) + _2bz *
			(q0q1 + q2q3) - my) + _2bx * q1 * (_2bx * (q0q2 + q1q3) +
			_2bz * (0.5f - q1q1 - q2q2) - mz);

/* normalize step magnitude */
		recipNorm = invSqrt(s0 * s0 + s1 * s1 + s2 * s2 + s3 * s3);
		s0 *= recipNorm;
		s1 *= recipNorm;
		s2 *= recipNorm;
		s3 *= recipNorm;

/* apply feedback */
		qDot1 -= ctx->beta * s0;
		qDot2 -= ctx->beta * s1;
		qDot3 -= ctx->beta * s2;
		qDot4 -= ctx->beta * s3;
	}

/* Integrate rate of change of quaternion to yield quaternion */
	q0 += qDot1 * (1.0f / ctx->rate);
	q1 += qDot2 * (1.0f / ctx->rate);
	q2 += qDot3 * (1.0f / ctx->rate);
	q3 += qDot4 * (1.0f / ctx->rate);

/* normalize quaternion */
	recipNorm = invSqrt(q0 * q0 + q1 * q1 + q2 * q2 + q3 * q3);
	q0 *= recipNorm;
	q1 *= recipNorm;
	q2 *= recipNorm;
	q3 *= recipNorm;

	ctx->q0 = q0;
	ctx->q1 = q1;
	ctx->q2 = q2;
	ctx->q3 = q3;
}

/*
 * Fast inverse square-root
 * See: http://en.wikipedia.org/wiki/Fast_inverse_square_root
 */
static float invSqrt(float x)
{
	float halfx = 0.5f * x;
	float y = x;
	long i = *(long*)&y;
	i = 0x5f3759df - (i>>1);
	y = *(float*)&i;
	y = y * (1.5f - (halfx * y * y));
	return y;
}
