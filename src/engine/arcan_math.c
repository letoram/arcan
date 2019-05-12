/*
 * No copyright claimed, Public Domain
 */

#include <stdlib.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <stdbool.h>

#ifndef M_PI
#define M_PI 3.14159265
#endif

#include "arcan_math.h"

quat default_quat;

/* note:
 * there's some reason and rhyme to some of the naive implementations
 * here and why everything isn't SIMD. While profiling isn't yet in
 * the highest of priorities, we want to the function that rely
 * on (possibly superflous) use of these functions,
 * and first establish is there a way to cache or omitt the call
 * altogether rather than "hiding" the cost by making the
 * calculation very efficient. When this subset is reduced to a minimum,
 * the corresponding functions get their turn in vectorization
 */
#ifndef ARCAN_MATH_SIMD
void mult_matrix_vecf(const float* restrict matrix,
	const float* restrict inv, float* restrict out)
{
	int i;

	for (i=0; i<4; i++)
		out[i] =
		inv[0] * matrix[0*4+i] +
		inv[1] * matrix[1*4+i] +
		inv[2] * matrix[2*4+i] +
		inv[3] * matrix[3*4+i];
}

void multiply_matrix(float* restrict dst,
	const float* restrict a, const float* restrict b)
{
	for (int i = 0; i < 16; i+= 4)
		for (int j = 0; j < 4; j++)
			dst[i+j] =
				b[i]   * a[j]   +
				b[i+1] * a[j+4] +
				b[i+2] * a[j+8] +
				b[i+3] * a[j+12];
}
#endif

void scale_matrix(float* m, float xs, float ys, float zs)
{
	m[0] *= xs; m[4] *= ys; m[8]  *= zs;
	m[1] *= xs; m[5] *= ys; m[9]  *= zs;
	m[2] *= xs; m[6] *= ys; m[10] *= zs;
	m[3] *= xs; m[7] *= ys; m[11] *= zs;
}

void translate_matrix(float* m, float xt, float yt, float zt)
{
	m[12] += xt;
	m[13] += yt;
	m[14] += zt;
/*
 *
 *m[12] = m[0] * xt + m[4] * yt + m[8] * zt + m[12];
 	m[13] = m[1] * xt + m[5] * yt + m[9] * zt + m[13];
 	m[14] = m[2] * xt + m[6] * yt + m[10]* zt + m[14];
	m[15] = m[3] * xt + m[7] * yt + m[11]* zt + m[15];
 */
}

static float midentity[] = {
	1.0, 0.0, 0.0, 0.0,
	0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 1.0, 0.0,
	0.0, 0.0, 0.0, 1.0
};

void identity_matrix(float* m)
{
	memcpy(m, midentity, 16 * sizeof(float));
}

quat quat_lookat(vector pos, vector dstpos)
{
	vector diff = norm_vector( sub_vector(dstpos, pos) );
	float xang = acos( dotp_vector(diff, build_vect(1.0, 0.0, 0.0)) );
	float yang = acos( dotp_vector(diff, build_vect(0.0, 1.0, 0.0)) );
	float zang = acos( dotp_vector(diff, build_vect(0.0, 0.0, 1.0)) );

	return build_quat_taitbryan(xang, yang, zang);
}

/* replacement for gluLookAt */
void matr_lookat(float* m, vector position, vector dstpos, vector up)
{
	vector fwd, side, rup;
	fwd  = norm_vector( sub_vector(dstpos, position) );
	side = norm_vector( crossp_vector( fwd, up ) );
	rup  = crossp_vector( side, fwd );

	m[0] = side.x;
	m[1] = rup.x;
	m[2] = -fwd.x;

	m[4] = side.y;
	m[5] = rup.y;
	m[6] = -fwd.y;

	m[8] = side.z;
	m[9] = rup.z;
	m[10] = -fwd.z;

	m[15] = 1.0;

	translate_matrix(m, -position.x, -position.y, -position.z);
}

