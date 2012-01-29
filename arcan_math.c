#include <stdlib.h>
#include <stdio.h>
#include <math.h>

#include "arcan_math.h"
#include <SDL_opengl.h>

static void mult_matrix_vecf(const float matrix[16], const float in[4], float out[4])
{
	int i;

	for (i=0; i<4; i++) {
		out[i] =
		in[0] * matrix[0*4+i] +
		in[1] * matrix[1*4+i] +
		in[2] * matrix[2*4+i] +
		in[3] * matrix[3*4+i];
	}
}

void build_projection_matrix(float nearv, float farv, float aspect, float fov, float m[16])
{
	const float h = 1.0f / tan(fov * (M_PI / 360.0));
	float neg_depth = nearv - farv;

	m[0]  = h / aspect; m[1]  = 0; m[2]  = 0;  m[3] = 0;
	m[4]  = 0; m[5]  = h; m[6]  = 0;  m[7] = 0;
	m[8]  = 0; m[9]  = 0; m[10] = (farv + nearv) / neg_depth; m[11] =-1;
	m[12] = 0; m[13] = 0; m[14] = 2.0f * (nearv * farv) / neg_depth; m[15] = 0;
}

int gluProjectf(float objx, float objy, float objz,
		   const float modelMatrix[16],
		   const float projMatrix[16],
		   const int viewport[4],
		   float *winx, float *winy, float *winz)
{
	float in[4];
	float out[4];

	in[0]=objx;
	in[1]=objy;
	in[2]=objz;
	in[3]=1.0;
	mult_matrix_vecf(modelMatrix, in, out);
	mult_matrix_vecf(projMatrix, out, in);
	if (in[3] == 0.0) return(GL_FALSE);
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
	return(GL_TRUE);
}

int pinpoly(int nvert, float *vertx, float *verty, float testx, float testy)
{
	int i, j, c = 0;
	for (i = 0, j = nvert-1; i < nvert; j = i++) {
		if ( ((verty[i]>testy) != (verty[j]>testy)) &&
			(testx < (vertx[j]-vertx[i]) * (testy-verty[i]) / (verty[j]-verty[i]) + vertx[i]) )
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
	const float thresh = 1.0 - EPSILON;
	if (dp > thresh)
			return lerp_quat(a, b, fact);

	if (dp < -1.0f) dp = -1.0f;
	else if (dp > 1.0f) dp = 1.0f;

	float theta = acosf(dp) * fact;
	quat c = mul_quatf(a, dp);
	a = add_quat(b, inv_quat(c));

	return norm_quat(a);
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

void push_orient_matr(float x, float y, float z, float roll, float pitch, float yaw)
{
	float matr[16];
	quat orient = build_quat_euler(roll, pitch, yaw);
	glTranslatef(x, y, z);
	matr_quatf(orient, matr);

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
	matr_quatf(res, dst->matr);
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


static inline void normalize_plane(float* pl)
{
	float mag = 1.0f / sqrtf(pl[0] * pl[0] + pl[1] * pl[1] + pl[2] * pl[2]);
	pl[0] *= mag;
	pl[1] *= mag;
	pl[2] *= mag;
	pl[3] *= mag;
}


void update_frustum(float* prjm, float* mvm, float frustum[6][4])
{
	float mmr[16];
/* multiply modelview with projection */
	mmr[0] = mvm[0] * prjm[0] + mvm[1] * prjm[4] + mvm[2] * prjm[8] + mvm[3] * prjm[12];
	mmr[1] = mvm[0] * prjm[1] + mvm[1] * prjm[5] + mvm[2] * prjm[9] + mvm[3] * prjm[13];
	mmr[2] = mvm[0] * prjm[2] + mvm[1] * prjm[6] + mvm[2] * prjm[10] + mvm[3] * prjm[14];
	mmr[3] = mvm[0] * prjm[3] + mvm[1] * prjm[7] + mvm[2] * prjm[11] + mvm[3] * prjm[15];
	mmr[4] = mvm[4] * prjm[0] + mvm[5] * prjm[4] + mvm[6] * prjm[8] + mvm[7] * prjm[12];
	mmr[5] = mvm[4] * prjm[1] + mvm[5] * prjm[5] + mvm[6] * prjm[9] + mvm[7] * prjm[13];
	mmr[6] = mvm[4] * prjm[2] + mvm[5] * prjm[6] + mvm[6] * prjm[10] + mvm[7] * prjm[14];
	mmr[7] = mvm[4] * prjm[3] + mvm[5] * prjm[7] + mvm[6] * prjm[11] + mvm[7] * prjm[15];
	mmr[8] = mvm[8] * prjm[0] + mvm[9] * prjm[4] + mvm[10] * prjm[8] + mvm[11] * prjm[12];
	mmr[9] = mvm[8] * prjm[1] + mvm[9] * prjm[5] + mvm[10] * prjm[9] + mvm[11] * prjm[13];
	mmr[10] = mvm[8] * prjm[2] + mvm[9] * prjm[6] + mvm[10] * prjm[10] + mvm[11] * prjm[14];
	mmr[11] = mvm[8] * prjm[3] + mvm[9] * prjm[7] + mvm[10] * prjm[11] + mvm[11] * prjm[15];
	mmr[12] = mvm[12] * prjm[0] + mvm[13] * prjm[4] + mvm[14] * prjm[8] + mvm[15] * prjm[12];
	mmr[13] = mvm[12] * prjm[1] + mvm[13] * prjm[5] + mvm[14] * prjm[9] + mvm[15] * prjm[13];
	mmr[14] = mvm[12] * prjm[2] + mvm[13] * prjm[6] + mvm[14] * prjm[10] + mvm[15] * prjm[14];
	mmr[15] = mvm[12] * prjm[3] + mvm[13] * prjm[7] + mvm[14] * prjm[11] + mvm[15] * prjm[15];

/* extract and normalize planes */
	frustum[0][0] = mmr[3] + mmr[0]; // left
	frustum[0][1] = mmr[7] + mmr[4];
	frustum[0][2] = mmr[11] + mmr[8];
	frustum[0][3] = mmr[15] + mmr[12];
	normalize_plane(frustum[0]);

	frustum[1][0] = mmr[3] - mmr[0]; // right
	frustum[1][1] = mmr[7] - mmr[4];
	frustum[1][2] = mmr[11] - mmr[8];
	frustum[1][3] = mmr[15] - mmr[12];
	normalize_plane(frustum[1]);

	frustum[2][0] = mmr[3] - mmr[1]; // top
	frustum[2][1] = mmr[7] - mmr[5];
	frustum[2][2] = mmr[11] - mmr[9];
	frustum[2][3] = mmr[15] - mmr[13];
	normalize_plane(frustum[2]);

	frustum[3][0] = mmr[3] + mmr[1]; // bottom
	frustum[3][1] = mmr[7] + mmr[5];
	frustum[3][2] = mmr[11] + mmr[9];
	frustum[3][3] = mmr[15] + mmr[13];
	normalize_plane(frustum[3]);

	frustum[4][0] = mmr[3] + mmr[2]; // near
	frustum[4][1] = mmr[7] + mmr[6];
	frustum[4][2] = mmr[11] + mmr[10];
	frustum[4][3] = mmr[15] + mmr[14];
	normalize_plane(frustum[4]);

	frustum[5][0] = mmr[3] - mmr[2]; // far
	frustum[5][1] = mmr[7] - mmr[6];
	frustum[5][2] = mmr[11] - mmr[10];
	frustum[5][3] = mmr[15] - mmr[14];
	normalize_plane(frustum[5]);
}
