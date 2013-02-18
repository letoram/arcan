set(CMAKE_CURRENT_BINARY_DIR /home/vdw/Desktop/Code/arcanfe-code/nacl)
include_directories(
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_hash/sha512"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_hash/sha512/ref"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include"
        "/home/vdw/Desktop/Code/arcanfe-code/nacl/include_internal"
    )
add_library(crypto_hash_sha512_ref /home/vdw/Desktop/Code/arcanfe-code/nacl/crypto_hash/sha512/ref/hash.c)
set_target_properties(crypto_hash_sha512_ref PROPERTIES LINKER_LANGUAGE C)
