set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_core/salsa20"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_core/salsa20/ref"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_core_salsa20_ref /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_core/salsa20/ref/core.c)
set_target_properties(crypto_core_salsa20_ref PROPERTIES LINKER_LANGUAGE C)
