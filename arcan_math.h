/* Arcan-fe, scriptable front-end engine
 *
 * Arcan-fe is the legal property of its developers, please refer
 * to the COPYRIGHT file distributed with this source distribution.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 */

#ifndef _HAVE_ARCAN_MATH
#define _HAVE_ARCAN_MATH

typedef struct {
	union{
		struct {
			float x, y, z, w;
		};
		float xyzw[4];
	};
} quat;

typedef struct {
	union{
		struct {
			float x, y, z;
		};
		float xyz[3];
	};
} vector;

typedef vector scalefactor;
typedef vector point;

typedef struct orientation {
	quat roll, pitch, yaw;
	float rollf, pitchf, yawf;
	vector view;
	float matr[16];
} orientation;

vector build_vect_polar(const float phi, const float theta);
vector build_vect(const float x, const float y, const float z);
quat build_quat(float angdeg, float vx, float vy, float vz);
float len_vector(vector invect);
vector crossp_vector(vector a, vector b);
float dotp_vector(vector a, vector b);
vector norm_vector(vector invect);
quat inv_quat(quat src);
float len_quat(quat src);
quat norm_quat(quat src);
quat mul_quat(quat a, quat b);
float* matr_quat(quat a, float* dmatr);
static void push_orient_matr(float x, float y, float z, float roll, float pitch, float yaw);
static void update_view(orientation* dst, float roll, float pitch, float yaw);


#endif
