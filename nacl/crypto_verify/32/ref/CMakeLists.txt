set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_verify/32"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_verify/32/ref"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_verify_32_ref /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_verify/32/ref/verify.c)
set_target_properties(crypto_verify_32_ref PROPERTIES LINKER_LANGUAGE C)
