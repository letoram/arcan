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
	unsigned ny = ceil(delta.z / step.z);
	
	*nverts = nx * ny;
	*verts = (float*) malloc(sizeof(float) * (*nverts) * 3);
	*txcos = (float*) malloc(sizeof(float) * (*nverts) * 2);
	
	unsigned vofs = 0, tofs = 0;
	for (unsigned row = 0; row < ny; row++)
		for (unsigned col = 0; col < nx; col++){
			(*verts)[vofs++] = min.x + ((float)col * step.x);
			(*verts)[vofs++] = max.y;
			(*verts)[vofs++] = min.z + ((float)row * step.z);
			(*txcos)[tofs++] = (float)col / (float)nx;
			(*txcos)[tofs++] = (float)row / (float)ny;
		}

	vofs  = 0;
#define VERTOFS(ROW,COL) ((ROW * ny) + COL)
	
	*nindices = (nx-1) * (ny-1) * 6;
	*indices = (unsigned*) malloc(sizeof(unsigned) * (*nindices));
	for (unsigned row = 0; row < ny - 1; row++)
		for (unsigned col = 0; col < nx - 1; col++){
/* triangle 1 */
			(*indices)[vofs++] = VERTOFS(row, col);
			(*indices)[vofs++] = VERTOFS(row+1, col);
			(*indices)[vofs++] = VERTOFS(row+1, col+1);
/* triangle 2 */
			(*indices)[vofs++] = VERTOFS(row+1, col+1);
			(*indices)[vofs++] = VERTOFS(row, col+1);
			(*indices)[vofs++] = VERTOFS(row, col);
		}
#undef VERTOFS
}