void build_orthographic_matrix(float* m, const float left, const float right,
	const float bottom, const float top, const float nearf, const float farf)
{
	float irml = 1.0 / (right - left);
	float itmb = 1.0 / (top - bottom);
	float ifmn = 1.0 / (farf - nearf);

	m[0]  = 2.0f * irml;
	m[1]  = 0.0f;
	m[2]  = 0.0f;
	m[3]  = 0.0;

	m[4]  = 0.0f;
	m[5]  = 2.0f * itmb;
	m[6]  = 0.0f;
	m[7]  = 0.0;

	m[8]  = 0.0f;
	m[9]  = 0.0f;
	m[10] = 2.0f * ifmn;
	m[11] = 0.0;

	m[12] = -(right+left) * irml;
	m[13] = -(top+bottom) * itmb;
	m[14] = -(farf+nearf) * ifmn;
	m[15] = 1.0f;
}

void build_projection_matrix(float* m,
	float nearv, float farv, float aspect, float fov)
{
	const float h = 1.0f / tan(fov * (M_PI / 360.0));
	float neg_depth = nearv - farv;

	m[0]  = h / aspect; m[1]  = 0; m[2]  = 0;  m[3] = 0;
	m[4]  = 0; m[5]  = h; m[6]  = 0;  m[7] = 0;
	m[8]  = 0; m[9]  = 0; m[10] = (farv + nearv) / neg_depth; m[11] =-1;
	m[12] = 0; m[13] = 0; m[14] = 2.0f * (nearv * farv) / neg_depth; m[15] = 0;
}

int project_matrix(float objx, float objy, float objz,
			const float modelMatrix[16], const float projMatrix[16],
			const int viewport[4], float *winx, float *winy, float *winz)
{
	_Alignas(16) float in[4];
	_Alignas(16) float out[4];

	in[0]=objx;
	in[1]=objy;
	in[2]=objz;
	in[3]=1.0;

	mult_matrix_vecf(modelMatrix, in, out);
	mult_matrix_vecf(projMatrix, out, in);

	if (in[3] == 0.0)
		return 0;

	in[0] /= in[3];
	in[1] /= in[3];
	in[2] /= in[3];

/* Map x, y and z to range 0-1 */
	in[0] = in[0] * 0.5 + 0.5;
	in[1] = in[1] * 0.5 + 0.5;
	in[2] = in[2] * 0.5 + 0.5;

/* Map x,y to viewport */
	in[0] = in[0] * viewport[2] + viewport[0];
	in[1] = in[1] * viewport[3] + viewport[1];

	*winx=in[0];
	*winy=in[1];
	*winz=in[2];
	return 1;
}

int pinpoly(int nvert, float *vertx, float *verty, float testx, float testy)
{
	int i, j, c = 0;
	for (i = 0, j = nvert-1; i < nvert; j = i++) {
		if ( ((verty[i]>testy) != (verty[j]>testy)) &&
			(testx < (vertx[j]-vertx[i]) * (testy-verty[i]) /
			(verty[j]-verty[i]) + vertx[i]) )
			c = !c;
	}
	return c;
}

vector build_vect_polar(const float phi, const float theta)
{
	vector res = {.x = sinf(phi) * cosf(theta),
		.y = sinf(phi) * sinf(theta), .z = sinf(phi)};
	return res;
}

vector build_vect(const float x, const float y, const float z)
{
	vector res = {.x = x, .y = y, .z = z};
	return res;
}

vector mul_vectorf(vector a, float f)
{
	vector res = {.x = a.x * f, .y = a.y * f, .z = a.z * f};
	return res;
}

quat build_quat(float angdeg, float vx, float vy, float vz)
{
	quat ret;
	float ang = angdeg / 180.f * M_PI;
	float res = sinf(ang / 2.0f);

	ret.w = cosf(ang / 2.0f);
	ret.x = vx * res;
	ret.y = vy * res;
	ret.z = vz * res;

	return ret;
}

float len_vector(vector invect)
{
	return sqrt(invect.x * invect.x +
		invect.y * invect.y + invect.z * invect.z);
}

vector crossp_vector(vector a, vector b)
{
	vector res = {
		.x = a.y * b.z - a.z * b.y,
		.y = a.z * b.x - a.x * b.z,
		.z = a.x * b.y - a.y * b.x
	};
	return res;
}

float dotp_vector(vector a, vector b)
{
	return a.x * b.x + a.y * b.y + a.z * b.z;
}

vector sub_vector(vector a, vector b)
{
	vector res = {.x = a.x - b.x,
	.y = a.y - b.y,
	.z = a.z - b.z};

	return res;
}

vector add_vector(vector a, vector b)
{
	vector res = {.x = a.x + b.x,
	.y = a.y + b.y,
	.z = a.z + b.z};

	return res;
}

