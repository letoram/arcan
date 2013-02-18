set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/xsalsa20"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/xsalsa20/ref"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_stream_xsalsa20_ref /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/xsalsa20/ref/xor.c;/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_stream/xsalsa20/ref/stream.c)
set_target_properties(crypto_stream_xsalsa20_ref PROPERTIES LINKER_LANGUAGE C)
