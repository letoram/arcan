project('test-dirctrl', 'c', default_options : ['c_std=gnu11'])
shmif_srv = dependency('arcan-shmif-srv')
shmif = dependency('arcan-shmif')
a12 = dependency('arcan-a12')
thread = dependency('threads')
cc = meson.get_compiler('c')
math = cc.find_library('m', required : false)
lua = cc.find_library('lua5.1', required : true)
sqlite3 = cc.find_library('sqlite3', required : true)

add_project_arguments(
  '-D_POSIX_C_SOURCE=200809L',
  '-DWANT_KEYSTORE_HASHER',
  '-DARCAN_DB_STANDALONE',
  '-D_GNU_SOURCE',
  '-Wno-unused-function', language : 'c')

dirs = [
  '../../../src/a12',
  '../../../src/a12/net',
  '../../../src/a12/external',
  '../../../src/a12/external/blake3',
  '../../../src/engine',
  '../../../src/frameserver/util',
  '../../../src/platform',
  '/usr/include/lua5.1'
]

executable('test-dirappl',
  [ 'dirctrl.c',
    '../../../src/a12/net/dir_supp.c',
    '../../../src/a12/net/dir_lua.c',
    '../../../src/a12/net/dir_lua_appl.c',
    '../../../src/engine/arcan_db.c',
    '../../../src/platform/posix/mem.c',
    '../../../src/platform/posix/map_resource.c',
    '../../../src/platform/posix/resource_io.c',
    '../../../src/a12/external/fts.c',
    '../../../src/frameserver/util/anet_helper.c',
    '../../../src/a12/net/nbio.c',
    '../../../src/frameserver/util/anet_keystore_naive.c'
  ],
  include_directories: [
    dirs
  ],
	install : true, dependencies : [shmif, a12, sqlite3, shmif_srv, math, thread, lua]
)