vector mul_vector(vector a, vector b)
{
	vector res = {
		.x = a.x * b.x,
		.y = a.y * b.y,
		.z = a.z * b.z
	};

	return res;
}

vector norm_vector(vector invect){
	vector empty = {.x = 0.0, .y = 0.0, .z = 0.0};
	float len = len_vector(invect);
	if (len < EPSILON)
		return empty;

	vector res = {
		.x = invect.x / len,
		.y = invect.y / len,
		.z = invect.z / len
	};

	return res;
}

quat inv_quat(quat src)
{
	quat res = {.x = -src.x, .y = -src.y, .z = -src.z, .w = src.w };
	return res;
}

float len_quat(quat src)
{
	return sqrt(src.x * src.x + src.y *
		src.y + src.z * src.z + src.w * src.w);
}

quat norm_quat(quat src)
{
	float val = src.x * src.x + src.y *
		src.y + src.z * src.z + src.w * src.w;

	if (val > 0.99999 && val < 1.000001)
		return src;

	val = sqrtf(val);
	quat res = {.x = src.x / val, .y = src.y / val,
		.z = src.z / val, .w = src.w / val};
	return res;
}

quat div_quatf(quat a, float v)
{
	quat res = {
		.x = a.x / v,
		.y = a.y / v,
		.z = a.z / v,
		.w = a.z / v
	};
	return res;
}

quat mul_quatf(quat a, float v)
{
	quat res = {
		.x = a.x * v,
		.y = a.y * v,
		.z = a.z * v,
		.w = a.w * v
	};
	return res;
}

quat mul_quat(quat a, quat b)
{
	quat res;
	res.w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z;
	res.x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y;
	res.y = a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z;
	res.z = a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x;
	return res;
}

quat add_quat(quat a, quat b)
{
	quat res;
	res.x = a.x + b.x;
	res.y = a.y + b.y;
	res.z = a.z + b.z;
	res.w = a.w + b.w;

	return res;
}

float dot_quat(quat a, quat b)
{
	return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}

vector angle_quat(quat a)
{
	float sqw = a.w*a.w;
	float sqx = a.x*a.x;
	float sqy = a.y*a.y;
	float sqz = a.z*a.z;

	vector euler;
	euler.x = atan2f(2.f * (a.x*a.y + a.z*a.w), sqx - sqy - sqz + sqw);
	euler.y = asinf(-2.f * (a.x*a.z - a.y*a.w));
	euler.z = atan2f(2.f * (a.y*a.z + a.x*a.w), -sqx - sqy + sqz + sqw);

	float mpi = 180.0 / M_PI;
	euler.x *= mpi;
	euler.y *= mpi;
	euler.z *= mpi;

	return euler;
}

vector lerp_vector(vector a, vector b, float fact)
{
	vector res;
	res.x = a.x + fact * (b.x - a.x);
	res.y = a.y + fact * (b.y - a.y);
	res.z = a.z + fact * (b.z - a.z);
	return res;
}

float interp_1d_sine(float sv, float ev, float fract)
{
	return sv + (ev - sv) * sinf(0.5 * fract * M_PI);
}

float interp_1d_linear(float sv, float ev, float fract)
{
	return sv + (ev - sv) * fract;
}

float interp_1d_smoothstep(float sv, float ev, float fract)
{
	float res = (fract - 0.1) / (0.9 - 0.1);
	if (res < 0)
		res = 0.0;
	else if (res > 1.0)
		res = 1.0;
	res = res * res * (3.0 - 2.0 * res);
	return sv + res * (ev - sv);
}

vector interp_3d_smoothstep(vector sv, vector ev, float fract)
{
	return (vector){
		.x = interp_1d_smoothstep(sv.x, ev.x, fract),
		.y = interp_1d_smoothstep(sv.y, ev.y, fract),
		.z = interp_1d_smoothstep(sv.z, ev.z, fract)
	};
}

vector interp_3d_linear(vector sv, vector ev, float fract)
{
	vector res;
	res.x = sv.x + (ev.x - sv.x) * fract;
	res.y = sv.y + (ev.y - sv.y) * fract;
	res.z = sv.z + (ev.z - sv.z) * fract;
	return res;
}

