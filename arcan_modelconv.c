#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <sys/stat.h>
#include <errno.h>
#include <ctype.h>
#include <assert.h>
#include <math.h>

#include "arcan_math.h"
#include <openctm.h>

/* need to store this for all contained meshes,
 * then split into a number of meshes, with the loading options
 * specified in the basename/basename.lua file. Since
 * .objs indices are relative to an absolute vertex cloud, 
 * we have to reindex. */
struct {
    CTMfloat* vertbuf;
    unsigned cap_vertbuf, ofs_vertbuf;
    
    CTMfloat* texbuf;
    unsigned cap_texbuf, ofs_texbuf;
    
    CTMfloat* normalbuf;
    unsigned cap_normalbuf, ofs_normalbuf;
    
    CTMuint* vertindbuf;
    unsigned cap_vertindbuf, ofs_vertindbuf;
    
    CTMuint* normindbuf;
    unsigned cap_normindbuf, ofs_normindbuf;
    
    CTMuint* texindbuf;
    unsigned cap_texindbuf, ofs_texindbuf;
    
    char* basename;
    bool split;
} global = {0};

char* chop(char* str)
{
    char* endptr = str + strlen(str) - 1;
    while(isspace(*str)) str++;
    
    if(!*str) return str;
    while(endptr > str && isspace(*endptr)) 
        endptr--;
    
    *(endptr+1) = 0;
    
    return str;
}

/* find v1/v2/(nv==3, v3) in sbuf (0 > sbuf < lim), 
 * if no math, add.
 * return index
 * assumes n(sbuf) has more space than lim */

static int checkc = 0;
static int missc  = 0;

unsigned resolve(CTMfloat* sbuf, unsigned* lim, float v1, float v2, float v3){
    /* check if it already exists */
    unsigned i;
    checkc++;
    
    for (i = 0; i < (*lim); i += 3){
        if (
            (fabs(sbuf[i+0] - v1) < EPSILON) && 
            (fabs(sbuf[i+1] - v2) < EPSILON) && 
            (fabs(sbuf[i+2] - v3) < EPSILON)
            ){        
            return i / 3;
        }
    }
    
    missc++;
    sbuf[i+0] = v1;
    sbuf[i+1] = v2;
    sbuf[i+2] = v3;
    
    *lim += 3;
    return i / 3;
}

static bool meshcount = 0;
static int write_rep(FILE* src, FILE* luafile, bool flush)
{    
    static char fname[64] = "";
    char* dstfile = fname;
    
    if (flush && strlen(fname) == 0)
        dstfile = global.basename;
    
    /* nothing if were's no indices found */
    if (global.ofs_vertindbuf > 0){
        CTMfloat (* vertbuf), (* normbuf), (* textbuf);
        CTMuint* indbuf;
        unsigned vertbufofs = 0, indbufofs = 0, vertbufind = 0, normbufofs = 0, textbufofs = 0;
        
        /* reindex, rebuffer */
        vertbuf = (CTMfloat*) malloc(global.ofs_vertindbuf * sizeof(float) * 3);
        normbuf = (CTMfloat*) malloc(global.ofs_vertindbuf * sizeof(float) * 3);
        textbuf = (CTMfloat*) malloc(global.ofs_vertindbuf * sizeof(float) * 2);
        indbuf  = (CTMuint*)  malloc(global.ofs_vertindbuf * sizeof(CTMuint));
        
        for (unsigned i = 0; i < global.ofs_vertindbuf; i++){
            unsigned ind = global.vertindbuf[ i ] * 3;
            
            indbuf[indbufofs++] = resolve(vertbuf, &vertbufofs,
                                          global.vertbuf[ ind   ],
                                          global.vertbuf[ ind+1 ],
                                          global.vertbuf[ ind+2 ]);
            
            if (global.ofs_normindbuf && global.ofs_normindbuf == global.ofs_vertindbuf){
                ind = global.normindbuf[i]*3; /* per vertex normal */
                
                normbuf[ normbufofs++ ] = global.normalbuf[ind];
                normbuf[ normbufofs++ ] = global.normalbuf[ind+1];
                normbuf[ normbufofs++ ] = global.normindbuf[ind+1];
            }
            
            if (global.ofs_texindbuf){
                ind = global.texindbuf[i]*2;
                textbuf[ textbufofs++ ] = global.texbuf[ind];
                textbuf[ textbufofs++ ] = global.texbuf[ind+1];
            }
        }
        
        char buf[68];
        snprintf(buf, 68, "%s.ctm", chop(dstfile));
        CTMcontext context;
        context = ctmNewContext(CTM_EXPORT);
        ctmDefineMesh(context, vertbuf, vertbufofs / 3, indbuf, indbufofs / 3, normbufofs ? normbuf : NULL);
        if (textbufofs)
            ctmAddUVMap(context, textbuf, buf, NULL);
        
        ctmSave(context, buf);

		if (meshcount == 0)
			fprintf(luafile, "local model = load_3dmodel(\"%s\");\n", buf);
		else
			fprintf(luafile, "add_3dmesh(model, \"%s\");\n", buf);

		meshcount++;
        ctmFreeContext(context);
/* ctm takes care of the buffers we handed over */
        if (!normbufofs)
            free(normbuf);
        
        if (!textbufofs)
            free(textbuf);
     
/* need to keep all the other data since it may be referenced */
        global.ofs_vertindbuf = global.ofs_texindbuf = global.ofs_normindbuf = 0;
    }
    
    /* read the rest of the line (should contain name of the group),
     * strip away any whitespace */
    fgets(fname, 64, src);
    return 0;
}


