set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_hashblocks/sha256"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_hashblocks/sha256/ref"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_hashblocks_sha256_ref /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_hashblocks/sha256/ref/blocks.c)
set_target_properties(crypto_hashblocks_sha256_ref PROPERTIES LINKER_LANGUAGE C)