float interp_1d_expout(float sv, float ev, float fract)
{
	return fract < EPSILON ? sv :
		sv + (ev - sv) * (1.0 - powf(2.0, -10.0 * fract));
}

float interp_1d_expin(float sv, float ev, float fract)
{
	return fract < EPSILON ? sv :
		sv + (ev - sv) * powf(2, 10 * (fract - 1.0));
}

float interp_1d_expinout(float sv, float ev, float fract)
{
	return fract < EPSILON ? sv :
			fract > 1.0 - EPSILON ? ev :
				fract < 0.5 ?
					sv + (ev - sv) * ( 0.5 * powf(2, (20 * fract) - 10)) :
					sv + (ev - sv) * ((-0.5 * powf(2, (-20 * fract) + 10)) + 1);
}

vector interp_3d_expin(vector sv, vector ev, float fract)
{
	vector res;

	res.x = fract < EPSILON ? sv.x :
		sv.x + (ev.x - sv.x) * powf(2, 10 * (fract - 1.0));

	res.y = fract < EPSILON ? sv.x :
		sv.y + (ev.y - sv.y) * powf(2, 10 * (fract - 1.0));

	res.z = fract < EPSILON ? sv.x :
		sv.z + (ev.z - sv.z) * powf(2, 10 * (fract - 1.0));

	return res;
}

vector interp_3d_expinout(vector sv, vector ev, float fract)
{
	vector res;
	res.x = fract < EPSILON ? sv.x :
			fract > 1.0 - EPSILON ? ev.x :
				fract < 0.5 ?
					sv.x + (ev.x - sv.x) * ( 0.5 * powf(2, (20 * fract) - 10)) :
					sv.x + (ev.x - sv.x) * ((-0.5 * powf(2, (-20 * fract) + 10)) + 1);

	res.y = fract < EPSILON ? sv.y :
			fract > 1.0 - EPSILON ? ev.y :
				fract < 0.5 ?
					sv.y + (ev.y - sv.y) * ( 0.5 * powf(2, (20 * fract) - 10)) :
					sv.y + (ev.y - sv.y) * ((-0.5 * powf(2, (-20 * fract) + 10)) + 1);

	res.z = fract < EPSILON ? sv.z :
			fract > 1.0 - EPSILON ? ev.z :
				fract < 0.5 ?
					sv.z + (ev.z - sv.z) * ( 0.5 * powf(2, (20 * fract) - 10)) :
					sv.z + (ev.z - sv.z) * ((-0.5 * powf(2, (-20 * fract) + 10)) + 1);

	return res;
}

vector interp_3d_expout(vector sv, vector ev, float fract)
{
	vector res;

	res.x = fract < EPSILON ? sv.x :
		sv.x + (ev.x - sv.x) * (1.0 - powf(2.0, -10.0 * fract));

	res.y = fract < EPSILON ? sv.x :
		sv.y + (ev.y - sv.y) * (1.0 - powf(2.0, -10.0 * fract));

	res.z = fract < EPSILON ? sv.x :
		sv.z + (ev.z - sv.z) * (1.0 - powf(2.0, -10.0 * fract));

	return res;
}

vector interp_3d_sine(vector sv, vector ev, float fract)
{
	vector res;
	res.x = sv.x + (ev.x - sv.x) * sinf(0.5 * fract * M_PI);
	res.y = sv.y + (ev.y - sv.y) * sinf(0.5 * fract * M_PI);
	res.z = sv.z + (ev.z - sv.z) * sinf(0.5 * fract * M_PI);
	return res;
}

static inline quat slerp_quatfl(quat a, quat b, float fact, bool r360)
{
	float weight_a, weight_b;
	bool flip = false;

/* r360 if delta > 180degrees) */
	float ct = dot_quat(a, b);
	if (r360 && ct > 1.0){
		ct   = -ct;
		flip = true;
	}

	float th  = acos(ct);
	float sth = sin(th);

	if (sth > 0.005f){
		weight_a = sin( (1.0f - fact) * th) / sth;
		weight_b = sin( fact * th   )       / sth;
	}
	else {
/* small steps, only linear */
		weight_a = 1.0f - fact;
		weight_b = fact;
	}

	if (flip)
		weight_b = -weight_b;

	return add_quat(mul_quatf(a, weight_a), mul_quatf(b, weight_b));
}

