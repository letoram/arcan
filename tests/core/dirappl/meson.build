project('test-dirappl', 'c', default_options : ['c_std=c11'])
shmif = dependency('arcan-shmif-srv')
thread = dependency('threads')
cc = meson.get_compiler('c')
math = cc.find_library('m', required : false)
add_project_arguments('-D_POSIX_C_SOURCE=200809L', language : 'c')
executable('test-dirappl', ['dirappl.c'],
	install : true, dependencies : [shmif, math, thread])
