#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <ctype.h>
#include <assert.h>
#include <math.h>

#include "getopt.h"
#include "arcan_math.h"
#include <openctm.h>

/* msys workaround */
#ifndef S_IXGRP
#define S_IXGRP S_IXUSR
#endif

#ifndef S_IXOTH 
#define S_IXOTH S_IXUSR
#endif

#ifndef S_IROTH
#define S_IROTH S_IXUSR
#endif

/* need to store this for all contained meshes,
 * then split into a number of meshes, with the loading options
 * specified in the basename/basename.lua file. Since
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
    
    char* basename; /* desired basename to store with */
	char* filename; /* model output if we have no material set */
	char* material; /* if a material label is given, we use that +ctm as we need to split on material */
	bool split;
	bool debug;
} global = {.split = true};

struct {
	float opacity;
	float specfact;
	
	vector diffuse;
	vector ambient;
	vector specular;
	
	char* diffusemap;
	char* specularmap;
	char* ambientmap;
	char* bumpmap;
	char* groupname;
	
} globalmat = {
	.opacity = 1.0
};

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

static bool file_exists(const char* fn)
{
	struct stat buf;
	bool rv = false;

	if (fn == NULL) 
		return false;
		
	if (stat(fn, &buf) == 0) {
		rv = S_ISREG(buf.st_mode);
	}

	return rv;
}

/* since material split may result in several models
 * with the same filename, we need to have a way of adding a seqn.
 * thus we do a linear filesystem search (assumes there's enough space in dst) */
static char* addseqn(char* dst, char* base, char* ext){
	unsigned seqn = 1;
	
	sprintf(dst, "%s.%s", base, ext);
	if (!file_exists(dst))
		return dst;
	
	do{
		sprintf(dst, "%s_%i.%s", base, seqn++, ext);
	} while (file_exists(dst));

	return dst;
}