static inline quat nlerp_quatfl(quat a, quat b, float fact, bool r360)
{
	float tinv = 1.0f - fact;
	quat rq;

	if (r360 && dot_quat(a, b) < 0.0f)
		rq = add_quat(mul_quatf(a, tinv), mul_quatf(a, -fact));
	else
		rq = add_quat(mul_quatf(a, tinv), mul_quatf(b,  fact));

	return norm_quat(rq);
}

quat slerp_quat180(quat a, quat b, float fact){
	return slerp_quatfl(a, b, fact, false);
}

quat slerp_quat360(quat a, quat b, float fact){
	return slerp_quatfl(a, b, fact, true );
}

quat nlerp_quat180(quat a, quat b, float fact){
	return nlerp_quatfl(a, b, fact, false);
}

quat nlerp_quat360(quat a, quat b, float fact){
	return nlerp_quatfl(a, b, fact, true );
}

float* matr_rotatef(float ang, float* dmatr)
{
	float cv = cosf(ang);
	float sf = sinf(ang);
	memcpy(dmatr, midentity, 16 * sizeof(float));
	dmatr[0] = cv;
	dmatr[5] = cv;
	dmatr[1] = sf;
	dmatr[4] = -sf;
	return dmatr;
}

float* matr_quatf(quat a, float* dmatr)
{
	if (dmatr){
		dmatr[0] = 1.0f - 2.0f * (a.y * a.y + a.z * a.z);
		dmatr[1] = 2.0f * (a.x * a.y + a.z * a.w);
		dmatr[2] = 2.0f * (a.x * a.z - a.y * a.w);
		dmatr[3] = 0.0f;
		dmatr[4] = 2.0f * (a.x * a.y - a.z * a.w);
		dmatr[5] = 1.0f - 2.0f * (a.x * a.x + a.z * a.z);
		dmatr[6] = 2.0f * (a.z * a.y + a.x * a.w);
		dmatr[7] = 0.0f;
		dmatr[8] = 2.0f * (a.x * a.z + a.y * a.w);
		dmatr[9] = 2.0f * (a.y * a.z - a.x * a.w);
		dmatr[10]= 1.0f - 2.0f * (a.x * a.x + a.y * a.y);
		dmatr[11]= 0.0f;
		dmatr[12]= 0.0f;
		dmatr[13]= 0.0f;
		dmatr[14]= 0.0f;
		dmatr[15]= 1.0f;
	}
	return dmatr;
}

/*
 * Plucked from MESA
 */
