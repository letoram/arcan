/* Included by arcan_3dbase.h to move the lengthier
 * "geometry generation" routines */

static inline void wireframe_box(float minx, float miny, float minz, float maxx, float maxy, float maxz)
{
	glColor3f(0.2, 1.0, 0.2);
	glBegin(GL_LINES);
	glVertex3f(minx, miny, minz); // back
	glVertex3f(minx, maxy, minz);
	glVertex3f(minx, miny, maxz);
	glVertex3f(minx, maxy, maxz);
	glVertex3f(minx, miny, minz);
	glVertex3f(maxx, miny, minz);
	glVertex3f(maxx, miny, minz);
	glVertex3f(maxx, maxy, minz);
	glVertex3f(maxx, maxy, minz);
	glVertex3f(minx, maxy, minz);
	glVertex3f(minx, miny, maxz); // front
	glVertex3f(maxx, miny, maxz);
	glVertex3f(maxx, miny, maxz);
	glVertex3f(maxx, maxy, maxz);
	glVertex3f(maxx, maxy, maxz);
	glVertex3f(minx, maxy, maxz);
	glVertex3f(minx, miny, minz); // left
	glVertex3f(minx, miny, maxz);
	glVertex3f(minx, maxy, minz);
	glVertex3f(minx, maxy, maxz);
	glVertex3f(maxx, miny, minz); // right
	glVertex3f(maxx, miny, maxz);
	glVertex3f(maxx, maxy, minz);
	glVertex3f(maxx, maxy, maxz);
	glEnd();
	glColor3f(1.0, 1.0, 1.0);
}

static void build_quadbox(float n, float p, float** verts, float** txcos, unsigned* nverts)
{
	float lut[6][12] = {
		{n,p,p,   n,p,n,   p,p,n,   p,p,p}, /* up */
		{n,n,n,   n,n,p,   p,n,p,   p,n,n}, /* dn */
		{n,p,p,   n,n,p,   n,n,n,   n,p,n}, /* lf */
		{p,p,n,   p,n,n,   p,n,p,   p,p,p}, /* rg */
		{n,p,n,   n,n,n,   p,n,n,   p,p,n}, /* fw */
		{p,p,p,   p,n,p,   n,n,p,   n,p,p}  /* bk */
	};

	*nverts = 24;
	*verts = malloc(sizeof(float) * (*nverts * 3));
	*txcos = malloc(sizeof(float) * (*nverts * 2));

	unsigned ofs = 0;
	for (unsigned i = 0; i < 6; i++){
		*txcos[ofs] = 1.0f; *txcos[ofs+1] = 0.0; *verts[ofs] = lut[i][0]; *verts[ofs+1] = lut[i][1]; *verts[ofs+2] = lut[i][2]; ofs += 3;
		*txcos[ofs] = 1.0f; *txcos[ofs+1] = 1.0; *verts[ofs] = lut[i][3]; *verts[ofs+1] = lut[i][4]; *verts[ofs+2] = lut[i][5]; ofs += 3;
		*txcos[ofs] = 0.0f; *txcos[ofs+1] = 1.0; *verts[ofs] = lut[i][6]; *verts[ofs+1] = lut[i][7]; *verts[ofs+2] = lut[i][8]; ofs += 3;
		*txcos[ofs] = 0.0f; *txcos[ofs+1] = 0.0; *verts[ofs] = lut[i][9]; *verts[ofs+1] = lut[i][10]; *verts[ofs+2] = lut[i][11]; ofs += 3;
	}	
}

/* this should really just be a fallback from geometry shaders now,
 * alas, long live old video cards */
static void build_hplane(point min, point max, point step,
						 float** verts, unsigned** indices, float** txcos,
						 unsigned* nverts, unsigned* nindices)
{
	point delta = {
		.x = max.x - min.x,
		.y = max.y,
		.z = max.z - min.z
	};

	unsigned nx = ceil(delta.x / step.x);
	unsigned nz = ceil(delta.z / step.z);
	
	*nverts = nx * nz;
	*verts = (float*) malloc(sizeof(float) * (*nverts) * 3);
	*txcos = (float*) malloc(sizeof(float) * (*nverts) * 2);
	
	unsigned vofs = 0, tofs = 0;
	for (unsigned x = 0; x < nx; x++)
		for (unsigned z = 0; z < nz; z++){
			(*verts)[vofs++] = min.x + (float)x*step.x;
			(*verts)[vofs++] = min.y;
			(*verts)[vofs++] = min.z + (float)z*step.z;
			(*txcos)[tofs++] = (float)x / (float)nx;
			(*txcos)[tofs++] = (float)z / (float)nz;
		}

	vofs = 0; tofs = 0;
#define GETVERT(X,Z)( ( (X) * nz) + Z)
	*indices = (unsigned*) malloc(sizeof(unsigned) * (*nverts) * 3 * 2);
		for (unsigned x = 0; x < nx-1; x++)
			for (unsigned z = 0; z < nz-1; z++){
				(*indices)[vofs++] = GETVERT(x, z);
				(*indices)[vofs++] = GETVERT(x, z+1);
				(*indices)[vofs++] = GETVERT(x+1, z+1);
				tofs++;
				
				(*indices)[vofs++] = GETVERT(x, z);
				(*indices)[vofs++] = GETVERT(x+1, z+1);
				(*indices)[vofs++] = GETVERT(x+1, z);
				tofs++;
			}
			
	*nindices = vofs;
}

