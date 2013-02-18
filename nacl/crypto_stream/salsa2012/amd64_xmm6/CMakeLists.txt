set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/salsa2012"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/salsa2012/amd64_xmm6"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_stream_salsa2012_amd64_xmm6 /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/salsa2012/amd64_xmm6/stream.s)
set_target_properties(crypto_stream_salsa2012_amd64_xmm6 PROPERTIES LINKER_LANGUAGE C)