static void print_usage()
{
	fprintf(stdout, "usage: arcan_modelconv infile basename outdir\n");
}

static void resizebuf(void** dbuf, unsigned* cap, unsigned ofs, unsigned step, unsigned size, const char* kind){
	if (ofs + step >= *cap){
		*cap = *cap * 2;
		*dbuf = realloc(*dbuf, (*cap) * size);
		if (!(*dbuf)){
			fprintf(stderr, "Fatal, couldn't resize %s to %i.\n", kind, *cap);
		}
	}
}

/* ' ' separated groups of floats (discard initial)
 * allowed num, . and neg. 
 * initial character (empty, n or t sets destination group, but all are floats) */
static void read_vertval(FILE* src)
{
	float v1, v2, v3, v4;
	unsigned* dstlim;
	unsigned* dstofs;
	CTMfloat* dstbuf;
	CTMfloat** dstbufp;
    long fpos = ftell(src);
	char dstgrp;
	dstgrp = fgetc(src);
	
	if (fscanf(src, " %f %f %f %f", &v1, &v2, &v3, &v4) < 3){
		fprintf(stderr, "Warning, vertex could not be read.\n");
		v1 = 0.0; v2 = 0.0; v3 = 0.0;
	}
    
	switch (dstgrp){
		case ' ' :
			resizebuf((void**)&global.vertbuf, &global.cap_vertbuf, global.ofs_vertbuf, 3, sizeof(float), "vertbuf");
			global.vertbuf[global.ofs_vertbuf++] = v1;
			global.vertbuf[global.ofs_vertbuf++] = v2;
			global.vertbuf[global.ofs_vertbuf++] = v3;
            break;
            
		case 'n' :
			resizebuf((void**)&global.normalbuf, &global.cap_normalbuf, global.ofs_normalbuf, 3, sizeof(float), "normbuf");
			global.normalbuf[global.ofs_normalbuf++] = v1;
			global.normalbuf[global.ofs_normalbuf++] = v2;
			global.normalbuf[global.ofs_normalbuf++] = v3;
            break;
            
		case 't' :
			resizebuf((void**)&global.texbuf, &global.cap_texbuf, global.ofs_texbuf, 2, sizeof(float), "texindbuf");
			global.texbuf[global.ofs_texbuf++] = v1;
			global.texbuf[global.ofs_texbuf++] = v2;
			/* note, 3 texcoords in some obj files?! */
            break;
        default:
            fprintf(stderr, "Warning, unknown vertex subtype (%c)\n", dstgrp);
	}
    
    fseek(src, fpos, SEEK_SET);
}

