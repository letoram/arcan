#include <stdlib.h>
#include <math.h>

#include "arcan_math.h"
#include <SDL_opengl.h>

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

quat build_quat(float angdeg, float vx, float vy, float vz)
{
	float res = sin( (angdeg / 18.0f * M_PI) / 2.0f);
	quat  ret = {.x = vx * res, .y = vy * res, .z = vz * res, .w = cos(res)};
	return ret;
}

float len_vector(vector invect)
{
	return sqrt(invect.x * invect.x + invect.y * invect.y + invect.z * invect.z);
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
	if (len < 0.0000001)
		return empty;
    
	vector res = {
		.x = invect.x * len,
		.y = invect.y * len,
		.z = invect.z * len
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
	return sqrt(src.x * src.x + src.y * src.y + src.z * src.z + src.w * src.w);
}

quat norm_quat(quat src)
{
	float len = len_quat(src);
	quat res = {.x = src.x / len, .y = src.y / len, .z = src.z / len, .w = src.w / len };
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

float angle_quat(quat a)
{

}

vector lerp_vector(vector a, vector b, float fact)
{
	vector res;
	res.x = a.x + fact * (b.x - a.x);
	res.y = a.y + fact * (b.y - a.y);
	res.z = a.z + fact * (b.z - a.z);
	return res;
}

float lerp_val(float a, float b, float fact)
{
	return a + fact * (b - a);
}

quat lerp_quat(quat a, quat b, float fact)
{
	quat res;
	res.x = a.x + fact * (b.x - a.x);
	res.y = a.y + fact * (b.y - a.y);
	res.z = a.z + fact * (b.z - a.z);
	res.w = a.w + fact * (b.w - a.w);
	return res;
}

float* matr_quat(quat a, float* dmatr)
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

void push_orient_matr(float x, float y, float z, float roll, float pitch, float yaw)
{
	float matr[16];
	quat orient = build_quat_euler(roll, pitch, yaw);
	glTranslatef(x, y, z);
	matr_quat(orient, matr);
	
	glMultMatrixf(matr);
}

quat build_quat_euler(float roll, float pitch, float yaw)
{
	quat res = mul_quat( mul_quat( build_quat(pitch, 1.0, 0.0, 0.0), build_quat(yaw, 0.0, 1.0, 0.0)), build_quat(roll, 0.0, 0.0, 1.0));
	return res;
}

void update_view(orientation* dst, float roll, float pitch, float yaw)
{
	dst->pitchf = pitch;
	dst->rollf = roll;
	dst->yawf = yaw;
	dst->pitch = build_quat(pitch, 1.0, 0.0, 0.0);
	dst->roll  = build_quat(yaw, 0.0, 1.0, 0.0);
	dst->yaw   = build_quat(roll, 0.0, 0.0, 1.0);
	quat res = mul_quat( mul_quat(dst->pitch, dst->yaw), dst->roll );
	matr_quat(res, dst->matr);
    /* cache view-vector as well why not .. */
}

float lerp_fract(unsigned startt, unsigned endt, float ct)
{
	float startf = (float)startt + EPSILON;
	float endf = (float)endt + EPSILON;
	
	if (ct > endt)
		ct = endt;

	float cf = ((float)ct - startf + EPSILON);

	return cf / (endf - startf);
}

/* quatslerp:
 * a, b, t (framefrag) and eps (0.0001),
 * t < 0 (q1) t > 1 q2
 * copy q2 to a3
 * c is dot q1 q3
 * c < 0.0? neg q3, neg c
 * c > 1 - eps
 * 	normalize lerp(q1, q3, t)
 * a = acos(c)
 * quatret = sin(1 - t) * a) * q1 + sin(t * a * q3) / sin a */

/* quatlerp:
 * q1 + t * (q2 - a1) */

