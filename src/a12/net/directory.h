#ifndef HAVE_DIRECTORY
#define HAVE_DIRECTORY

struct anet_dirsrv_opts {
	int basedir;
};

struct anet_dircl_opts {
	int basedir;
	const char* applname;
	bool die_on_list;
};

void anet_directory_srv(
	struct a12_state* S, struct anet_dirsrv_opts opts, int fdin, int fdout);

void anet_directory_cl(
	struct a12_state* S, struct anet_dircl_opts opts, int fdin, int fdout);

#endif