static void storeind(signed vert, signed texco, signed norm)
{
    if (vert){
        if (vert < 1) vert += global.ofs_vertbuf;
        else vert--;
        resizebuf((void**)&global.vertindbuf, &global.cap_vertindbuf, global.ofs_vertindbuf, 3, sizeof(CTMuint), "vertindbuf");
        global.vertindbuf[global.ofs_vertindbuf++] = vert;
    }
    
    if (texco){
        if (texco < 1) texco += global.ofs_vertbuf;
        else texco--;
        resizebuf((void**)&global.texindbuf, &global.cap_texindbuf, global.ofs_texindbuf, 2, sizeof(CTMuint), "textindbuf");
        global.texindbuf[global.ofs_texindbuf++] = texco;
    }
    
    if (norm){
        if (norm < 1) norm += global.ofs_normalbuf;
        else norm--;
        resizebuf((void**)&global.normindbuf, &global.cap_normindbuf, global.ofs_normindbuf, 3, sizeof(CTMuint), "normindbuf");    
        global.normindbuf[global.ofs_normindbuf++] = norm;
    }
}

static void read_face(FILE* src)
{
    unsigned u1, u2, u3, u4, u5, u6, u7, u8, u9;
    long fpos = ftell(src);
    long feol = fpos;
    
    /* buffer the whole line */
    while (fgetc(src) != '\n' && !feof(src));
    feol = ftell(src);
    char* linebuf = (char*) malloc(sizeof(char*) * (feol - fpos + 1));
    if (!linebuf) return;
    
    fseek(src, fpos, SEEK_SET);
    fgets(linebuf, (feol - fpos + 1), src);
    
    char* line = chop(linebuf);
    
    /* need to know if we should tesselate into tris and how many attributes we have */
    unsigned ngroups = 0, ofs = 0, nelem = 0;
    bool reset = true;
    while (line[ofs]){
        if (line[ofs] == '/' && reset){
            nelem++;
            reset = false;
        }
        else if ( isspace(line[ofs]) ){
            ngroups++;
            while (line[ofs] && isspace(line[ofs++]));
            continue;
        }
        else
            reset = true;
        
        ofs++;
    }
    if (++ngroups != 3 && ngroups != 4){
        fprintf(stderr, "Warning, couldn't read face from line: (%s)-- unknown size (%i) groups found.\n", line, ngroups);
        goto error;
    }
    
    /* fill buf */
    struct {
        signed vrti, txci, normi;
    } buf[4] = {0};
    
    char* lineofs = line;
    
    if (nelem > 0)
        nelem /= ngroups;
    
    for (unsigned i = 0; i < ngroups; i++){
        while(*lineofs && isspace(*lineofs)) lineofs++;
        
        switch (nelem){
            case 0: sscanf(lineofs, "%d", &buf[i].vrti); /* just vertex indices */
                break;
                
            case 1: 
                if (index(lineofs, '/')[1] == '/')
                    sscanf(lineofs, "%d//%d", &buf[i].vrti, &buf[i].normi);
                else
                    sscanf(lineofs, "%d/%d", &buf[i].vrti, &buf[i].txci);
                break;
                
            case 2: sscanf(lineofs, "%d/%d/%d", &buf[i].vrti, &buf[i].txci, &buf[i].normi);
                break;
        }
        
        while (*lineofs && !isspace(*lineofs))
            lineofs++;
    }
    
    /* store in global */
    storeind( buf[0].vrti, buf[0].txci, buf[0].normi );
    storeind( buf[1].vrti, buf[1].txci, buf[1].normi );
    storeind( buf[2].vrti, buf[2].txci, buf[2].normi );
    
    /*    printf("f %d//%d %d//%d %d//%d\n", buf[0].vrti, buf[0].normi, buf[1].vrti, buf[1].normi, buf[2].vrti, buf[2].normi); */
    if (ngroups == 4){   
        storeind( buf[0].vrti, buf[0].txci, buf[0].normi );
        storeind( buf[2].vrti, buf[2].txci, buf[2].normi );
        storeind( buf[3].vrti, buf[3].txci, buf[3].normi );
    }
    
error:
    free(linebuf);
    fseek(src, fpos, SEEK_SET);
}