bool matr_invf(const float* restrict m, float* restrict out)
{
	float inv[16], det;
	int i;

	inv[0] =
		m[5]  * m[10] * m[15] -
		m[5]  * m[11] * m[14] -
		m[9]  * m[6]  * m[15] +
		m[9]  * m[7]  * m[14] +
		m[13] * m[6]  * m[11] -
		m[13] * m[7]  * m[10];

	inv[4] =
		-m[4] * m[10] * m[15] +
		 m[4]  * m[11] * m[14] +
		 m[8]  * m[6]  * m[15] -
		 m[8]  * m[7]  * m[14] -
		 m[12] * m[6]  * m[11] +
		 m[12] * m[7]  * m[10];

	inv[8] =
		m[4]  * m[9]  * m[15] -
		m[4]  * m[11] * m[13] -
		m[8]  * m[5]  * m[15] +
		m[8]  * m[7]  * m[13] +
		m[12] * m[5]  * m[11] -
		m[12] * m[7]  * m[9];

	inv[12] =
		-m[4]  * m[9]  * m[14] +
		 m[4]  * m[10] * m[13] +
		 m[8]  * m[5]  * m[14] -
		 m[8]  * m[6]  * m[13] -
		 m[12] * m[5]  * m[10] +
		 m[12] * m[6]  * m[9];

	inv[1] =
		-m[1] * m[10] * m[15] +
		 m[1]  * m[11] * m[14] +
		 m[9]  * m[2]  * m[15] -
		 m[9]  * m[3]  * m[14] -
		 m[13] * m[2]  * m[11] +
		 m[13] * m[3]  * m[10];

	inv[5] =
		m[0]  * m[10] * m[15] -
		m[0]  * m[11] * m[14] -
		m[8]  * m[2]  * m[15] +
		m[8]  * m[3]  * m[14] +
		m[12] * m[2]  * m[11] -
		m[12] * m[3]  * m[10];

	inv[9] =
		-m[0]  * m[9]  * m[15] +
		 m[0]  * m[11] * m[13] +
		 m[8]  * m[1]  * m[15] -
		 m[8]  * m[3]  * m[13] -
		 m[12] * m[1]  * m[11] +
		 m[12] * m[3]  * m[9];

	inv[13] =
		m[0]  * m[9] * m[14] -
		m[0]  * m[10] * m[13] -
		m[8]  * m[1] * m[14] +
		m[8]  * m[2] * m[13] +
		m[12] * m[1] * m[10] -
		m[12] * m[2] * m[9];

	inv[2] =
		m[1]  * m[6] * m[15] -
		m[1]  * m[7] * m[14] -
		m[5]  * m[2] * m[15] +
		m[5]  * m[3] * m[14] +
		m[13] * m[2] * m[7] -
		m[13] * m[3] * m[6];

	inv[6] =
		-m[0]  * m[6] * m[15] +
		 m[0]  * m[7] * m[14] +
		 m[4]  * m[2] * m[15] -
		 m[4]  * m[3] * m[14] -
		 m[12] * m[2] * m[7] +
		 m[12] * m[3] * m[6];

	inv[10] =
		m[0]  * m[5] * m[15] -
		m[0]  * m[7] * m[13] -
		m[4]  * m[1] * m[15] +
		m[4]  * m[3] * m[13] +
		m[12] * m[1] * m[7] -
		m[12] * m[3] * m[5];

	inv[14] =
		-m[0] * m[5] * m[14] +
		 m[0]  * m[6] * m[13] +
		 m[4]  * m[1] * m[14] -
		 m[4]  * m[2] * m[13] -
		 m[12] * m[1] * m[6] +
		 m[12] * m[2] * m[5];

	inv[3] =
		-m[1] * m[6] * m[11] +
		 m[1] * m[7] * m[10] +
		 m[5] * m[2] * m[11] -
		 m[5] * m[3] * m[10] -
		 m[9] * m[2] * m[7] +
		 m[9] * m[3] * m[6];

	inv[7] =
		m[0] * m[6] * m[11] -
		m[0] * m[7] * m[10] -
		m[4] * m[2] * m[11] +
		m[4] * m[3] * m[10] +
		m[8] * m[2] * m[7] -
		m[8] * m[3] * m[6];

	inv[11] =
		-m[0] * m[5] * m[11] +
		 m[0] * m[7] * m[9] +
		 m[4] * m[1] * m[11] -
		 m[4] * m[3] * m[9] -
		 m[8] * m[1] * m[7] +
		 m[8] * m[3] * m[5];

	inv[15] =
		m[0] * m[5] * m[10] -
		m[0] * m[6] * m[9] -
		m[4] * m[1] * m[10] +
		m[4] * m[2] * m[9] +
		m[8] * m[1] * m[6] -
		m[8] * m[2] * m[5];

	det =
		m[0] * inv[0] + m[1] * inv[4] +
		m[2] * inv[8] + m[3] * inv[12];

	if (det == 0)
		return false;

	det = 1.0 / det;

	for (i = 0; i < 16; i++)
		out[i] = inv[i] * det;

	return true;
}

double* matr_quat(quat a, double* dmatr)
{
	if (dmatr){
		dmatr[0] = 1.0f - 2.0f * (a.y * a.y + a.z * a.z);
		dmatr[1] = 2.0f * (a.x * a.y + a.z * a.w);
		dmatr[2] = 2.0f * (a.x * a.z - a.y * a.w);
		dmatr[3] = 0.0f;
		dmatr[4] = 2.0f * (a.x * a.y - a.z * a.w);
		dmatr[5] = 1.0f - 2.0f * (a.x * a.x + a.z * a.z);
		dmatr[6] = 2.0f * (a.z * a.y + a.x * a.w);
		dmatr[7] = 0.0f;
		dmatr[8] = 2.0f * (a.x * a.z + a.y * a.w);
		dmatr[9] = 2.0f * (a.y * a.z - a.x * a.w);
		dmatr[10]= 1.0f - 2.0f * (a.x * a.x + a.y * a.y);
		dmatr[11]= 0.0f;
		dmatr[12]= 0.0f;
		dmatr[13]= 0.0f;
		dmatr[14]= 0.0f;
		dmatr[15]= 1.0f;
	}
	return dmatr;
}

