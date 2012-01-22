#include <stdlib.h>
#include <stdio.h>
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
	float val = src.x * src.x + src.y * src.y + src.z * src.z + src.w * src.w;

	if (val > 0.99999 && val < 1.000001)
		return src;

	val = sqrtf(val);
	quat res = {.x = src.x / val, .y = src.y / val, .z = src.z / val, .w = src.w / val};
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

float lerp_val(float a, float b, float fact)
{
	return a + fact * (b - a);
}

quat lerp_quat(quat a, quat b, float fact)
{
//	printf("a (%f, %f, %f, %f) -- b (%f, %f, %f, %f) - %f\n", a.x, a.y, a.z, a.w, b.x, b.y, b.z, b.w, fact);
	quat res = add_quat( mul_quatf(a, 1 - fact), mul_quatf(b, fact) );
	return res;
}

quat slerp_quat(quat a, quat b, float fact)
{
	float dp = dot_quat(a, b);
	quat c;
	
	if (dp < 0){
		dp = -dp;
		c = inv_quat(b);
	} else c = b;

	if (dp < 0.95f){
		float ang = acosf(dp);
		quat res = add_quat( mul_quatf(a, sinf(ang * (1-fact))), mul_quatf(c, sinf(ang * fact)) );
		return div_quatf(res, sinf(ang));
	} else
		return lerp_quat(a, c, fact);
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
	quat pitchq = build_quat(pitch, 1.0, 0.0, 0.0);
	quat rollq  = build_quat(yaw, 0.0, 1.0, 0.0);
	quat yawq   = build_quat(roll, 0.0, 0.0, 1.0);
	quat res = mul_quat( mul_quat(pitchq, yawq), rollq );
	matr_quat(res, dst->matr);
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