/* quirks to note:
 * associated .MTL files ignored
 * 1-based indexing, with relative indexes possible */
void parse_obj(FILE* src, FILE* luafile, const char* basename)
{
    unsigned linecount = 0;
	/* skip all whitespace and lines beginning with # */
	while(!feof(src)){
		char ch;
		bool skipline = false;
        linecount++;
        
		while ( !feof(src) && (ch = fgetc(src)) != '\n' ){
			if (skipline)
				continue;
            
            if (isspace(ch))
                continue;
            
			switch (ch){
                    /* comment  */	case '#' : skipline = true; break;
                    /* vertice  */ 	case 'v' : read_vertval(src); skipline = true; break; 
                    /* faces    */  case 'f' : read_face(src); skipline = true; break; 
                    /* grouping */  case 'g' : skipline = true; 
                    if (global.split)
                        write_rep(src, luafile, false); 
                    break;
                    
                    /* smoothing*/  case 's' : skipline = true; break;
                    /* usemat   */  case 'u' : skipline = true; break;
                    /* mtllib   */  case 'm' : skipline = true; break;
				default:
					fprintf(stderr, "Warning, unknown control character: %c on line %i\n", ch, linecount);
			}
		}
	}
}

/* Parse arguments,
 * Basic filesystem error checking
 * Make filestructure, setup points and call parsing routines */
int main(int argc, char** argv)
{
	if (argc != 4){
		print_usage();
		return 1;
	}
    
	FILE* fpek = fopen(argv[1], "r");
	if (!fpek){
		fprintf(stderr, "Couldn't open input (%s)\n", argv[1]);
		return 1;
	}
    
	if (mkdir(argv[3], S_IRWXU | S_IXGRP | S_IXOTH | S_IROTH) == -1 &&
		errno != EEXIST){
        fprintf(stderr, "Couldn't create directory (%s)\n", argv[3]);
        return 1;
	}
	
	chdir(argv[3]);
    
	char* luafname = (char*) malloc( (strlen(argv[2] + 5)) * sizeof(char) );
	sprintf(luafname, "%s.lua", argv[2]);
	FILE* luadst = fopen(luafname, "w");
	free(luafname);
    
	if (!luadst){
		fprintf(stderr, "Couldn't open output (%s) for writing.\n", argv[2]);
		return 1;
	}
    
    global.split = true;
    global.basename = argv[2];
    global.cap_normalbuf  = global.cap_texbuf     = global.cap_vertbuf   = 640 * 1024;
    global.cap_normindbuf = global.cap_vertindbuf = global.cap_texindbuf = 640 * 1024;
    
    global.vertbuf    = (CTMfloat*) malloc(global.cap_vertbuf    * sizeof(CTMfloat));
    global.texbuf     = (CTMfloat*) malloc(global.cap_texbuf     * sizeof(CTMfloat)); 
    global.normalbuf  = (CTMfloat*) malloc(global.cap_normalbuf  * sizeof(CTMfloat));
    global.vertindbuf = (CTMuint*)  malloc(global.cap_vertindbuf * sizeof(CTMuint));
    global.texindbuf  = (CTMuint*)  malloc(global.cap_texindbuf  * sizeof(CTMuint));
    global.normindbuf = (CTMuint*)  malloc(global.cap_normindbuf * sizeof(CTMuint));
    
    parse_obj(fpek, luadst, argv[2]);
    
    if (global.ofs_vertindbuf > 0)
        write_rep(fpek, luadst, true);

	if (meshcount > 0){
		fprintf(luadst, "image_framesetsize(model, %i);\n", meshcount);
		fprintf(luadst, "return model;\n");
	}
	
	fclose(fpek);
	fclose(luadst);
    
	return 0;
}
