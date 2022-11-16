/*
 * Copy me if you can.
 * by 20h
 */

#ifndef ARG_H__
#define ARG_H__

extern char *argv0;

/* use main(int argc, char *argv[]) */
#define ARGBEGIN	for (argv0 = *argv, argv++, argc--;\
					argv[0] && argv[0][0] == '-'\
					&& argv[0][1];\
					argc--, argv++) {\
				char argc_;\
				char **argv_;\
				int brk_;\
				if (argv[0][1] == '-' && argv[0][2] == '\0') {\
					argv++;\
					argc--;\
					break;\
				}\
				int i_;\
				for (i_ = 1, brk_ = 0, argv_ = argv;\
						argv[0][i_] && !brk_;\
						i_++) {\
					if (argv_ != argv)\
						break;\
					argc_ = argv[0][i_];\
					switch (argc_)

#define ARGEND			}\
			}

#define ARGC()		argc_

#define EARGF(x)	((argv[0][i_+1] == '\0' && argv[1] == NULL)?\
				((x), abort(), (char *)0) :\
				(brk_ = 1, (argv[0][i_+1] != '\0')?\
					(&argv[0][i_+1]) :\
					(argc--, argv++, argv[0])))

#define ARGF()		((argv[0][i_+1] == '\0' && argv[1] == NULL)?\
				(char *)0 :\
				(brk_ = 1, (argv[0][i_+1] != '\0')?\
					(&argv[0][i_+1]) :\
					(argc--, argv++, argv[0])))

#endif