quat build_quat_taitbryan(float roll, float pitch, float yaw)
{
	roll  = fmodf(roll + 180.f, 360.f) - 180.f;
	pitch = fmodf(pitch+ 180.f, 360.f) - 180.f;
	yaw   = fmodf(yaw  + 180.f, 360.f) - 180.f;

	quat res = mul_quat( mul_quat( build_quat(pitch, 1.0, 0.0, 0.0),
		build_quat(yaw, 0.0, 1.0, 0.0)), build_quat(roll, 0.0, 0.0, 1.0));
	return res;
}

void update_view(orientation* dst, float roll, float pitch, float yaw)
{
	dst->pitchf = pitch;
	dst->rollf = roll;
	dst->yawf = yaw;
	quat pitchq = build_quat(pitch, 1.0, 0.0, 0.0);
	quat rollq  = build_quat(yaw, 0.0, 1.0, 0.0);
	quat yawq   = build_quat(roll, 0.0, 0.0, 1.0);
	quat res = mul_quat( mul_quat(pitchq, yawq), rollq );
	matr_quatf(res, dst->matr);
}

vector taitbryan_forwardv(float roll, float pitch, float yaw)
{
	_Alignas(16) float dmatr[16];

	quat pitchq = build_quat(pitch, 1.0, 0.0, 0.0);
	quat yawq   = build_quat(yaw,   0.0, 1.0, 0.0);

	matr_quatf(pitchq, dmatr);

	vector view;
	view.y = -dmatr[9];
	quat res = mul_quat(pitchq, yawq);
	matr_quatf(res, dmatr);
	view.x = -dmatr[8];
	view.z = dmatr[10];

	return view;
}

static inline void normalize_plane(float* pl)
{
	float mag = 1.0f / sqrtf(pl[0] * pl[0] + pl[1] * pl[1] + pl[2] * pl[2]);
	pl[0] *= mag;
	pl[1] *= mag;
	pl[2] *= mag;
	pl[3] *= mag;
}

bool frustum_point(const float frustum[6][4],
	const float x, const float y, const float z)
{
	for (int i = 0; i < 6; i++)
		if (frustum[i][0] * x +
				frustum[i][1] * y +
				frustum[i][2] * z +
				frustum[i][3] <= 0.0f)
			return false;

	return true;
}

enum cstate frustum_aabb(const float frustum[6][4],
	const float x1, const float y1, const float z1,
	const float x2, const float y2, const float z2)
{
	enum cstate res = inside;
	for (int i = 0; i < 6; i++){
		if (frustum[i][0] * x1 + frustum[i][1] * y1 +
			frustum[i][2] * z1 + frustum[i][3] > 0.0f)
			continue;

		res = intersect;

		if (frustum[i][0] * x2 + frustum[i][1] * y1 +
			frustum[i][2] * z1 + frustum[i][3] > 0.0f)
			continue;

		if (frustum[i][0] * x1 + frustum[i][1] * y2 +
			frustum[i][2] * z1 + frustum[i][3] > 0.0f)
			continue;

		if (frustum[i][0] * x2 + frustum[i][1] * y2 +
			frustum[i][2] * z1 + frustum[i][3] > 0.0f)
			continue;

		if (frustum[i][0] * x1 + frustum[i][1] * y1 +
			frustum[i][2] * z2 + frustum[i][3] > 0.0f)
			continue;

		if (frustum[i][0] * x2 + frustum[i][1] * y1 +
			frustum[i][2] * z2 + frustum[i][3] > 0.0f)
			continue;

		if (frustum[i][0] * x1 + frustum[i][1] * y2 +
			frustum[i][2] * z2 + frustum[i][3] > 0.0f)
			continue;

		if (frustum[i][0] * x2 + frustum[i][1] * y2 +
			frustum[i][2] * z2 + frustum[i][3] > 0.0f)
			continue;
	}

	return res;
}

enum cstate frustum_sphere(const float frustum[6][4],
	const float x, const float y, const float z, const float radius)
{
	for (int i = 0; i < 6; i++){
		float dist =
			frustum[i][0] * x +
			frustum[i][1] * y +
			frustum[i][2] * z +
			frustum[i][3];

		if (dist < -radius)
			return outside;

		else if (fabs(dist) < radius)
			return intersect;
	}

	return inside;
}