static int meshcount = 0;
static int write_rep(char* arg, FILE* luafile)
{
	/* nothing if were's no indices found */
    if (global.split && global.filename && global.ofs_vertindbuf > 0){
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

 /* either I've messed up or there's something with CTMFreeContext,
  * but in some border-conditions, it will double-free */
		char buf[68];
		addseqn(buf, chop(global.filename), "ctm");
		printf("yielded : %s\n", buf);
		CTMcontext context;
		context = ctmNewContext(CTM_EXPORT);
		ctmDefineMesh(context, vertbuf, vertbufofs / 3, indbuf, indbufofs / 3, normbufofs ? normbuf : NULL);
		if (textbufofs)
			ctmAddUVMap(context, textbuf, buf, NULL);
        
		ctmSave(context, buf);

		if (meshcount == 0)
			fprintf(luafile, "-- Build and link meshes into a model\n\n"
			"model.vid = load_3dmodel(\"models/%s/%s\");\n", global.basename, buf);
		else
			fprintf(luafile, "add_3dmesh(model.vid, \"models/%s/%s\");\n", global.basename, buf);

		fprintf(luafile, "model_material(\"%s\", %i);\n", chop(global.filename), meshcount);
		ctmFreeContext(context);
/* ctm takes care of the buffers we handed over */
		if (!normbufofs)
			free(normbuf);
        
		if (!textbufofs)
			free(textbuf);

/* need to keep all the other data since it may be referenced */
		global.ofs_vertindbuf = global.ofs_texindbuf = global.ofs_normindbuf = 0;
		meshcount++;
		/* read the rest of the line (should contain name of the group),
 * strip away any whitespace */
	}

	if (global.filename)
		free(global.filename);

	if (arg)
		global.filename = strdup(arg);

	return 0;
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
static void read_vertval(char* arg, char dstgrp)
{
	float v1, v2, v3, v4;
	unsigned* dstlim;
	unsigned* dstofs;
	CTMfloat* dstbuf;
	CTMfloat** dstbufp;
	
	if (sscanf(arg, " %f %f %f %f", &v1, &v2, &v3, &v4) < 3){
		fprintf(stderr, "Warning, vertex could not be read.\n");
		v1 = 0.0; v2 = 0.0; v3 = 0.0;
	}
    
	switch (dstgrp){
		case 0 :
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

void storemat(FILE* dst, char* groupname)
{
/* current API for material support is quite limited,
 * only one kind of map allowed,
 * no tinting, no illumination model,
 * only diffuse colour */
	if (globalmat.groupname != NULL){
		if (globalmat.diffusemap || globalmat.bumpmap ||
			globalmat.specularmap || globalmat.ambientmap){
			char* maptype = NULL;
			if (globalmat.diffusemap) maptype = globalmat.diffusemap;
			else if (globalmat.ambientmap) maptype = globalmat.ambientmap;
			else if (globalmat.specularmap) maptype = globalmat.specularmap;
			else if (globalmat.bumpmap) maptype = globalmat.bumpmap;

			fprintf(dst, "model.textures[\"%s\"] = load_image(\"models/%s/textures/%s\");\n", globalmat.groupname, global.basename, maptype);
		}
		else {
			fprintf(dst, "model.textures[\"%s\"] = fill_surface(8, 8, %d, %d, %d);\n", globalmat.groupname,
					(unsigned) (255 * globalmat.diffuse.x), (unsigned) (255 * globalmat.diffuse.y), (unsigned) (255 * globalmat.diffuse.z));
		}

		free(globalmat.ambientmap); free(globalmat.specularmap); free(globalmat.bumpmap); free(globalmat.diffusemap);
		globalmat.ambientmap = globalmat.specularmap = globalmat.bumpmap = globalmat.diffusemap = NULL;
		free(globalmat.groupname);
		globalmat.groupname = NULL;
			
		if (groupname)
			globalmat.groupname = strdup(groupname);
	}
	else
		globalmat.groupname = strdup(groupname);
}

static void read_faceval(char* arg)
{
    unsigned u1, u2, u3, u4, u5, u6, u7, u8, u9;
    char* line = chop(arg);
    
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
		return;
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
                if (strchr(lineofs, '/')[1] == '/')
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
}

/* will try to automatically map specified single- color / simple property materials,
 * texture loading and map to the mesh (framenumber) with the corresponding label */
void parse_mat(FILE* src, FILE* luafile, const char* basename)
{
	/* newmtl - set next group label */
	/* Ka f f f    ambient term
	 * Kd f f f    diffuse term
	 * Ks f f f    specular term
	 * d f         transparency
	 * Tr 0.9      transparency
	 * illum mode  (ignored)
	 * map_Ka      (ambient texture map)
	 * map_Kd      (diffuse texture map)
	 * map_Ks      (specular texture map)
	 * map_bump    (bump map)
	 * bump        (alternative bump map format) */

	char line[256];
	unsigned ofs = 0;
	vector nullv= {.x = 0.0, .y = 0.0, .z = 0.0};
	
	while (!feof(src)){
		fgets(line, sizeof(line), src);
		char* cmdl = chop(line);
		char ofs = 0;

		while (!isspace(cmdl[ofs]) && cmdl[ofs++]);
		if (ofs >= sizeof(line)){
			fprintf(stderr, "Unexpected input parsing material, giving up\n");
			return;
		}

		cmdl[ofs] = 0;
		char* arg = &cmdl[ofs+1];
		
		if (strcmp(cmdl, "Ka") == 0){
			if (3 != sscanf(arg, "%f %f %f", &globalmat.ambient.x, &globalmat.ambient.y, &globalmat.ambient.y))
				globalmat.ambient = nullv;
		}
		else if (strcmp(cmdl, "Kd") == 0){
			if (3 != sscanf(arg, "%f %f %f", &globalmat.diffuse.x, &globalmat.diffuse.y, &globalmat.diffuse.y))
				globalmat.diffuse = nullv;
		}
		else if (strcmp(cmdl, "Ks") == 0){
			if (3 != sscanf(arg, "%f %f %f", &globalmat.specular.x, &globalmat.specular.y, &globalmat.specular.z))
				globalmat.specular = nullv;
		}
		else if (strcmp(cmdl, "d") == 0 ||
			strcmp(cmdl, "Tr") == 0){
			if (1 != sscanf(arg, "%f", &globalmat.opacity))
				globalmat.opacity = 1.0;
		}
		else if (strcmp(cmdl, "Ns") == 0){
			if (1 != sscanf(arg, "%f", &globalmat.specfact))
				globalmat.specfact = 0.0;
		}
		else if (strcmp(cmdl, "illum") == 0);
		else if (strcmp(cmdl, "map_Ka") == 0)
			globalmat.ambientmap = strdup(arg);
		else if (strcmp(cmdl, "map_Kd") == 0)
			globalmat.diffusemap = strdup(arg);
		else if (strcmp(cmdl, "map_Ks") == 0)
			globalmat.specularmap = strdup(arg);
		else if (strcmp(cmdl, "map_bump") == 0 ||
			strcmp(cmdl, "bump") == 0)
			globalmat.bumpmap = strdup(arg);
		
		else if (strcmp(cmdl, "newmtl") == 0){
			storemat(luafile, arg);
		}
	}

	storemat(luafile, NULL);
}

/* quirks to note:
 * associated .MTL files ignored
 * 1-based indexing, with relative indexes possible */
void parse_obj(FILE* src, FILE* luafile, const char* basename)
{
 	char line[1024];
	unsigned ofs = 0;
	vector nullv= {.x = 0.0, .y = 0.0, .z = 0.0};
	
	while (!feof(src)){
		fgets(line, sizeof(line), src);
		char* cmdl = chop(line);
		char ofs = 0;

		while (!isspace(cmdl[ofs]) && cmdl[ofs++]);
		if (ofs >= sizeof(line)){
			fprintf(stderr, "Unexpected input parsing obj, giving up\n");
			return;
		}

		cmdl[ofs] = 0;
		char* arg = &cmdl[ofs+1];
	   unsigned linecount = 0;

		if (strcmp(cmdl, "#") == 0)
			continue;
		else if (strcmp(cmdl, "v") == 0 || strcmp(cmdl, "vt") == 0 ||
			strcmp(cmdl, "vn") == 0)
				read_vertval(arg, cmdl[1]);
		else if (strcmp(cmdl, "f") == 0)
			read_faceval(arg);
		else if (strcmp(cmdl, "s") == 0)
			continue; /* ignore smoothing groups */
		else if (strcmp(cmdl, "g") == 0 ||
			strcmp(cmdl, "usemtl") == 0)
			write_rep(arg, luafile);
	}
}

void print_usage()
{
	fprintf(stdout, "arcan_modelconv, usage: \n"
	"\t-i inputfile -- (req) specify input file to parse\n"
	"\t-b basename  -- (req) specify modelname\n"
	"\t-m mtlfile   -- (opt) specify material file to parse\n"
	"\t-s           -- (opt) disable splitting files on group\n"
	"\t-g           -- (opt) emit debugoutput in model code\n"
	"\t-o outputdir -- (opt) default: ./) specify where to store the resulting files\n");
}

/* Parse arguments,
 * Basic filesystem error checking
 * Make filestructure, setup points and call parsing routines */
int main(int argc, char** argv)
{
	char* matfile   = NULL;
	char* basename  = NULL;
	char* inputfile = NULL;
	char* outputdir = NULL;
	char ch;

	while ( (ch = getopt(argc, argv, "gsm:i:o:b:")) != -1){
		switch (ch) {
			case 'm' : matfile   = strdup(optarg); break;
			case 'i' : inputfile = strdup(optarg); break;
			case 'o' : outputdir = strdup(optarg); break;
			case 'b' : basename  = strdup(optarg); break;
			case 'g' : global.debug = true; break;
			case 's' : global.split = false; break;
			default:
				fprintf(stderr, "Warning, unknown option (%c), ignored.\n", ch);  
		}
	}

	if (!outputdir)
		outputdir = "./";
	
	if (!inputfile || !basename){
		print_usage();
		return 0;
	}
	
    
	FILE* fpek = fopen(inputfile, "r");
	FILE* matfpek = NULL;
	
	if (matfile){
		matfpek = fopen(matfile, "r");
		if (!matfpek)
			fprintf(stderr, "Warning, couldn't open material file (%s), ignoring.\n", matfile);
	}
	
	if (!fpek){
		fprintf(stderr, "Couldn't open input (%s)\n", inputfile); 
		return 1;
	}

#ifdef __MINGW_H
	if (mkdir(outputdir) == -1 &&
		errno != EEXIST){
        fprintf(stderr, "Couldn't create directory (%s)\n", outputdir);
        return 1;
	}
#else
	if (mkdir(outputdir, S_IRWXU | S_IXGRP | S_IXOTH | S_IROTH) == -1 &&
		errno != EEXIST){
        fprintf(stderr, "Couldn't create directory (%s)\n", outputdir);
        return 1;
	}
#endif

	chdir(outputdir);
    
	char* luafname = (char*) malloc( (strlen(basename + 5)) * sizeof(char) );
	sprintf(luafname, "%s.lua", basename);
	FILE* luadst = fopen(luafname, "w");
	free(luafname);
    
	if (!luadst){
		fprintf(stderr, "Couldn't open output (%s) for writing.\n", argv[2]);
		return 1;
	}
    
    global.basename = basename;
    global.cap_normalbuf  = global.cap_texbuf     = global.cap_vertbuf   = 640 * 1024;
    global.cap_normindbuf = global.cap_vertindbuf = global.cap_texindbuf = 640 * 1024;
    
    global.vertbuf    = (CTMfloat*) malloc(global.cap_vertbuf    * sizeof(CTMfloat));
    global.texbuf     = (CTMfloat*) malloc(global.cap_texbuf     * sizeof(CTMfloat)); 
    global.normalbuf  = (CTMfloat*) malloc(global.cap_normalbuf  * sizeof(CTMfloat));
    global.vertindbuf = (CTMuint*)  malloc(global.cap_vertindbuf * sizeof(CTMuint));
    global.texindbuf  = (CTMuint*)  malloc(global.cap_texindbuf  * sizeof(CTMuint));
    global.normindbuf = (CTMuint*)  malloc(global.cap_normindbuf * sizeof(CTMuint));

/* add a wrapper function to make things slightly more cleaner */
	fprintf(luadst, "local model = {vid = ARCAN_EID, labels = {}, textures = {}};\n");
	fprintf(luadst, "local function model_material(label, slot)\n\t"
	"if (model.labels[label] == nil) then model.labels[label] = {}; end\n\t"
	"table.insert(model.labels[label], slot);\nend\n");
	
    parse_obj(fpek, luadst, basename);
	global.split = true;
	
	if (global.ofs_vertindbuf > 0)
        write_rep(NULL, luadst);

	if (meshcount > 0)
		fprintf(luadst, "image_framesetsize(model.vid, %i);\n", meshcount);

	if (matfpek){
		parse_mat(matfpek, luadst, basename);
		fclose(matfpek);
	}

	if (global.debug){
		fprintf(luadst, "\nfor label, vid in pairs(model.textures) do\n"
		"\tif (vid == ARCAN_EID) then\n"
		"\t\tmodel.textures[label] = fill_surface(8, 8, 255,255,0);\n"
		"\tend");
	}

	/*  this little loop scans through the loaded models, and tries to find corresponding textures */
	fprintf(luadst, "\nfor label,vids in pairs(model.labels) do\n"
		"\tif (model.textures[label]) then\n"
		"\t\tfor ind, slot in ipairs(vids) do\n"
		"\t\t\tset_image_as_frame(model.vid, model.textures[label], slot, 1);\n"
		"\t\t end\n"
		"\tend\n"
	"end\n");

    fprintf(luadst, "return model;\n");
    fclose(fpek);
	fclose(luadst);
	
	return 0;
}
