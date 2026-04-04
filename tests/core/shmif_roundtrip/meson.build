project('shmif-roundtrip', 'c',
  default_options : ['c_std=c11']
)

shmif_srv = dependency('arcan-shmif-srv')
thread_dep = dependency('threads')
cc = meson.get_compiler('c')
math_dep = cc.find_library('m', required : false)

add_project_arguments(
  '-D_POSIX_C_SOURCE=200809L',
  '-D__UNIX',
  language : 'c'
)

executable('shmif_roundtrip',
  ['shmif_roundtrip.c'],
  install : true,
  dependencies : [shmif_srv, math_dep, thread_dep]
)
