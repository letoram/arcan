#include <arcan_shmif.h>

#ifdef __OpenBSD__
void arcan_shmif_privsep(struct arcan_shmif_cont* C,
	const char* pledge_str, struct shmif_privsep_node** nodes, int opts)
{
	size_t i = 0;
	while (nodes[i]){
		unveil(nodes[i]->path, nodes[i]->perm);
		i++;
	}

	unveil(NULL, NULL);

	if (pledge_str){
		if (
			strcmp(pledge_str, "shmif")  == 0 ||
			strcmp(pledge_str, "decode") == 0 ||
			strcmp(pledge_str, "encode") == 0 ||
			strcmp(pledge_str, "a12-srv") == 0 ||
			strcmp(pledge_str, "a12-cl") == 0
		){
			pledge_str = SHMIF_PLEDGE_PREFIX;
		}
		else if (strcmp(pledge_str, "minimal") == 0){
			pledge_str = "stdio";
		}
		else if (strcmp(pledge_str, "minimalfd") == 0){
			pledge_str = "stdio sendfd recvfd";
		}

		pledge(pledge_str, NULL);
	}
}

#else
void arcan_shmif_privsep(struct arcan_shmif_cont* C,
	const char* pledge, struct shmif_privsep_node** nodes, int opts)
{
/* oh linux, why art thou.. */
}
#endif