void update_frustum(float* prjm, float* mvm, float frustum[6][4])
{
	float mmr[16];
/* multiply modelview with projection */
	multiply_matrix(mmr, mvm, prjm);

/* extract and normalize planes */
	frustum[0][0] = mmr[3]  + mmr[0]; // left
	frustum[0][1] = mmr[7]  + mmr[4];
	frustum[0][2] = mmr[11] + mmr[8];
	frustum[0][3] = mmr[15] + mmr[12];
	normalize_plane(frustum[0]);

	frustum[1][0] = mmr[3]  - mmr[0]; // right
	frustum[1][1] = mmr[7]  - mmr[4];
	frustum[1][2] = mmr[11] - mmr[8];
	frustum[1][3] = mmr[15] - mmr[12];
	normalize_plane(frustum[1]);

	frustum[2][0] = mmr[3]  - mmr[1]; // top
	frustum[2][1] = mmr[7]  - mmr[5];
	frustum[2][2] = mmr[11] - mmr[9];
	frustum[2][3] = mmr[15] - mmr[13];
	normalize_plane(frustum[2]);

	frustum[3][0] = mmr[3]  + mmr[1]; // bottom
	frustum[3][1] = mmr[7]  + mmr[5];
	frustum[3][2] = mmr[11] + mmr[9];
	frustum[3][3] = mmr[15] + mmr[13];
	normalize_plane(frustum[3]);

	frustum[4][0] = mmr[3]  + mmr[2]; // near
	frustum[4][1] = mmr[7]  + mmr[6];
	frustum[4][2] = mmr[11] + mmr[10];
	frustum[4][3] = mmr[15] + mmr[14];
	normalize_plane(frustum[4]);

	frustum[5][0] = mmr[3]  - mmr[2]; // far
	frustum[5][1] = mmr[7]  - mmr[6];
	frustum[5][2] = mmr[11] - mmr[10];
	frustum[5][3] = mmr[15] - mmr[14];
	normalize_plane(frustum[5]);
}

void arcan_math_init()
{
	default_quat = build_quat_taitbryan(0, 0, 0);
}

bool ray_plane(vector* pos, vector* dir,
	vector* plane_pos, vector* plane_normal, vector* intersect)
{
	float den = dotp_vector(*plane_normal, *dir);
	if (den > EPSILON){
		vector diff = sub_vector(*pos, *plane_pos);
		float tt = dotp_vector(diff, *plane_normal);
		*intersect = add_vector(mul_vectorf(*dir, tt), *pos);
		return tt >= 0;
	}

	return false;
}

bool ray_sphere(const vector* ray_pos, const vector* ray_dir,
	const vector* sphere_pos, float sphere_rad, float* d1, float *d2)
{
	float den, b;
	vector delta = sub_vector(*ray_pos, *sphere_pos);
	b = -1.0 * dotp_vector(delta, *ray_dir);
	den = b * b - dotp_vector(delta, delta) + sphere_rad * sphere_rad;
	if (den < 0)
		return false;

	den = sqrtf(den);

	*d1 = b - den;
	*d2 = b + den;

	if (*d2 < 0)
		return false;

	if (*d1 < 0)
		*d1 = 0;

	return true;
}

vector unproject_matrix(float dev_x, float dev_y, float dev_z,
	const float* restrict view, const float* restrict proj)
{
/* combine modelview and projection, then invert */
	_Alignas(16) float invm[16];
	_Alignas(16) float vpm[16];
	multiply_matrix(vpm, proj, view);
	matr_invf(vpm, invm);

/* x y z should be device coordinates (-1..1) */
	_Alignas(16) float wndv[4] = {dev_x, dev_y, dev_z, 1.0};
	_Alignas(16) float upv[4];
/* transform device coordinates */

	mult_matrix_vecf(invm, wndv, upv);

	upv[3] = 1.0 / upv[3];

	vector vs = {
		.x = upv[0] * upv[3],
		.y = upv[1] * upv[3],
		.z = upv[2] * upv[3]
	};

	return vs;
}

void dev_coord(float* out_x, float* out_y, float* out_z,
	int x, int y, int w, int h, float near, float far)
{
	*out_x = (2.0 * (float) x ) / (float) w - 1.0;
	*out_y = 1.0 - (2.0 * (float) y ) / (float) h;
	*out_z = (0.0 - near) / (far - near);
}

