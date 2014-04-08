/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 3
 * of the License, or (at your option) any later version.
 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301,USA.
 *
 */

#ifndef _HAVE_ARCAN_MATH
#define _HAVE_ARCAN_MATH

/*
 * I know it's dumb to roll your own mathlib by now,
 * replace with something quick at your own leisure -- 
 * I use this as a refresher-course ;-) 
 */

#define EPSILON 0.000001f
#define DEG2RAD(X) (X * M_PI / 180)

typedef struct {
	union {
		struct {
			float x, y, z, w;
		};
		float xyzw[4];
	};
} quat;

extern quat default_quat;

typedef struct {
	union {
		struct {
			float x, y, z;
		};
		float xyz[3]; 
	};
} vector;

typedef vector point;
typedef vector scalefactor;

/* actually store all three forms as the conversion
 * is costly */
typedef struct orientation {
	float rollf, pitchf, yawf;
	float matr[16];
} orientation;

enum cstate {
	inside    = 0,
	intersect = 1,
	outside   = 2
};

void arcan_math_init();

/* Matrices
 * All assume column major organization */
void scale_matrix(float*, float, float, float);
void translate_matrix(float*, float, float, float);
void identity_matrix(float*);
void multiply_matrix(float* restrict dst, float* restrict a, float* restrict b);
quat quat_matrix(float* src); 
void matr_lookat(float* m, vector position, vector dstpos, vector up);
void mult_matrix_vecf(const float* restrict inmatr, 
	const float* restrict, float* restrict outv);

/* Vectors */
vector build_vect_polar(const float phi, const float theta);
vector build_vect(const float x, const float y, const float z);
float len_vector(vector invect);
vector crossp_vector(vector a, vector b);
float dotp_vector(vector a, vector b);
vector norm_vector(vector invect);
vector mul_vector(vector a, vector b);
vector add_vector(vector a, vector b);
vector sub_vector(vector a, vector b);
vector mul_vectorf(vector a, float f);

/* Quaternions */
quat inv_quat(quat src);
float len_quat(quat src);
quat norm_quat(quat src);
quat mul_quat(quat a, quat b);
quat mul_quatf(quat a, float b);
quat div_quatf(quat a, float b);
float* matr_quatf(quat a, float* dmatr);
double* matr_quat(quat a, double* dmatr);
vector angle_quat(quat a);

/* spherical interpolation between quaternions a and b with the weight of f.
 * 180/360 separation implies different interpolation paths */
quat slerp_quat180(quat a, quat b, float f);
quat slerp_quat360(quat a, quat b, float f);

/* normalized linear interpolation, non-uniform speed. */
quat nlerp_quat180(quat a, quat b, float f);
quat nlerp_quat360(quat a, quat b, float f);

/* regular, 1d and 3d interpolators */
float interp_1d_linear(float startv, float stopv, float fract);
vector interp_3d_linear(vector startv, vector stopv, float fract);
vector interp_3d_sine(vector startv, vector endv, float fract);

quat add_quat(quat a, quat b);
quat build_quat_taitbryan(float roll, float pitch, float yaw);
quat quat_lookat(vector viewpos, vector dstpos);

vector taitbryan_forwardv(float roll, float pitch, float yaw);

void update_view(orientation* dst, float roll, float pitch, float yaw);

void build_projection_matrix(float* m, float near, float far, 
	float aspect, float fov);
void build_orthographic_matrix(float* m, const float left, const float right,
	const float bottom, const float top, const float near, const float far);

int project_matrix(float objx, float objy, float objz, const float model[16],
	const float projection[16], const int viewport[4], float*, float*, float*);

void update_frustum(float* projection, 
	float* modelview, float dstfrustum[6][4]);

enum cstate frustum_sphere(const float frustum[6][4],
	const float x, const float y, const float z, const float radius);

bool frustum_point(const float frustum[6][4], 
	const float x, const float y, const float z);

enum cstate frustum_aabb(const float frustum[6][4],
	const float x1, const float y1, const float z1,
	const float x2, const float y2, const float z2);

/* comp.graphics.algorithms DAQ, Randolph Franklin */
int pinpoly(int, float*, float*, float, float);
#endif
