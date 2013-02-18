set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/aes128ctr"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/aes128ctr/core2"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_stream_aes128ctr_core2 /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/aes128ctr/core2/xor.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/aes128ctr/core2/afternm.s;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/aes128ctr/core2/xor_afternm.s;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/aes128ctr/core2/beforenm.s;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/aes128ctr/core2/stream.c)
set_target_properties(crypto_stream_aes128ctr_core2 PROPERTIES LINKER_LANGUAGE C)
