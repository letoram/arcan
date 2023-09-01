/*
 * No copyright claimed, Public Domain
 */

#ifndef HAVE_ARCAN_MATH
#define HAVE_ARCAN_MATH

#define EPSILON 0.000001f
#define DEG2RAD(X) (X * M_PI / 180)

#ifndef MIN
#define MIN(x,y) (((x)<(y))?(x):(y))
#endif
#ifndef MAX
#define MAX(x,y) (((x)>(y))?(x):(y))
#endif

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

/* generate lookup-tables */
void arcan_math_init();

/* all assume column- major order, 4x4 */
void scale_matrix(float*, float, float, float);
void translate_matrix(float*, float, float, float);
void identity_matrix(float*);
void multiply_matrix(float* restrict dst,
	const float* restrict a, const float* restrict b);
quat quat_matrix(float* src);
void matr_lookat(float* m, vector position, vector dstpos, vector up);
void mult_matrix_vecf(const float* restrict inmatr,
	const float* restrict, float* restrict outv);
bool matr_invf(const float* restrict m, float* restrict out);
int project_matrix(float objx, float objy, float objz, const float model[16],
	const float projection[16], const int viewport[4], float*, float*, float*);
vector unproject_matrix(float dev_x, float dev_y, float dev_z,
		const float* restrict view, const float* restrict proj);
float* matr_rotatef(float ang, float* dst);

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
vector taitbryan_forwardv(float roll, float pitch, float yaw);

quat inv_quat(quat src);
float len_quat(quat src);
quat norm_quat(quat src);
quat mul_quat(quat a, quat b);
quat mul_quatf(quat a, float b);
quat div_quatf(quat a, float b);
float* matr_quatf(quat a, float* dmatr);
double* matr_quat(quat a, double* dmatr);
vector angle_quat(quat a);
quat add_quat(quat a, quat b);
quat build_quat_taitbryan(float roll, float pitch, float yaw);
quat quat_lookat(vector viewpos, vector dstpos);

/* spherical interpolation between quaternions a and b with the weight of f.
 * 180/360 separation implies different interpolation paths */
quat slerp_quat180(quat a, quat b, float f);
quat slerp_quat360(quat a, quat b, float f);

/* normalized linear interpolation, non-uniform speed. */
quat nlerp_quat180(quat a, quat b, float f);
quat nlerp_quat360(quat a, quat b, float f);

/* some of the more common interpolators (1D, 3D) */
float interp_1d_linear(float startv, float stopv, float fract);
float interp_1d_sine(float startv, float endv, float fract);
float interp_1d_expout(float startv, float endv, float fract);
float interp_1d_expin(float startv, float endv, float fract);
float interp_1d_expinout(float startv, float endv, float fract);
float interp_1d_smoothstep(float startv, float endv, float fract);

vector interp_3d_linear(vector startv, vector stopv, float fract);
vector interp_3d_sine(vector startv, vector endv, float fract);
vector interp_3d_expout(vector startv, vector endv, float fract);
vector interp_3d_expin(vector startv, vector endv, float fract);
vector interp_3d_expinout(vector startv, vector endv, float fract);
vector interp_3d_smoothstep(vector startv, vector endv, float fract);

void update_view(orientation* dst, float roll, float pitch, float yaw);

/* camera / view functions */
void build_projection_matrix(float* m, float near, float far,
	float aspect, float fov);
void build_orthographic_matrix(float* m, const float left, const float right,
	const float bottom, const float top, const float near, const float far);

bool ray_plane(vector* pos, vector* dir,
	vector* plane_pos, vector* plane_normal, vector* intersect);
bool ray_sphere(const vector* ray_pos, const vector* ray_dir,
	const vector* sphere_pos, float sphere_rad, float* d1, float *d2);

/* basic intersections */
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

/* misc. utility */
void dev_coord(float* out_x, float* out_y, float* out_z,
	int x, int y, int w, int h, float near, float far);
#endif
