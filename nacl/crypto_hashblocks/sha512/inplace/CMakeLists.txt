set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_hashblocks/sha512"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_hashblocks/sha512/inplace"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_hashblocks_sha512_inplace /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_hashblocks/sha512/inplace/blocks.c)
set_target_properties(crypto_hashblocks_sha512_inplace PROPERTIES LINKER_LANGUAGE C)
